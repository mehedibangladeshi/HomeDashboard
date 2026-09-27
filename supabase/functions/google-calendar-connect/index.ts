import { createHash } from "node:crypto";
import { corsHeaders, json } from "../_shared/http.ts";
import { serviceClient, userClient } from "../_shared/supabase.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  const authorization = request.headers.get("authorization");
  if (!authorization) return json({ error: "Authentication required" }, 401);
  const client = userClient(authorization);
  const { data: { user } } = await client.auth.getUser();
  if (!user) return json({ error: "Authentication required" }, 401);
  const { householdId } = await request.json();
  const { data: membership } = await client
    .from("memberships")
    .select("role")
    .eq("household_id", householdId)
    .eq("user_id", user.id)
    .single();
  if (membership?.role !== "owner") {
    return json({ error: "Owner access required" }, 403);
  }

  const state = crypto.randomUUID() + crypto.randomUUID();
  const stateHash = createHash("sha256").update(state).digest("hex");
  const admin = serviceClient();
  await admin.from("google_oauth_states").insert({
    state_hash: stateHash,
    household_id: householdId,
    user_id: user.id,
    expires_at: new Date(Date.now() + 10 * 60_000).toISOString(),
  });
  const query = new URLSearchParams({
    client_id: Deno.env.get("GOOGLE_CLIENT_ID")!,
    redirect_uri: Deno.env.get("GOOGLE_OAUTH_REDIRECT_URL")!,
    response_type: "code",
    access_type: "offline",
    prompt: "consent",
    scope: "https://www.googleapis.com/auth/calendar",
    state,
  });
  return json({
    authorizationUrl: `https://accounts.google.com/o/oauth2/v2/auth?${query}`,
  });
});
