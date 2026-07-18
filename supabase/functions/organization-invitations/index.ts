import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import {
  ApiFailure,
  fail,
  ok,
  organizationContext,
  record,
  text,
  uuid,
} from "../_shared/organization_api.ts";

const manageActions = new Set(["list", "generate", "rotate", "revoke"]);
const allowedResponsibilities = new Set([
  "head_coach",
  "assistant_coach",
  "team_manager",
  "hitting_coach",
  "pitching_coach",
  "catching_coach",
  "strength_coach",
  "evaluator",
  "read_only",
]);

function environment() {
  const url = text(
    Deno.env.get("SUPABASE_URL") ?? Deno.env.get("DHD_SUPABASE_URL"),
  );
  const anon = text(
    Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("DHD_SUPABASE_ANON_KEY"),
  );
  const service = text(
    Deno.env.get("DHD_SERVICE_ROLE_KEY") ??
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),
  );
  if (!url || !anon || !service) {
    throw new ApiFailure(500, "missing_supabase_secrets");
  }
  return { url, anon, service };
}

function randomToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

async function tokenHash(token: string) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(token),
  );
  return [...new Uint8Array(digest)].map((value) =>
    value.toString(16).padStart(2, "0")
  ).join("");
}

function cleanContext(value: unknown) {
  const context = text(value);
  if (context !== "family" && context !== "staff") {
    throw new ApiFailure(422, "invalid_invitation_context");
  }
  return context;
}

function cleanResponsibilities(value: unknown) {
  const source = Array.isArray(value) ? value : [];
  const cleaned = [
    ...new Set(
      source.map(text).filter((item) => allowedResponsibilities.has(item)),
    ),
  ];
  if (cleaned.length !== source.length) {
    throw new ApiFailure(422, "invalid_staff_responsibility");
  }
  return cleaned;
}

async function publicTokenContext(token: string) {
  if (!token || token.length < 40 || token.length > 100) {
    throw new ApiFailure(404, "invitation_not_found");
  }
  const { url, service } = environment();
  const admin = createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const hash = await tokenHash(token);
  const { data: link, error } = await admin.from(
    "sd_organization_invitation_links",
  )
    .select("*,sd_orgs(name)").eq("token_hash", hash).maybeSingle();
  if (error) throw new ApiFailure(500, "invitation_lookup_failed");
  if (!link) throw new ApiFailure(404, "invitation_not_found");
  if (link.revoked_at) throw new ApiFailure(410, "invitation_revoked");
  if (new Date(link.expires_at) <= new Date()) {
    throw new ApiFailure(410, "invitation_expired");
  }
  return { admin, link };
}

function presentedLink(link: Record<string, unknown>) {
  const organization = record(link.sd_orgs);
  return {
    id: link.id,
    organization_id: link.organization_id,
    organization_name: text(organization.name),
    invitation_context: link.invitation_context,
    intended_role: link.intended_role,
    intended_team_id: link.intended_team_id,
    intended_responsibilities: link.intended_responsibilities ?? [],
    expires_at: link.expires_at,
    revoked_at: link.revoked_at,
    accepted_at: link.accepted_at,
    last_rotated_at: link.last_rotated_at,
    use_count: link.use_count ?? 0,
    token_version: link.token_version,
  };
}

