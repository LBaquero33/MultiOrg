# First Organization Administrator

The multi-org backend intentionally starts with no user accounts. Set the
`COACH_SIGNUP_CODE` Edge Function secret in Supabase, then create the first
coach account from the desktop app. A coach is an organization administrator in
this product and receives the **Org Admin** destination after sign-in.

1. In Supabase Dashboard → Edge Functions → Secrets, set a strong
   `COACH_SIGNUP_CODE`.
2. In the app choose the organization, choose **Create Account**, choose
   **Coach**, and enter that code.
3. Sign in through the desktop app. **Org Admin** appears in the coach sidebar.

After first sign-in, create players, parents, coaches, facilities, terminology,
and feature settings through Org Admin. Rotate the setup code once the initial
staff accounts are created.
