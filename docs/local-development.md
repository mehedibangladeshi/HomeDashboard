# Local web development

Requirements: Docker, Node.js 22+, Flutter 3.47.5 / Dart 3.13.4. The launcher pins
Supabase CLI 2.118.0. Run from the repository root:

```sh
node tools/local-web.mjs
```

If Flutter is not on PATH, point to the SDK without changing your home directory:

```sh
HOMEDASHBOARD_FLUTTER_SDK=/tmp/flutter-home-management node tools/local-web.mjs
```

Open http://localhost:3000. Enter owner@home.test, manager@home.test or
member@home.test and select the email sign-in button. Read the link in Mailpit
at http://localhost:54324. Use separate browser profiles for simultaneous users.
other@home.test belongs to an isolated second household for authorization tests.
The sample household includes groceries, a recurring chore and a family event.

The launcher starts the real backend, applies pending migrations without
resetting data, seeds fixtures once, generates ignored .local/web.json and runs
Flutter's web server. Google login, Calendar and push are intentionally disabled.
No cloud project, real email delivery or Firebase configuration is needed.

Stop Flutter with Ctrl+C. Stop backend containers separately:

```sh
npx --yes supabase@2.118.0 stop
```

Database reset is destructive to local test data and is never part of routine
startup. To deliberately rebuild disposable fixtures, reset the local database
then rerun the launcher. Never copy test data to production.

## Commit hook

```sh
chmod +x .githooks/commit-msg
git config --local core.hooksPath .githooks
```

Validate the last message with `node tools/check-commit.mjs --last`.

## Verification

```sh
flutter analyze
flutter test
flutter build web --release --dart-define-from-file=.local/web.json
npx --yes supabase@2.118.0 db lint --level warning
npx --yes supabase@2.118.0 test db
```

The real browser acceptance test requires the local web server running:

```sh
npm ci
npx playwright install chromium
npm run test:web
```

It signs in through Mailpit, saves a purchase, queues a purchase while offline,
reloads to replay it, and creates/completes a chore. It leaves test records in
the disposable local household. Screenshots are saved under ignored `.local/`.
Do not hot-restart Flutter during the test.

Use localhost consistently for browser auth; do not mix 127.0.0.1 and localhost
in callback URLs. Phones must use a reachable LAN backend address; Android
emulators use 10.0.2.2. The local launcher is web-only.
