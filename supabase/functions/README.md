# Edge Functions

Configure the following secrets before deployment:

- `FCM_SERVICE_ACCOUNT_JSON`
- `GOOGLE_CLIENT_ID`
- `GOOGLE_CLIENT_SECRET`
- `GOOGLE_OAUTH_REDIRECT_URL`
- `GOOGLE_WEBHOOK_TOKEN`
- `TOKEN_ENCRYPTION_KEY` (base64-encoded 32 random bytes)
- `INTERNAL_FUNCTION_SECRET`
- `CRON_SECRET`
- `APP_INVITE_REDIRECT_URL`

Deploy all function directories and schedule these authenticated HTTP calls from
Supabase Cron or the Dashboard:

- `reminder-dispatch` every five minutes with `x-cron-secret`
- `sync-google-calendar` every fifteen minutes with `x-internal-secret` and `{}`

Google Calendar webhooks invoke `sync-google-calendar` immediately; periodic
sync is the reconciliation fallback.
