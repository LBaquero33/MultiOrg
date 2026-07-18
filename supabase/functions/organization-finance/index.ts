import {
  ApiFailure,
  fail,
  ok,
  organizationContext,
  record,
  requireCapability,
  rpcFailure,
  text,
  uuid,
} from "../_shared/organization_api.ts";
import { invoiceNextStatus } from "../_shared/organization_operations.ts";

Deno.serve(async (req) => {
  try {
    const payload = record(await req.json());
    const ctx = await organizationContext(req, payload);
    const action = text(payload.action);
    if (action === "account") {
      let query = ctx.admin.from("sd_customer_accounts").select(
        "*,players:sd_customer_account_players(*),invoices:sd_invoices(*),credits:sd_account_credits(*)",
      ).eq("org_id", ctx.organizationId);
      if (!ctx.isAdmin) {
        query = query.or(
          `user_id.eq.${ctx.callerId},responsible_user_id.eq.${ctx.callerId}`,
        );
      }
      const { data, error } = await query.limit(100);
      if (error) throw new ApiFailure(500, "account_lookup_failed");
      return ok({ accounts: data ?? [] });
    }
    requireCapability(ctx.capabilities, "view_financial_overview");
    if (action === "overview") {
      const [invoices, payments, refunds, expenses, accounts] = await Promise
        .all([
          ctx.admin.from("sd_invoices").select("*").eq(
            "org_id",
            ctx.organizationId,
          ).eq("financial_layer", "organization_customer").order("created_at", {
            ascending: false,
          }).limit(200),
          ctx.admin.from("sd_payments").select("*").eq(
            "org_id",
            ctx.organizationId,
          ).eq("financial_layer", "organization_customer").order("created_at", {
            ascending: false,
          }).limit(200),
          ctx.admin.from("sd_refunds").select("*").eq(
            "org_id",
            ctx.organizationId,
          ).eq("financial_layer", "organization_customer").order("created_at", {
            ascending: false,
          }).limit(100),
          ctx.admin.from("sd_expenses").select("*").eq(
            "org_id",
            ctx.organizationId,
          ).eq("financial_layer", "organization_expense").order(
            "expense_date",
            { ascending: false },
          ).limit(200),
          ctx.admin.from("sd_customer_accounts").select("*").eq(
            "org_id",
            ctx.organizationId,
          ).eq("active", true).limit(200),
        ]);
      if (
        [invoices, payments, refunds, expenses, accounts].some((value) =>
          value.error
        )
      ) throw new ApiFailure(500, "finance_lookup_failed");
      return ok({
        invoices: invoices.data ?? [],
        payments: payments.data ?? [],
        refunds: refunds.data ?? [],
        expenses: expenses.data ?? [],
        customer_accounts: accounts.data ?? [],
        provider_actions_enabled: false,
      });
    }
    if (action === "create_invoice") {
      const invoice = record(payload.invoice);
      const requestId = uuid(payload.request_id);
      const invoiceNumber = text(invoice.invoice_number);
      if (!requestId || !invoiceNumber) {
        throw new ApiFailure(400, "invoice_number_and_request_id_required");
      }
      const { data: replay } = await ctx.admin.from("sd_financial_audit_logs")
        .select("target_id").eq("org_id", ctx.organizationId).eq(
          "request_id",
          requestId,
        ).eq("action", "create_invoice").maybeSingle();
      if (replay?.target_id) {
        const { data: prior } = await ctx.admin.from("sd_invoices").select("*")
          .eq("id", replay.target_id).eq("org_id", ctx.organizationId).single();
        return ok({ invoice: prior, replayed: true });
      }
      const items = Array.isArray(payload.items)
        ? payload.items.map(record)
        : [];
      if (!items.length) throw new ApiFailure(400, "invoice_items_required");
      const subtotal = items.reduce(
        (sum, item) => sum + Number(item.total_amount_cents ?? 0),
        0,
      );
      const discount = Number(invoice.discount_cents ?? 0);
      const tax = Number(invoice.tax_cents ?? 0);
      const total = subtotal - discount + tax;
      if (total < 0) throw new ApiFailure(400, "invalid_invoice_total");
      const { data: header, error } = await ctx.admin.from("sd_invoices")
        .insert({
          org_id: ctx.organizationId,
          payer_id: uuid(invoice.payer_id),
          child_id: uuid(invoice.child_id),
          created_by: ctx.callerId,
          customer_account_id: uuid(invoice.customer_account_id),
          season_id: uuid(invoice.season_id),
          team_id: uuid(invoice.team_id),
          registration_application_id: uuid(
            invoice.registration_application_id,
          ),
          invoice_number: invoiceNumber,
          financial_layer: "organization_customer",
          status: "draft",
          currency: text(invoice.currency) || "usd",
          subtotal_cents: subtotal,
          discount_cents: discount,
          tax_cents: tax,
          total_cents: total,
          amount_remaining_cents: total,
          due_date: text(invoice.due_date) || null,
          notes: text(invoice.notes) || null,
          internal_notes: text(invoice.internal_notes) || null,
          payment_terms: text(invoice.payment_terms) || null,
        }).select().single();
      if (error || !header) throw new ApiFailure(409, "invoice_create_failed");
      const { error: itemError } = await ctx.admin.from("sd_invoice_items")
        .insert(items.map((item) => ({
          org_id: ctx.organizationId,
          invoice_id: header.id,
          item_type: text(item.item_type) || "custom",
          description: text(item.description),
          quantity: Number(item.quantity ?? 1),
          unit_amount_cents: Number(item.unit_amount_cents),
          total_amount_cents: Number(item.total_amount_cents),
          taxable: Boolean(item.taxable),
          metadata: record(item.metadata),
        })));
      if (itemError) {
        await ctx.admin.from("sd_invoices").delete().eq("id", header.id).eq(
          "status",
          "draft",
        );
        throw new ApiFailure(409, "invoice_items_create_failed");
      }
      const { error: auditError } = await ctx.admin.from(
        "sd_financial_audit_logs",
      ).insert({
        org_id: ctx.organizationId,
        actor_id: ctx.callerId,
        action: "create_invoice",
        target_type: "invoice",
        target_id: header.id,
        request_id: requestId,
        amount_cents: total,
        details: { invoice_number: invoiceNumber },
      });
      if (auditError) {
        await ctx.admin.from("sd_invoice_items").delete().eq(
          "invoice_id",
          header.id,
        );
        await ctx.admin.from("sd_invoices").delete().eq("id", header.id).eq(
          "status",
          "draft",
        );
        throw new ApiFailure(409, "invoice_idempotency_conflict");
      }
      return ok({ invoice: header, replayed: false });
    }
    if (action === "invoice_state") {
      const next = invoiceNextStatus(
        text(payload.current_status),
        text(payload.invoice_action),
      );
      if (!next) throw new ApiFailure(409, "invalid_invoice_transition");
      const { data, error } = await ctx.admin.rpc("sd_change_invoice_state", {
        p_org_id: ctx.organizationId,
        p_actor_id: ctx.callerId,
        p_invoice_id: uuid(payload.invoice_id),
        p_action: text(payload.invoice_action),
        p_expected_version: Number(payload.expected_version),
        p_request_id: uuid(payload.request_id),
        p_reason: text(payload.reason),
      });
      if (error) rpcFailure(error, "invoice_state_failed");
      return ok({ result: data });
    }
    if (action === "record_payment") {
      const { data, error } = await ctx.admin.rpc("sd_record_manual_payment", {
        p_org_id: ctx.organizationId,
        p_actor_id: ctx.callerId,
        p_customer_account_id: uuid(payload.customer_account_id),
        p_amount_cents: Number(payload.amount_cents),
        p_currency: text(payload.currency) || "usd",
        p_method: text(payload.method),
        p_external_reference: text(payload.external_reference) || null,
        p_allocations: Array.isArray(payload.allocations)
          ? payload.allocations
          : [],
        p_request_id: uuid(payload.request_id),
      });
      if (error) rpcFailure(error, "payment_record_failed");
      return ok({ result: data });
    }
    if (action === "issue_refund" || action === "issue_credit") {
      const { data, error } = await ctx.admin.rpc(
        "sd_issue_financial_adjustment",
        {
          p_org_id: ctx.organizationId,
          p_actor_id: ctx.callerId,
          p_action: action,
          p_target_id: uuid(payload.target_id),
          p_amount_cents: Number(payload.amount_cents),
          p_reason: text(payload.reason),
          p_request_id: uuid(payload.request_id),
        },
      );
      if (error) rpcFailure(error, "financial_adjustment_failed");
      return ok({ result: data });
    }
    if (action === "approve_expense") {
      const { data, error } = await ctx.admin.rpc("sd_approve_expense", {
        p_org_id: ctx.organizationId,
        p_actor_id: ctx.callerId,
        p_expense_id: uuid(payload.expense_id),
        p_expected_version: Number(payload.expected_version),
        p_request_id: uuid(payload.request_id),
      });
      if (error) rpcFailure(error, "expense_approval_failed");
      return ok({ expense: data });
    }
    if (action === "generate_reminders") {
      const { data, error } = await ctx.admin.rpc(
        "sd_generate_financial_reminder_intents",
        {
          p_org_id: ctx.organizationId,
          p_actor_id: ctx.callerId,
          p_as_of: text(payload.as_of) || new Date().toISOString().slice(0, 10),
          p_dry_run: payload.dry_run !== false,
        },
      );
      if (error) rpcFailure(error, "reminder_generation_failed");
      return ok({ result: data });
    }
    throw new ApiFailure(400, "unsupported_action");
  } catch (error) {
    if (error instanceof ApiFailure) {
      return fail(error.status, error.code, error.message);
    }
    return fail(500, "organization_finance_failed");
  }
});
