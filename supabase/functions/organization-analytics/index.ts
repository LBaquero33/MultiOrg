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
import { rowsToCSV } from "../_shared/organization_operations.ts";

Deno.serve(async (req) => {
  try {
    const payload = record(await req.json());
    const ctx = await organizationContext(req, payload);
    const action = text(payload.action);
    if (action === "team_summary") {
      const { data, error } = await ctx.admin.rpc("sd_team_analytics", {
        p_organization_id: ctx.organizationId,
        p_actor_id: ctx.callerId,
        p_team_id: uuid(payload.team_id),
        p_from: text(payload.from),
        p_to: text(payload.to),
      });
      if (error) rpcFailure(error, "team_analytics_failed");
      return ok({ analytics: data });
    }
    requireCapability(ctx.capabilities, "view_org_analytics");
    if (action === "dashboard") {
      const { data, error } = await ctx.admin.rpc("sd_organization_analytics", {
        p_organization_id: ctx.organizationId,
        p_actor_id: ctx.callerId,
        p_filters: record(payload.filters),
      });
      if (error) rpcFailure(error, "analytics_failed");
      const { data: definitions } = await ctx.admin.from(
        "sd_metric_definitions",
      ).select("*").order("domain").order("name");
      return ok({ analytics: data, definitions: definitions ?? [] });
    }
    if (action === "export") {
      const reportType = text(payload.report_type);
      const configs: Record<
        string,
        { table: string; scope: string; columns: string[] }
      > = {
        financial_summary: {
          table: "sd_invoices",
          scope: "org_id",
          columns: [
            "id",
            "invoice_number",
            "status",
            "total_cents",
            "amount_paid_cents",
            "amount_remaining_cents",
            "currency",
            "issue_date",
            "due_date",
          ],
        },
        receivables_aging: {
          table: "sd_invoices",
          scope: "org_id",
          columns: [
            "id",
            "invoice_number",
            "customer_account_id",
            "status",
            "amount_remaining_cents",
            "currency",
            "due_date",
          ],
        },
        revenue_detail: {
          table: "sd_payments",
          scope: "org_id",
          columns: [
            "id",
            "amount_cents",
            "currency",
            "payment_method_type",
            "status",
            "received_at",
          ],
        },
        expense_detail: {
          table: "sd_expenses",
          scope: "org_id",
          columns: [
            "id",
            "vendor",
            "category",
            "amount_cents",
            "currency",
            "expense_date",
            "reimbursable",
            "reimbursement_status",
          ],
        },
        registration_status: {
          table: "sd_registration_applications",
          scope: "organization_id",
          columns: [
            "id",
            "season_id",
            "offering_id",
            "state",
            "fee_status",
            "balance_cents",
            "created_at",
          ],
        },
        team_roster: {
          table: "sd_player_team_memberships",
          scope: "organization_id",
          columns: [
            "id",
            "season_id",
            "team_id",
            "player_id",
            "active",
            "started_at",
            "ended_at",
          ],
        },
        attendance: {
          table: "sd_event_operation_participants",
          scope: "organization_id",
          columns: [
            "id",
            "season_id",
            "team_id",
            "event_id",
            "user_id",
            "attendance_status",
            "arrival_at",
            "departure_at",
          ],
        },
        availability: {
          table: "sd_event_operation_participants",
          scope: "organization_id",
          columns: [
            "id",
            "season_id",
            "team_id",
            "event_id",
            "user_id",
            "availability_status",
            "expected_arrival_at",
            "expected_departure_at",
          ],
        },
        schedule: {
          table: "sd_team_events",
          scope: "organization_id",
          columns: [
            "id",
            "season_id",
            "team_id",
            "event_type",
            "title",
            "status",
            "start_at",
            "end_at",
            "location_name",
          ],
        },
        practice_completion: {
          table: "sd_team_events",
          scope: "organization_id",
          columns: [
            "id",
            "season_id",
            "team_id",
            "title",
            "status",
            "start_at",
            "end_at",
          ],
        },
        game_completion: {
          table: "sd_team_events",
          scope: "organization_id",
          columns: [
            "id",
            "season_id",
            "team_id",
            "title",
            "status",
            "start_at",
            "end_at",
          ],
        },
        communication_delivery: {
          table: "sd_notification_intent_receipts",
          scope: "organization_id",
          columns: [
            "id",
            "source_type",
            "category",
            "delivery_state",
            "preference_decision",
            "failure_reason",
            "created_at",
          ],
        },
        missing_requirements: {
          table: "sd_registration_requirement_responses",
          scope: "organization_id",
          columns: [
            "id",
            "application_id",
            "requirement_template_id",
            "required_version",
            "accepted_version",
            "status",
            "expires_at",
          ],
        },
        season_summary: {
          table: "sd_seasons",
          scope: "organization_id",
          columns: [
            "id",
            "name",
            "start_date",
            "end_date",
            "status",
            "is_default",
          ],
        },
      };
      const config = configs[reportType];
      if (!config) throw new ApiFailure(400, "unsupported_report_type");
      const { table, scope: scopeColumn, columns } = config;
      let query = ctx.admin.from(table).select(columns.join(",")).eq(
        scopeColumn,
        ctx.organizationId,
      );
      if (reportType === "practice_completion") {
        query = query.eq("event_type", "practice");
      }
      if (reportType === "game_completion") {
        query = query.eq("event_type", "game");
      }
      const filters = record(payload.filters);
      if (uuid(filters.season_id) && columns.includes("season_id")) {
        query = query.eq("season_id", uuid(filters.season_id)!);
      }
      if (uuid(filters.team_id) && columns.includes("team_id")) {
        query = query.eq("team_id", uuid(filters.team_id)!);
      }
      const { data, error } = await query.limit(5000);
      if (error) throw new ApiFailure(500, "report_query_failed");
      const rows = (data ?? []) as unknown as Record<string, unknown>[];
      const asOf = new Date().toISOString();
      const { data: run, error: runError } = await ctx.admin.from(
        "sd_report_runs",
      ).insert({
        organization_id: ctx.organizationId,
        requested_by: ctx.callerId,
        report_type: reportType,
        filters: record(payload.filters),
        format: "csv",
        row_count: rows.length,
        redaction_profile: "organization_finance_admin",
        as_of: asOf,
      }).select().single();
      if (runError) throw new ApiFailure(500, "report_audit_failed");
      return ok({
        report_run: run,
        filename: `${reportType}-${asOf.slice(0, 10)}.csv`,
        content_type: "text/csv",
        csv: rowsToCSV(rows, columns),
        as_of: asOf,
      });
    }
    throw new ApiFailure(400, "unsupported_action");
  } catch (error) {
    if (error instanceof ApiFailure) {
      return fail(error.status, error.code, error.message);
    }
    return fail(500, "organization_analytics_failed");
  }
});
