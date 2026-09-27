import { createHash } from "node:crypto";
import {
  encryptSecret,
  exchangeCode,
  googleRequest,
} from "../_shared/google.ts";
import { serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (request) => {
  const url = new URL(request.url);
  const code = url.searchParams.get("code");
  const state = url.searchParams.get("state");
  if (!code || !state) {
    return new Response("Missing code or state", { status: 400 });
  }
  const stateHash = createHash("sha256").update(state).digest("hex");
  const supabase = serviceClient();
  const { data: oauthState } = await supabase
    .from("google_oauth_states")
    .select("household_id, user_id, expires_at, used_at")
    .eq("state_hash", stateHash)
    .single();
  if (
    !oauthState || oauthState.used_at ||
    new Date(oauthState.expires_at) < new Date()
  ) {
    return new Response("OAuth state is invalid or expired", { status: 400 });
  }
  try {
    const token = await exchangeCode(code);
    if (!token.refresh_token) {
      throw new Error("Google did not return a refresh token");
    }
    const { data: household } = await supabase
      .from("households")
      .select("name, time_zone")
      .eq("id", oauthState.household_id)
      .single();
    if (!household) throw new Error("Household no longer exists");
    const calendar = await googleRequest<{ id: string }>(
      token.access_token,
      "/calendars",
      {
        method: "POST",
        body: JSON.stringify({
          summary: `${household.name} · Home Management`,
          timeZone: household.time_zone,
        }),
      },
    );
    const channelId = crypto.randomUUID();
    const expiration = Date.now() + 6 * 24 * 60 * 60 * 1000;
    const channel = await googleRequest<
      { resourceId: string; expiration?: string }
    >(
      token.access_token,
      `/calendars/${encodeURIComponent(calendar.id)}/events/watch`,
      {
        method: "POST",
        body: JSON.stringify({
          id: channelId,
          type: "web_hook",
          address: `${
            Deno.env.get("SUPABASE_URL")
          }/functions/v1/google-calendar-webhook`,
          token: Deno.env.get("GOOGLE_WEBHOOK_TOKEN"),
          expiration: String(expiration),
        }),
      },
    );
    await supabase.from("calendar_connections").upsert({
      household_id: oauthState.household_id,
      owner_user_id: oauthState.user_id,
      google_calendar_id: calendar.id,
      encrypted_refresh_token: await encryptSecret(token.refresh_token),
      channel_id: channelId,
      channel_resource_id: channel.resourceId,
      channel_expires_at: new Date(Number(channel.expiration ?? expiration))
        .toISOString(),
      updated_at: new Date().toISOString(),
    });
    await supabase.from("google_oauth_states").update({
      used_at: new Date().toISOString(),
    }).eq("state_hash", stateHash);
    return new Response(
      "Calendar connected. You can return to Home Management.",
      {
        headers: { "Content-Type": "text/plain; charset=utf-8" },
      },
    );
  } catch (error) {
    return new Response(
      error instanceof Error ? error.message : "Calendar connection failed",
      { status: 500 },
    );
  }
});
