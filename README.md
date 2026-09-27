# Home Management

A shared household dashboard for spending, chores, reminders, and a dedicated
Google Calendar. The client is a single Flutter codebase targeting Android,
iOS, and web. Supabase provides Postgres, authentication, storage, realtime,
scheduled jobs, and Edge Functions; Firebase Cloud Messaging delivers push
notifications.

## Repository layout

Git identity, task-based commit messages, and agent attribution rules are
defined in [AGENTS.md](AGENTS.md). Every agent must follow them.

- `lib/` — Flutter application and domain modules
- `supabase/migrations/` — database schema, row-level security, and seed helpers
- `supabase/functions/` — reminder and Google Calendar server functions
- `test/` — domain and widget tests
- `docs/adr/` — architectural decisions

## Local setup

For the credential-free local web workflow, run `node tools/local-web.mjs` and
follow [local development](docs/local-development.md). It provisions a real
local Supabase backend and sample family accounts; Google and Firebase remain
disabled. The phased production roadmap is in
[implementation roadmap](docs/implementation-roadmap.md).
Current verification evidence and outstanding release gates are recorded in
[release status](docs/release-status.md).

1. Install the Flutter stable SDK and Supabase CLI.
2. Copy `.env.example` to `.env` and provide the public Supabase values.
3. Start Supabase with `supabase start`, then apply pending migrations with
   `supabase db push --local`. Reset only deliberately disposable local data.
4. Generate platform shells if they are absent: `flutter create .`.
5. Install packages with `flutter pub get`.
6. Run with `flutter run --dart-define-from-file=.env`.

The local Supabase URL must be reachable from the target device. Use the host
machine's LAN address for a physical phone and `10.0.2.2` for an Android
emulator instead of `127.0.0.1`.

## Firebase and Google Calendar

- Add Firebase's `google-services.json` to `android/app/` and
  `GoogleService-Info.plist` to `ios/Runner/` for native push notifications.
- Replace the public Firebase placeholders in
  `web/firebase-messaging-sw.js`; the matching web values belong in `.env`.
- Enable Google and email authentication in Supabase and register
  `io.homemanagement.app://login-callback` as an allowed redirect URL.
- Create one Google Cloud OAuth client with Calendar access. Its callback URL
  must point to the deployed `google-calendar-callback` Edge Function.

Server secrets (`GOOGLE_CLIENT_SECRET`, `GOOGLE_WEBHOOK_TOKEN`, and FCM service
credentials) belong in Supabase secrets, never in `.env` or the Flutter bundle.

Deploy the database and functions with `supabase db push` and
`supabase functions deploy`. The exact server secret list and required reminder
and calendar schedules are in `supabase/functions/README.md`.

## Verification

Run the commands in [local development](docs/local-development.md), including
database and real-browser checks. Database reset is not a deployment step;
production uses forward migrations after staging acceptance.
