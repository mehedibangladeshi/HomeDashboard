# Session handoff — 2026-09-27

## User feedback and next-session priority

The web version looks like a mobile app. Improve it into a deliberate desktop
web experience, while keeping a frictionless mobile experience. There is still
substantial work before the final version. The local milestone is a functional
foundation, not product acceptance or production readiness.

The user does not currently have the requested production hostname/project
identifiers/Apple Developer membership ready. Do not block local improvements
on cloud setup. A custom domain is optional for an initial hosted pilot.

## Session outcome

- Set repository-local human identity and documented/enforced task commit
  rules in AGENTS.md; no AI attribution.
- Established a real local Supabase backend and credential-free web launcher,
  email sign-in through Mailpit, and separate household role fixtures.
- Implemented live dashboard data, spending details/corrections, historical
  analytics, recurring payment recording, chore/event edits, invitations,
  household recovery and a notification inbox.
- Added account-scoped transactional offline queues and retry/replay safeguards.
- Strengthened database role/tenant integrity, receipts, invitation acceptance,
  rolling schedules, payment retries and provider worker safeguards.
- Prepared CI, Hosting configuration, signing safeguards and deployment docs.
- Verified 14 Flutter tests, 42 database tests, clean analysis/database lint,
  Edge Function type checks, web release compilation and a real Chromium
  sign-in/purchase/offline/chore journey. These checks do not cover all roles,
  physical devices or live cloud integrations.

## Next-session plan

1. Inspect the current app in a wide browser and capture the user-visible layout.
   Agree on a compact desktop layout direction before a large visual rewrite.
   Prioritize persistent side navigation, a useful top bar, multi-column Today
   content, richer spending tables and a wider calendar/detail workspace.
   Use available width intentionally; avoid merely enlarging mobile cards.
2. Implement responsive shell and page layouts with explicit compact, medium
   and wide behavior. Preserve mobile quick entry, keyboard access, sensible
   focus order, readable spacing and role-dependent navigation/actions.
3. Verify desktop/tablet/mobile widths, scrolling, modal sizing and overflow.
   Add responsive widget/browser tests and screenshots; rerun existing journeys
   so layout changes do not regress sign-in, spending or offline replay.
4. Complete local product workflows: ledger pagination/search/filtering;
   purchase payer/date/note/itemization UX; budget spending/progress views;
   clearer empty/loading/error states and full Owner/Manager/Member journeys.
5. Strengthen integrity/offline tests: concurrent Owner changes, deletion job
   suppression, receipt failures, restart/account switching, multi-tab lease
   expiry, legacy queue migration and device privacy/storage review.
6. Only then proceed through staging, push, Calendar, native signing and
   operations gates in implementation-roadmap.md. Request provider access at
   the point it is needed, and never request secrets in chat.

Keep tasks small and make task-formatted commits under AGENTS.md. Do not
reimplement completed backend foundations during the web layout work.

## Resume locally

```sh
HOMEDASHBOARD_FLUTTER_SDK=/tmp/flutter-home-management node tools/local-web.mjs
```

Use installed Flutter if the temporary SDK no longer exists. Prerequisites and
version pins are in local-development.md. The launcher applies forward local
migrations without resetting data; never run a destructive reset routinely.

Web: http://localhost:3000. Mailpit: http://localhost:54324. Sign in as
owner@home.test, manager@home.test or member@home.test using separate browser
profiles. Google login/Calendar and push remain disabled locally.

Ignored .local/ holds generated public configuration and browser screenshots.
Do not commit secrets, local fixture output, build files or dependency caches.

## Source of truth

- implementation-roadmap.md: phases, invariants and acceptance gates.
- release-status.md: actual verification evidence and unfinished work.
- production-runbook.md: staged deployment, signing and operations requirements.
- local-development.md: startup and verification commands.
- AGENTS.md: identity and commit rules for every future agent.

No production deployment, signed native release or completed family pilot has
occurred. Check GitHub CI results after this session's push; they were not part
of the local verification evidence.
