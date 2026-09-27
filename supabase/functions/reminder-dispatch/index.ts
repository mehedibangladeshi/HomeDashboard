import { sendPush } from "../_shared/fcm.ts";
import { json } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";

function isQuiet(
  start: string | null,
  end: string | null,
  timeZone: string,
): boolean {
  if (!start || !end) return false;
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone,
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(new Date());
  const hour = Number(parts.find((part) => part.type === "hour")?.value ?? 0);
  const minute = Number(
    parts.find((part) => part.type === "minute")?.value ?? 0,
  );
  const current = hour * 60 + minute;
  const toMinutes = (value: string) => {
    const [h, m] = value.split(":").map(Number);
    return h * 60 + m;
  };
  const from = toMinutes(start);
  const until = toMinutes(end);
  return from <= until
    ? current >= from && current < until
    : current >= from || current < until;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  const cronSecret = Deno.env.get("CRON_SECRET");
  if (cronSecret && request.headers.get("x-cron-secret") !== cronSecret) {
    return json({ error: "Unauthorized" }, 401);
  }
  const supabase = serviceClient();
  await supabase.rpc("materialize_due_notifications");
  const { data: notifications, error } = await supabase
    .from("notifications")
    .select("id, household_id, user_id, title, body")
    .eq("status", "pending")
    .lte("scheduled_for", new Date().toISOString())
    .limit(100);
  if (error) return json({ error: error.message }, 500);

  let delivered = 0;
  for (const notification of notifications ?? []) {
    const [{ data: profile }, { data: household }, { data: devices }] =
      await Promise.all([
        supabase.from("profiles").select("quiet_hours_start, quiet_hours_end")
          .eq("user_id", notification.user_id).maybeSingle(),
        supabase.from("households").select("time_zone").eq(
          "id",
          notification.household_id,
        ).single(),
        supabase.from("device_tokens").select("token").eq(
          "user_id",
          notification.user_id,
        ),
      ]);
    if (
      isQuiet(
        profile?.quiet_hours_start ?? null,
        profile?.quiet_hours_end ?? null,
        household?.time_zone ?? "UTC",
      )
    ) {
      continue;
    }
    const results = await Promise.all(
      (devices ?? []).map((device) =>
        sendPush(device.token, notification.title, notification.body, {
          notification_id: notification.id,
          household_id: notification.household_id,
        })
      ),
    );
    await supabase.from("notifications").update({
      status: results.some(Boolean) || results.length === 0
        ? "delivered"
        : "failed",
      delivered_at: new Date().toISOString(),
    }).eq("id", notification.id);
    delivered += 1;
  }
  return json({ processed: delivered });
});
