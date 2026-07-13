# Home Plate Apple player subscription setup

Create the subscription group **Home Plate Player Access**, then create **Home Plate Player Monthly** with product ID `com.homeplate.player.monthly`, one-month duration, USD 4.99 price, localization, description, and the required review screenshot. Complete App Store agreements, tax, and banking requirements; create a sandbox tester; and configure sandbox testing.

Do not configure the App Store Server Notifications V2 URL to the hosted
Supabase Edge Function yet. It intentionally fails closed because Supabase's
Node compatibility layer cannot run Apple's complete X.509/JWS verifier.
Renewal lifecycle handling must be deployed on a supported verification
runtime first, then forward only verified lifecycle results to Supabase.

For initial StoreKit purchase persistence, set `APPLE_BUNDLE_ID` and
`APPLE_ENVIRONMENT` (`sandbox` or `production`) as Supabase secrets. The iOS
app accepts only `VerificationResult.verified`; Supabase then authorizes the
actor and context, validates the verified transaction metadata, enforces
transaction replay constraints, and updates the subscription and entitlement
tables. No client-provided access boolean is accepted.

Local `.storekit` transactions use the `Xcode` environment and are not accepted
by a backend configured for Apple Sandbox. Use a development-signed app with no
StoreKit configuration attached, or TestFlight, for the end-to-end Sandbox
backend test.
