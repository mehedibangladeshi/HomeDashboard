# Release status — 2026-09-27

The local web milestone is running and verified. This is not a completed
production release or a claim that every roadmap acceptance gate has passed.

## Verified on this workstation

- Real Docker Supabase with forward migrations through 202609270011; Mailpit
  email-link sign-in and separate Owner/Manager/Member fixture accounts.
- Flutter analysis: no issues. Flutter tests: 14 passed, including exact money
  parsing, offline account isolation, partial receipt retry and serialized sync.
- Database tests: 42 passed across tenant access, role permissions, invitations,
  receipt access, ownership, corrections, rolling schedules and payment retries.
- Database lint: no schema errors. Seven Edge Function entrypoints pass Deno
  type checking. Commit-message validation tests pass.
- Chromium acceptance: real email sign-in; purchase persists after reload;
  offline purchase survives reload and replays; chore creation and completion;
  no uncaught browser errors. Screenshot: ignored .local/web-acceptance.png.
- Flutter web release compilation succeeds with local public configuration.

## Implemented foundations

Local launcher, role/tenant safeguards, canonical receipt access, invitation
acceptance, household recovery entrypoint, authoritative Today/month summaries,
historical analytics periods, expense detail/correction/void flows, recording
recurring payments, chore/event editing, notification inbox, and durable
account-scoped IndexedDB/SQLite command queues with retry status.

Cloud integrations are disabled locally. OAuth callback state is claimed
atomically and Owner access is rechecked. Calendar imports trust stored
household mappings, not caller-supplied entity identifiers. Reminder dispatch
fails closed without its worker secret. These are code safeguards, not proof
that live Google or push integrations work.

CI configuration, Firebase Hosting configuration, public-value configuration
template, Android release-signing requirement and a production runbook are
prepared. CI has not run on GitHub. Native builds/signing have not been verified
on this workstation; SQLite is covered through queue abstractions, not a real
Android/iPhone installation.

## Remaining gates

| Area | Still required before declaring completion |
| --- | --- |
| Local workflows | Full ledger pagination/search; complete purchase payer/date/note/itemization UX; category budget progress; full three-role browser acceptance |
| Integrity/offline | Concurrent ownership stress tests; deletion/purge job suspension coverage; device storage/privacy review; restart/multi-tab lease expiry tests; legacy outbox migration |
| Staging/production | Actual hostname, DNS, Supabase/Firebase project access, verified SMTP; explicit staged migrations/functions and hosted acceptance |
| Push | Real FlutterFire configuration, APNs/VAPID, token cleanup, claimed/retryable delivery jobs, quiet hours and physical-device delivery tests |
| Calendar | Live OAuth; worker locking, sync conflict handling/reconciliation, watch renewal/revocation and webhook/expiry tests |
| Native | Android toolchain/device and release keystore; Mac/Xcode, Apple team, iPhone, signed APK and TestFlight installation tests |
| Operations | Encrypted DB plus receipt backups, isolated restore drill, monitoring, rollback demonstration and seven-day family pilot |

Do not enable production integration flags merely because configuration files
exist. Supply secrets only through ignored local files or provider secret
stores. Public identifiers and account availability can be shared in chat.

## Try the local app

Open http://localhost:3000 and sign in as owner@home.test. Open the email link
from http://localhost:54324. Use separate browser profiles for manager@home.test
and member@home.test. Launch instructions are in local-development.md; cloud
handoff instructions are in production-runbook.md.
