import {
  googleDateTime,
  googleRequest,
  refreshAccessToken,
} from "../_shared/google.ts";
import { json } from "../_shared/http.ts";
import { serviceClient } from "../_shared/supabase.ts";

type Connection = {
  household_id: string;
  google_calendar_id: string;
  encrypted_refresh_token: string;
  sync_token: string | null;
};

type GoogleEvent = {
  id: string;
  status?: string;
  summary?: string;
  description?: string;
  updated?: string;
  etag?: string;
  start?: { dateTime?: string; date?: string };
  end?: { dateTime?: string; date?: string };
  extendedProperties?: { private?: Record<string, string> };
};

async function appEventPayload(
  supabase: ReturnType<typeof serviceClient>,
  item: any,
) {
  if (item.entity_type === "household_event") {
    const { data } = await supabase.from("household_events").select("*").eq(
      "id",
      item.entity_id,
    ).maybeSingle();
    if (!data) return null;
    return {
      status: data.status === "cancelled" ? "cancelled" : "confirmed",
      summary: data.title,
      description: data.description ?? "",
      start: googleDateTime(data.starts_at),
      end: googleDateTime(data.ends_at),
      extendedProperties: {
        private: {
          hm_entity_type: item.entity_type,
          hm_entity_id: item.entity_id,
        },
      },
    };
  }
  if (item.entity_type === "chore_occurrence") {
    const { data } = await supabase.from("chore_occurrences").select("*").eq(
      "id",
      item.entity_id,
    ).maybeSingle();
    if (!data) return null;
    const start = new Date(data.due_at);
    return {
      status: data.status === "cancelled" ? "cancelled" : "confirmed",
      summary: `Chore: ${data.title_snapshot}`,
      start: googleDateTime(start.toISOString()),
      end: googleDateTime(
        new Date(start.getTime() + 30 * 60_000).toISOString(),
      ),
      extendedProperties: {
        private: {
          hm_entity_type: item.entity_type,
          hm_entity_id: item.entity_id,
        },
      },
    };
  }
  const { data } = await supabase.from("obligation_occurrences").select("*").eq(
    "id",
    item.entity_id,
  ).maybeSingle();
  if (!data) return null;
  const start = new Date(data.due_at);
  return {
    status: data.status === "cancelled" ? "cancelled" : "confirmed",
    summary: "Household payment due",
    description:
      "Payment details are available only to household Owners and Managers in Home Management.",
    start: googleDateTime(start.toISOString()),
    end: googleDateTime(new Date(start.getTime() + 30 * 60_000).toISOString()),
    extendedProperties: {
      private: {
        hm_entity_type: item.entity_type,
        hm_entity_id: item.entity_id,
      },
    },
  };
}

async function pushOutbox(
  supabase: ReturnType<typeof serviceClient>,
  connection: Connection,
  token: string,
) {
  const { data: items } = await supabase
    .from("calendar_outbox")
    .select("*")
    .eq("household_id", connection.household_id)
    .lte("available_at", new Date().toISOString())
    .order("id")
    .limit(100);
  for (const item of items ?? []) {
    try {
      const { data: mapping } = await supabase
        .from("calendar_mappings")
        .select("*")
        .eq("household_id", connection.household_id)
        .eq("entity_type", item.entity_type)
        .eq("entity_id", item.entity_id)
        .maybeSingle();
      const payload = item.operation === "delete"
        ? null
        : await appEventPayload(supabase, item);
      if (!payload || payload.status === "cancelled") {
        if (mapping) {
          await googleRequest<void>(
            token,
            `/calendars/${
              encodeURIComponent(connection.google_calendar_id)
            }/events/${encodeURIComponent(mapping.google_event_id)}`,
            { method: "DELETE" },
          );
          await supabase.from("calendar_mappings").delete().eq(
            "id",
            mapping.id,
          );
        }
      } else {
        const event = await googleRequest<GoogleEvent>(
          token,
          `/calendars/${
            encodeURIComponent(connection.google_calendar_id)
          }/events${
            mapping ? `/${encodeURIComponent(mapping.google_event_id)}` : ""
          }`,
          { method: mapping ? "PATCH" : "POST", body: JSON.stringify(payload) },
        );
        await supabase.from("calendar_mappings").upsert({
          household_id: connection.household_id,
          entity_type: item.entity_type,
          entity_id: item.entity_id,
          google_event_id: event.id,
          google_etag: event.etag,
          last_origin: "app",
          last_synced_at: new Date().toISOString(),
        }, { onConflict: "household_id,entity_type,entity_id" });
      }
      await supabase.from("calendar_outbox").delete().eq("id", item.id);
    } catch (error) {
      await supabase.from("calendar_outbox").update({
        attempts: item.attempts + 1,
        last_error: error instanceof Error ? error.message : String(error),
        available_at: new Date(
          Date.now() + Math.min(3600, 2 ** item.attempts * 30) * 1000,
        ).toISOString(),
      }).eq("id", item.id);
    }
  }
}

