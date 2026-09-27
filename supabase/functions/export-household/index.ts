import JSZip from "npm:jszip@3.10.1";
import { corsHeaders, json } from "../_shared/http.ts";
import { serviceClient, userClient } from "../_shared/supabase.ts";

function csv(rows: Record<string, unknown>[]): string {
  if (rows.length === 0) return "";
  const columns = [...new Set(rows.flatMap((row) => Object.keys(row)))];
  const quote = (value: unknown) => {
    const normalized = value == null
      ? ""
      : typeof value === "object"
      ? JSON.stringify(value)
      : String(value);
    return `"${normalized.replaceAll('"', '""')}"`;
  };
  return [
    columns.map(quote).join(","),
    ...rows.map((row) => columns.map((column) => quote(row[column])).join(",")),
  ].join("\n");
}

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
  const { data: membership } = await client.from("memberships").select("role")
    .eq("household_id", householdId).eq("user_id", user.id).single();
  if (membership?.role !== "owner") {
    return json({ error: "Owner access required" }, 403);
  }

  const admin = serviceClient();
  const tables = [
    "households",
    "memberships",
    "profiles",
    "categories",
    "payment_sources",
    "expenses",
    "expense_items",
    "budgets",
    "obligations",
    "obligation_occurrences",
    "chores",
    "chore_occurrences",
    "household_events",
    "notifications",
    "audit_events",
  ];
  const zip = new JSZip();
  const manifest: Record<string, unknown> = {
    formatVersion: 1,
    householdId,
    exportedAt: new Date().toISOString(),
    requestedBy: user.id,
  };
  let expenseRows: Record<string, unknown>[] = [];
  for (const table of tables) {
    let query = admin.from(table).select("*");
    if (table === "profiles") {
      const { data: members } = await admin.from("memberships").select(
        "user_id",
      ).eq("household_id", householdId);
      query = admin.from("profiles").select("*").in(
        "user_id",
        (members ?? []).map((member) => member.user_id),
      );
    } else if (table === "expense_items") {
      const { data: expenses } = await admin.from("expenses").select("id").eq(
        "household_id",
        householdId,
      );
      query = admin.from("expense_items").select("*").in(
        "expense_id",
        (expenses ?? []).map((expense) => expense.id),
      );
    } else if (table !== "households") {
      query = query.eq("household_id", householdId);
    } else {
      query = query.eq("id", householdId);
    }
    const { data, error } = await query;
    if (error) {
      return json(
        { error: `Export failed for ${table}: ${error.message}` },
        500,
      );
    }
    const rows = (data ?? []) as Record<string, unknown>[];
    if (table === "expenses") expenseRows = rows;
    zip.file(`${table}.csv`, csv(rows));
  }
  const receiptFolder = zip.folder("receipts")!;
  for (const expense of expenseRows) {
    const path = expense.receipt_path as string | null;
    if (!path) continue;
    const { data } = await admin.storage.from("receipts").download(path);
    if (data) {
      receiptFolder.file(path.split("/").at(-1)!, await data.arrayBuffer());
    }
  }
  zip.file("manifest.json", JSON.stringify(manifest, null, 2));
  await admin.from("audit_events").insert({
    household_id: householdId,
    actor_user_id: user.id,
    action: "exported",
    entity_type: "household",
    entity_id: householdId,
  });
  const archive = await zip.generateAsync({
    type: "uint8array",
    compression: "DEFLATE",
  });
  const body = (archive.buffer as ArrayBuffer).slice(
    archive.byteOffset,
    archive.byteOffset + archive.byteLength,
  );
  return new Response(body, {
    headers: {
      ...corsHeaders,
      "Content-Type": "application/zip",
      "Content-Disposition": `attachment; filename="home-management-${
        new Date().toISOString().slice(0, 10)
      }.zip"`,
    },
  });
});
