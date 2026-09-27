# Production setup and release gates

This runbook prepares deployment; configuration templates do not imply a live
or production-approved release. Use docs/implementation-roadmap.md for gates.

## Accounts and configuration

1. Select the existing domain's app hostname; obtain DNS access.
2. Create staging and production Supabase projects. Keep test fixtures local.
3. Create Firebase Hosting/FCM projects. Enable custom-domain Hosting and wait
   for HTTPS certificate verification before setting auth callbacks.
4. Configure SMTP with a verified sender domain. Test a recipient outside the
   Supabase project team, not just the project owner's email.
5. Copy config/production.json.example into ignored .local/production.json.
   Replace public values. Leave integration flags disabled until verified.
6. Configure backend secrets listed in supabase/functions/README.md directly
   in provider secret stores. Never place service-role keys in the client.
7. Configure Google login and Calendar OAuth clients separately. Allow only
   actual staging/production callback URLs and the native app callback.

## Deployment order

Use a tested Git revision. Select the staging project explicitly before every
remote database operation; verify the linked project reference. Apply forward
migrations with `supabase db push`, deploy Edge Functions, and set scheduled
worker HTTP calls with secrets held in Supabase Vault. Never run a remote reset.

Build web with `flutter build web --release --dart-define-from-file=.local/production.json`.
Deploy with `firebase deploy --only hosting --project ACTUAL_PROJECT_ID` only
after the selected project's API smoke tests pass. The Firebase configuration
sets SPA routing and avoids stale HTML/JavaScript caches.

Repeat staging authentication, permissions, uploads, reminders and Calendar
tests before promoting production. Use production accounts without test data.

## Native distribution

Android: create and securely back up a release keystore. Configure
android/key.properties using android/key.properties.example. A release build
must never use debug signing. Archive the signed APK checksum and version.

iOS: on the Mac, configure Apple Developer membership, the permanent bundle
identifier, signing team, APNs key and background notification capabilities.
Register the Firebase Apple app, then test on the physical iPhone before an
archive is uploaded to TestFlight. Renew builds before the 90-day expiry.

FlutterFire must generate and wire the native configuration and web service
worker settings; placing files on disk alone does not prove push works.

## Operations and recovery

Before real household use: configure daily encrypted database exports and a
separate export of private receipt objects, copied to two user-controlled
locations. Restore into an isolated environment and verify login, memberships,
ledger reconciliation and receipt availability. Record actual recovery time.
Do not put decrypted backups, receipt data or tokens in GitHub artifacts.

Monitor app/API availability, cron execution, failed deliveries, Calendar sync
age, free-tier quotas and project-pausing notices. Logs must omit credentials,
receipt content and financial notes.

Rollback web Hosting to the previous verified release; distribute a corrected
APK/TestFlight version for native defects. Database changes use forward repair
migrations and require compatibility with existing installed clients.

Do not declare the final release complete until all physical-device tests,
backup restoration, required OAuth review and the seven-day family pilot pass.