async function applyGoogleEvent(
  supabase: ReturnType<typeof serviceClient>,
  householdId: string,
  event: GoogleEvent,
) {
  const { data: existing } = await supabase
    .from("calendar_mappings")
    .select("*")
    .eq("household_id", householdId)
    .eq("google_event_id", event.id)
    .maybeSingle();
  // Never trust Google event metadata as an authority to address app records.
  const entityType = existing?.entity_type;
  const entityId = existing?.entity_id;

  if (event.status === "cancelled") {
    if (!existing) return;
    if (entityType !== "household_event") {
      // Deleting a calendar mirror cannot cancel a chore or a payment obligation.
      await supabase.from("calendar_mappings").delete().eq("id", existing.id)
        .eq("household_id", householdId);
      await supabase.from("calendar_outbox").upsert({
        household_id: householdId, entity_type: entityType, entity_id: entityId,
        operation: "upsert", available_at: new Date().toISOString(), attempts: 0,
      }, { onConflict: "household_id,entity_type,entity_id" });
      return;
    }
    const table = entityType === "household_event"
      ? "household_events"
      : entityType === "chore_occurrence"
      ? "chore_occurrences"
      : "obligation_occurrences";
    await supabase.from(table).update({
      status: "cancelled",
      updated_at: new Date().toISOString(),
    }).eq("id", entityId).eq("household_id", householdId);
    await supabase.from("calendar_outbox").delete().eq(
      "household_id",
      householdId,
    ).eq("entity_type", entityType).eq("entity_id", entityId);
    return;
  }
  const startsAt = event.start?.dateTime ?? event.start?.date;
  const endsAt = event.end?.dateTime ?? event.end?.date;
  if (!startsAt) return;
  if (entityType && entityId) {
    if (
      existing?.last_synced_at && event.updated &&
      new Date(event.updated) <= new Date(existing.last_synced_at)
    ) return;
    if (entityType === "household_event") {
      await supabase.from("household_events").update({
        title: event.summary ?? "Untitled event",
        description: event.description,
        starts_at: new Date(startsAt).toISOString(),
        ends_at: new Date(endsAt ?? new Date(startsAt).getTime() + 3600_000)
          .toISOString(),
        updated_at: new Date().toISOString(),
      }).eq("id", entityId).eq("household_id", householdId);
    } else {
      const table = entityType === "chore_occurrence"
        ? "chore_occurrences"
        : "obligation_occurrences";
      await supabase.from(table).update({
        due_at: new Date(startsAt).toISOString(),
        updated_at: new Date().toISOString(),
      }).eq("id", entityId).eq("household_id", householdId);
    }
    await supabase.from("calendar_mappings").upsert({
      household_id: householdId,
      entity_type: entityType,
      entity_id: entityId,
      google_event_id: event.id,
      google_etag: event.etag,
      last_origin: "google",
      last_synced_at: new Date().toISOString(),
    }, { onConflict: "household_id,entity_type,entity_id" });
    await supabase.from("calendar_outbox").delete().eq(
      "household_id",
      householdId,
    ).eq("entity_type", entityType).eq("entity_id", entityId);
    return;
  }
  if (!endsAt) return;
  const { data: ownerConnection } = await supabase
    .from("calendar_connections")
    .select("owner_user_id")
    .eq("household_id", householdId)
    .single();
  if (!ownerConnection) throw new Error("Calendar connection no longer exists");
  const { data: created } = await supabase.from("household_events").insert({
    household_id: householdId,
    title: event.summary ?? "Untitled event",
    description: event.description,
    starts_at: new Date(startsAt).toISOString(),
    ends_at: new Date(endsAt).toISOString(),
    all_day: Boolean(event.start?.date),
    created_by: ownerConnection.owner_user_id,
  }).select("id").single();
  if (!created) throw new Error("Could not import Google Calendar event");
  await supabase.from("calendar_mappings").insert({
    household_id: householdId,
    entity_type: "household_event",
    entity_id: created.id,
    google_event_id: event.id,
    google_etag: event.etag,
    last_origin: "google",
  });
  await supabase.from("calendar_outbox").delete().eq(
    "household_id",
    householdId,
  ).eq("entity_type", "household_event").eq("entity_id", created.id);
}

