import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function verifyAdmin(db: any, req: Request): Promise<boolean> {
  const authorization = req.headers.get("authorization") || "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) return false;
  const { data, error } = await db.auth.getUser(match[1]);
  if (error || !data?.user) return false;
  const user = data.user as any;
  return user.id === "dda16adb-3b6e-4244-a028-83df88b7801d" ||
    ["admin", "manager"].includes(String(user.app_metadata?.role || ""));
}

async function hideInactiveImportedChannels(db: any) {
  const activeChannelUrls = new Map<string, string>();
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await db.from("playback_servers")
      .select("channel_id,stream_url").not("source_id", "is", null).eq("is_active", true)
      .order("channel_id").range(offset, offset + 999);
    if (error) throw new Error("Active stream lookup: " + JSON.stringify(error));
    for (const row of data || []) {
      if (row.channel_id && row.stream_url && !activeChannelUrls.has(String(row.channel_id))) {
        activeChannelUrls.set(String(row.channel_id), String(row.stream_url));
      }
    }
    if (!data || data.length < 1000) break;
  }

  const importedIds: string[] = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await db.from("channels").select("id")
      .not("external_source_key", "is", null).order("id").range(offset, offset + 999);
    if (error) throw new Error("Imported channel lookup: " + JSON.stringify(error));
    for (const row of data || []) importedIds.push(String(row.id));
    if (!data || data.length < 1000) break;
  }

  const visibleIds = importedIds.filter(id => activeChannelUrls.has(id));
  const hiddenIds = importedIds.filter(id => !activeChannelUrls.has(id));
  for (let i = 0; i < visibleIds.length; i += 250) {
    const batch = visibleIds.slice(i, i + 250);
    for (const id of batch) {
      const { error } = await db.from("channels")
        .update({ is_published: true, stream_url: activeChannelUrls.get(id) })
        .eq("id", id);
      if (error) throw new Error("Restore channel visibility: " + JSON.stringify(error));
    }
  }
  for (let i = 0; i < hiddenIds.length; i += 500) {
    const { error } = await db.from("channels").update({ is_published: false })
      .in("id", hiddenIds.slice(i, i + 500));
    if (error) throw new Error("Hide channel visibility: " + JSON.stringify(error));
  }

  const { data: packages, error: packageError } = await db.from("content_packages")
    .select("id").eq("content_type", "channel").like("name", "قنوات تلقائية — %");
  if (packageError) throw new Error("Automatic package lookup: " + JSON.stringify(packageError));
  const packageIds = (packages || []).map((row: any) => String(row.id));
  if (!packageIds.length) return;

  const staleIds: string[] = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await db.from("content_package_items")
      .select("id,content_id").in("package_id", packageIds).eq("content_type", "channel")
      .order("id").range(offset, offset + 999);
    if (error) throw new Error("Automatic package membership lookup: " + JSON.stringify(error));
    for (const item of data || []) {
      if (!activeChannelUrls.has(String(item.content_id))) staleIds.push(String(item.id));
    }
    if (!data || data.length < 1000) break;
  }
  for (let i = 0; i < staleIds.length; i += 500) {
    const { error } = await db.from("content_package_items").delete().in("id", staleIds.slice(i, i + 500));
    if (error) throw new Error("Automatic package cleanup: " + JSON.stringify(error));
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return json({ error: "Server configuration missing" }, 500);
  const db: any = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
  if (!await verifyAdmin(db, req)) return json({ error: "Unauthorized" }, 401);

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch {}
  try {
    if (body.mode === "status") {
      const { data, error } = await db.from("tv_source_global_settings")
        .select("built_in_import_enabled").eq("id", "global").maybeSingle();
      if (error) throw error;
      return json({ ok: true, mode: "status", enabled: data?.built_in_import_enabled !== false });
    }

    if (body.mode !== "set" || typeof body.enabled !== "boolean") {
      return json({ error: "Expected mode=status or mode=set with a boolean enabled value" }, 400);
    }

    const enabled = body.enabled;
    const { error: settingError } = await db.from("tv_source_global_settings").upsert({
      id: "global",
      built_in_import_enabled: enabled,
      updated_at: new Date().toISOString(),
    }, { onConflict: "id" });
    if (settingError) throw settingError;

    if (!enabled) {
      const { data: builtins, error } = await db.from("tv_channel_sources")
        .select("source_key").eq("is_builtin", true);
      if (error) throw error;
      const sourceIds = (builtins || []).map((row: any) => String(row.source_key || "")).filter(Boolean);
      if (sourceIds.length) {
        const { error: pauseError } = await db.from("playback_servers")
          .update({ is_active: false }).in("source_id", sourceIds);
        if (pauseError) throw pauseError;
      }
      await hideInactiveImportedChannels(db);
    }

    return json({ ok: true, mode: "set", enabled, hiddenImmediately: !enabled });
  } catch (error) {
    return json({ ok: false, error: error instanceof Error ? error.message : JSON.stringify(error) }, 500);
  }
});