async function authenticatedUser(req: Request) {
  const { url, anon } = environment();
  const token = text(
    (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, ""),
  );
  if (!token) throw new ApiFailure(401, "authentication_required");
  const client = createClient(url, anon, {
    global: { headers: { Authorization: `Bearer ${token}` } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user?.id) {
    throw new ApiFailure(401, "authentication_required");
  }
  return data.user.id;
}

Deno.serve(async (req) => {
  try {
    if (req.method !== "POST") throw new ApiFailure(405, "method_not_allowed");
    const payload = record(await req.json());
    const action = text(payload.action);

    if (action === "validate") {
      const { link } = await publicTokenContext(text(payload.token));
      return ok({ invitation: presentedLink(link) });
    }

    if (action === "accept") {
      const actorId = await authenticatedUser(req);
      const { admin, link } = await publicTokenContext(text(payload.token));
      const organizationId = text(link.organization_id);
      const intendedRole = text(link.intended_role);
      const { data: priorAcceptance } = await admin.from(
        "sd_organization_invitation_acceptances",
      )
        .select("id").eq("invitation_link_id", link.id).eq(
          "accepted_by",
          actorId,
        ).maybeSingle();
      if (priorAcceptance?.id) {
        return ok({ invitation: { ...presentedLink(link), accepted: true } });
      }
      const { data: existing } = await admin.from("sd_org_memberships").select(
        "role,status",
      )
        .eq("org_id", organizationId).eq("user_id", actorId).maybeSingle();
      if (
        existing?.status === "active" && text(existing.role) !== intendedRole
      ) {
        throw new ApiFailure(409, "account_role_mismatch");
      }
      const { error: membershipError } = await admin.from("sd_org_memberships")
        .upsert({
          org_id: organizationId,
          user_id: actorId,
          role: intendedRole,
          status: "active",
        }, { onConflict: "org_id,user_id" });
      if (membershipError) {
        throw new ApiFailure(409, "invitation_acceptance_failed");
      }

      if (intendedRole === "coach" && link.intended_team_id) {
        const { data: team } = await admin.from("sd_teams").select("season_id")
          .eq("id", link.intended_team_id).eq("org_id", organizationId)
          .maybeSingle();
        if (!team?.season_id) {
          throw new ApiFailure(409, "invited_team_unavailable");
        }
        const { data: existingAssignment } = await admin.from(
          "sd_coach_team_assignments",
        )
          .select("id").eq("organization_id", organizationId).eq(
            "team_id",
            link.intended_team_id,
          )
          .eq("coach_id", actorId).eq("active", true).is("ended_at", null)
          .maybeSingle();
        let assignmentId = existingAssignment?.id;
        if (!assignmentId) {
          const { data: assignment, error } = await admin.from(
            "sd_coach_team_assignments",
          ).insert({
            coach_id: actorId,
            organization_id: organizationId,
            season_id: team.season_id,
            team_id: link.intended_team_id,
            is_primary: false,
            organization_wide_access: false,
            created_by: link.created_by,
            updated_by: link.created_by,
          }).select("id").single();
          if (error) throw new ApiFailure(409, "coach_assignment_failed");
          assignmentId = assignment.id;
        }
        const responsibilities = cleanResponsibilities(
          link.intended_responsibilities,
        );
        if (responsibilities.length) {
          const { error } = await admin.from("sd_coach_team_responsibilities")
            .upsert(
              responsibilities.map((responsibility) => ({
                assignment_id: assignmentId,
                responsibility,
                created_by: link.created_by,
              })),
              {
                onConflict: "assignment_id,responsibility",
                ignoreDuplicates: true,
              },
            );
          if (error) throw new ApiFailure(409, "coach_responsibility_failed");
        }
      }

      const acceptedAt = new Date().toISOString();
      const { error: auditError } = await admin.from(
        "sd_organization_invitation_acceptances",
      ).upsert({
        invitation_link_id: link.id,
        organization_id: organizationId,
        accepted_by: actorId,
        accepted_role: intendedRole,
        accepted_at: acceptedAt,
        details: {
          invitation_context: link.invitation_context,
          token_version: link.token_version,
        },
      }, { onConflict: "invitation_link_id,accepted_by" });
      if (auditError) throw new ApiFailure(500, "invitation_audit_failed");
      await admin.from("sd_organization_invitation_links").update({
        accepted_at: acceptedAt,
        use_count: Number(link.use_count ?? 0) + 1,
        updated_at: acceptedAt,
      }).eq("id", link.id);
      return ok({ invitation: { ...presentedLink(link), accepted: true } });
    }

    if (!manageActions.has(action)) {
      throw new ApiFailure(400, "unsupported_action");
    }
    const ctx = await organizationContext(req, payload, {
      allowPlatformAdmin: true,
    });
    if (!ctx.isAdmin && !ctx.isPlatformAdmin) {
      throw new ApiFailure(403, "invitation_management_required");
    }
    const context = payload.invitation_context == null
      ? null
      : cleanContext(payload.invitation_context);

    if (action === "list") {
      const { data, error } = await ctx.admin.from(
        "sd_organization_invitation_links",
      )
        .select("*,sd_orgs(name)").eq("organization_id", ctx.organizationId)
        .order("created_at", { ascending: false });
      if (error) throw new ApiFailure(500, "invitation_list_failed");
      return ok({ links: (data ?? []).map(presentedLink) });
    }

    if (action === "revoke") {
      const linkId = uuid(payload.link_id);
      if (!linkId) throw new ApiFailure(422, "invitation_link_required");
      const { data, error } = await ctx.admin.from(
        "sd_organization_invitation_links",
      ).update({
        revoked_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }).eq("id", linkId).eq("organization_id", ctx.organizationId).select(
        "*,sd_orgs(name)",
      ).single();
      if (error) throw new ApiFailure(404, "invitation_not_found");
      return ok({ link: presentedLink(data), invitation_url: null });
    }

    if (!context) throw new ApiFailure(422, "invitation_context_required");
    const responsibilities = context === "staff"
      ? cleanResponsibilities(payload.intended_responsibilities)
      : [];
    const teamId = context === "staff" ? uuid(payload.intended_team_id) : null;
    if (teamId) {
      const { data } = await ctx.admin.from("sd_teams").select("id").eq(
        "id",
        teamId,
      )
        .eq("org_id", ctx.organizationId).eq("is_active", true).maybeSingle();
      if (!data) throw new ApiFailure(422, "invited_team_unavailable");
    }
    const now = new Date();
    const expiresAt = new Date(
      now.getTime() +
        Math.min(90, Math.max(1, Number(payload.expires_in_days) || 30)) *
          86400000,
    );
    let nextVersion = 1;
    if (action === "rotate") {
      const { data: current } = await ctx.admin.from(
        "sd_organization_invitation_links",
      )
        .select("token_version").eq("organization_id", ctx.organizationId)
        .eq("invitation_context", context).is("revoked_at", null).maybeSingle();
      nextVersion = Number(current?.token_version ?? 0) + 1;
    }
    await ctx.admin.from("sd_organization_invitation_links").update({
      revoked_at: now.toISOString(),
      updated_at: now.toISOString(),
    }).eq("organization_id", ctx.organizationId).eq(
      "invitation_context",
      context,
    ).is("revoked_at", null);
    const token = randomToken();
    const hash = await tokenHash(token);
    const { data, error } = await ctx.admin.from(
      "sd_organization_invitation_links",
    ).insert({
      organization_id: ctx.organizationId,
      invitation_context: context,
      intended_role: context === "family" ? "parent" : "coach",
      intended_team_id: teamId,
      intended_responsibilities: responsibilities,
      token_hash: hash,
      token_version: nextVersion,
      expires_at: expiresAt.toISOString(),
      last_rotated_at: action === "rotate" ? now.toISOString() : null,
      created_by: ctx.callerId,
    }).select("*,sd_orgs(name)").single();
    if (error) throw new ApiFailure(409, "invitation_generation_failed");
    const base = text(Deno.env.get("HOME_PLATE_INVITE_BASE_URL")) ||
      "homeplate://invite/";
    return ok({
      link: presentedLink(data),
      invitation_url: `${base}${encodeURIComponent(token)}`,
    });
  } catch (error) {
    if (error instanceof ApiFailure) return fail(error.status, error.code);
    console.error(
      "organization_invitation_failed",
      error instanceof Error ? error.name : "unknown",
    );
    return fail(500, "organization_invitation_failed");
  }
});