async function pullGoogle(
  supabase: ReturnType<typeof serviceClient>,
  connection: Connection,
  token: string,
) {
  let pageToken: string | undefined;
  let nextSyncToken: string | undefined;
  do {
    const params = new URLSearchParams({
      showDeleted: "true",
      singleEvents: "true",
      maxResults: "250",
    });
    if (connection.sync_token) params.set("syncToken", connection.sync_token);
    if (pageToken) params.set("pageToken", pageToken);
    let body: {
      items?: GoogleEvent[];
      nextPageToken?: string;
      nextSyncToken?: string;
    };
    try {
      body = await googleRequest(
        token,
        `/calendars/${
          encodeURIComponent(connection.google_calendar_id)
        }/events?${params}`,
      );
    } catch (error) {
      if ((error as any).status === 410 && connection.sync_token) {
        await supabase.from("calendar_connections").update({ sync_token: null })
          .eq("household_id", connection.household_id);
        connection.sync_token = null;
        return pullGoogle(supabase, connection, token);
      }
      throw error;
    }
    for (const event of body.items ?? []) {
      await applyGoogleEvent(supabase, connection.household_id, event);
    }
    pageToken = body.nextPageToken;
    nextSyncToken = body.nextSyncToken ?? nextSyncToken;
  } while (pageToken);
  await supabase.from("calendar_connections").update({
    sync_token: nextSyncToken ?? connection.sync_token,
    last_synced_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  }).eq("household_id", connection.household_id);
}

async function synchronize(connection: Connection) {
  const supabase = serviceClient();
  const { data: household } = await supabase.from("households").select("id")
    .eq("id", connection.household_id).is("deleted_at", null).maybeSingle();
  if (!household) return;
  const token = await refreshAccessToken(connection.encrypted_refresh_token);
  await pushOutbox(supabase, connection, token);
  await pullGoogle(supabase, connection, token);
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  if (
    request.headers.get("x-internal-secret") !==
      Deno.env.get("INTERNAL_FUNCTION_SECRET")
  ) {
    return json({ error: "Unauthorized" }, 401);
  }
  const { householdId } = await request.json().catch(() => ({}));
  const supabase = serviceClient();
  let query = supabase.from("calendar_connections").select("*");
  if (householdId) query = query.eq("household_id", householdId);
  const { data: connections, error } = await query;
  if (error) return json({ error: error.message }, 500);
  const results = [];
  for (const connection of connections ?? []) {
    try {
      await synchronize(connection);
      results.push({ householdId: connection.household_id, ok: true });
    } catch (error) {
      results.push({
        householdId: connection.household_id,
        ok: false,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  }
  return json({ results });
});
