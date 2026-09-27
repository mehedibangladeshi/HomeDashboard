# HomeDashboard implementation roadmap

Approved target: family-first web on an existing custom domain, signed Android
APK, and iOS TestFlight. Managed Supabase, Firebase Hosting/FCM and SMTP use free
tiers; Apple Developer membership is the agreed exception. A Mac and iPhone
are available. Public app stores, banking and receipt OCR are outside this pilot.

## Phases and acceptance gates

| Phase | Tasks | Completion evidence |
| --- | --- | --- |
| 0: Baseline | Human-identity task commits, tool versions, environment separation, commit validation, runbooks | Fresh checkout reproduces checks with no secrets in Git |
| 1: Local web | Docker Supabase, forward migrations, local fixtures, Mailpit email links, correct web callbacks, integration flags, localhost launcher | Browser signs in and persists purchases/chores with no cloud account |
| 2: Integrity | RLS/RPC audit, role matrix, household reference validation, concurrent ownership protection, invitation acceptance, receipt access, deletion suspension/recovery/purge | Anonymous, cross-household and role-escalation tests fail safely |
| 3: Workflows | Live Today dashboard, purchase details/category/payer/date/items/receipts, historical analytics, budgets/payment recording, chore/event edits, notification inbox, export/recovery | Owner/Manager/Member acceptance journeys pass |
| 4: Offline | Account-scoped transactional storage, durable commands/receipts, idempotent replay, partial-upload recovery, retry states, cache invalidation | Reload/reconnection cannot lose, duplicate or expose another user's actions |
| 5: Cloud | Separate staging/production, SMTP/domain DNS, secrets, forward deploys, invite-only production bootstrap, hosted smoke tests | Staging works with real users before production promotion |
| 6: Push | FlutterFire, VAPID/service worker, APNs, token lifecycle, permission flow, durable claimed jobs/retries, quiet hours, private lock-screen payloads | Browser/Android/iPhone receive reminders and authenticated navigation |
| 7: Calendar | Separate login/calendar OAuth, atomic state, owner recheck, encrypted tokens, watch renewal, incremental sync, reconciliation, conflicts, revocation | Two-way schedule edits converge without duplication or financial disclosure |
| 8: Native | Android toolchain, permanent IDs, release keystore, Xcode signing/APNs, physical-device journeys, APK/TestFlight delivery | Family installs signed apps from the tested release revision |
| 9: Operations | CI gates, controlled promotion, sanitized errors, uptime/quota checks, daily encrypted DB/object backups, isolated restore drill, rollback, seven-day pilot | Three production clients pass acceptance and recovery is demonstrated |

## Defaults and invariants

- One household per account; BDT and Asia/Dhaka onboarding defaults.
- Owners govern roles, export, Calendar connection and deletion. Managers
  operate finances and ordinary membership. Members submit expenses for review.
- Monthly non-rolling category budgets; amounts stored in integer minor units.
- Offline purchases and chore completion first; other writes require connectivity.
- OAuth integrations stay disabled until configured, never simulated as working.
- Google edits affect schedules, never payment amounts, approval or completion.
- Conflict detection preserves both versions for explicit user resolution.
- Local fixture creation and destructive local reset never target cloud projects.
- Every coherent task gets a small commit under AGENTS.md; no AI attribution.

## Provider dependencies and operating limits

Cloud phases require the chosen hostname/DNS access, project credentials,
verified SMTP sender, Apple membership/signing access, Mac/iPhone access and an
Android test device. Secrets go into ignored configuration or provider stores.
Free Supabase may pause inactive projects. TestFlight builds expire after 90
days; renew builds before expiry. Google Calendar OAuth testing tokens can
expire after seven days; configure the production consent/verification flow.
Backups must include Storage objects separately from Postgres data.

## Required verification

Unit/widget checks; local pgTAP role/tenant tests; real Auth/REST/Storage/Edge
Function integration tests; browser journeys; physical Android/iOS tests;
offline restart/account-switch/retry tests; concurrent owner changes;
recurrence/timezone boundaries; push retries/quiet hours; Calendar webhook,
etag, expiry and renewal tests; restore and release rollback drills.

## Evidence log

The existing MVP passed static analysis, eight domain tests, web release build,
Deno type checks and fresh database migration/lint checks before this roadmap.
Those checks do not establish production readiness. Record new evidence and
remaining dependencies in release-status.md as implementation progresses.
