# Test strategy

Run unit and widget tests on every change, then validate database policies against
a local Supabase project. The minimum authorization matrix covers every role
attempting to read and mutate each household-owned table, cross-household IDs,
last-Owner changes, Member expense submissions, receipt paths, and Owner export.

Google Calendar integration tests should use a separate test calendar and cover
initial sync, incremental tokens, invalid token recovery, webhook duplication,
missed-webhook reconciliation, app/Google update conflicts, redacted Obligation
events, cancellations, and watch renewal. Push tests cover token rotation, quiet
hours, duplicate reminder runs, and invalid device tokens.
