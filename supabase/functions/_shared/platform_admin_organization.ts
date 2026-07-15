export type PlatformOrganizationCreationInput = {
  name: string;
  slug: string;
  plan: string;
  billingEmail: string | null;
  maxMembers: number | null;
};

export type PlatformOrganizationCreationRPCArguments = {
  p_actor_id: string;
  p_name: string;
  p_slug: string;
  p_plan: string;
  p_billing_email: string | null;
  p_max_members: number | null;
};

/**
 * The actor ID is supplied separately from the browser payload and comes only
 * from the authenticated Supabase session. There is deliberately no owner ID
 * field in the client-controlled input.
 */
export function platformOrganizationCreationRPCArguments(
  authenticatedActorId: string,
  input: PlatformOrganizationCreationInput,
): PlatformOrganizationCreationRPCArguments {
  return {
    p_actor_id: authenticatedActorId,
    p_name: input.name,
    p_slug: input.slug,
    p_plan: input.plan,
    p_billing_email: input.billingEmail,
    p_max_members: input.maxMembers,
  };
}
