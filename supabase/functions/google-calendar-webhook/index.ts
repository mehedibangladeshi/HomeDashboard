import { json } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  if (
    request.headers.get("x-goog-channel-token") !==
      Deno.env.get("GOOGLE_WEBHOOK_TOKEN")
  ) {
    return json({ error: "Invalid channel token" }, 401);
  }
  const channelId = request.headers.get("x-goog-channel-id");
  if (!channelId) return json({ error: "Missing channel id" }, 400);
  const supabase = serviceClient();
  const { data: connection } = await supabase
    .from("calendar_connections")
    .select("household_id")
    .eq("channel_id", channelId)
    .maybeSingle();
  if (!connection) return json({ ok: true });
  const response = await fetch(
    `${Deno.env.get("SUPABASE_URL")}/functions/v1/sync-google-calendar`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-internal-secret": Deno.env.get("INTERNAL_FUNCTION_SECRET")!,
      },
      body: JSON.stringify({ householdId: connection.household_id }),
    },
  );
  return json({ accepted: response.ok }, response.ok ? 202 : 500);
});
