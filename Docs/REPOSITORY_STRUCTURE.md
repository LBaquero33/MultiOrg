# Home Plate Repository Structure

`HomePlate.xcodeproj` is generated from `project.yml`. Update the specification and regenerate the project instead of hand-editing `project.pbxproj`.

## Application

- `HomePlate/App`: application entry point and root scene.
- `HomePlate/Core`: shared models, services, state, and runtime infrastructure.
- `HomePlate/DesignSystem`: reusable tokens, components, templates, and previews.
- `HomePlate/Features`: product features grouped by user workflow.
- `HomePlate/Supporting`: assets, entitlements, launch resources, and StoreKit configuration.

## Configuration and tests

- `Configs`: platform Info.plists and local build configuration templates.
- `HomePlateTests`: iOS unit, contract, and render tests.
- `SharedFixtures`: fixtures shared across test suites and backend contracts.

## Backend and documentation

- `supabase/functions`: Edge Functions and shared server contracts.
- `supabase/migrations`: immutable database migration history.
- `Docs`: product boundaries, architecture, audits, and design guidance.

The stable bundle identifiers remain `com.multiorg.app` and `com.multiorg.app.mac` for application continuity. They are runtime identifiers, not source-directory names.
