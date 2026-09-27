import { createHash, randomBytes } from "node:crypto";
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
  const { householdId, email, role = "member" } = await request.json();
  const { data: membership } = await client.from("memberships").select("role")
    .eq("household_id", householdId).eq("user_id", user.id).single();
  const allowed = membership?.role === "owner" ||
    (membership?.role === "manager" && role === "member");
  if (!allowed) return json({ error: "Not permitted" }, 403);

  const token = randomBytes(32).toString("base64url");
  const tokenHash = createHash("sha256").update(token).digest("hex");
  const admin = serviceClient();
  const { error: insertError } = await admin.from("invitations").insert({
    household_id: householdId,
    email: String(email).trim().toLowerCase(),
    role,
    token_hash: tokenHash,
    invited_by: user.id,
    expires_at: new Date(Date.now() + 7 * 24 * 60 * 60_000).toISOString(),
  });
  if (insertError) return json({ error: insertError.message }, 400);
  const { error: inviteError } = await admin.auth.admin.inviteUserByEmail(
    email,
    {
      data: { household_invite_token: token },
      redirectTo: Deno.env.get("APP_INVITE_REDIRECT_URL"),
    },
  );
  if (inviteError) return json({ error: inviteError.message }, 400);
  return json({ invited: true });
});
