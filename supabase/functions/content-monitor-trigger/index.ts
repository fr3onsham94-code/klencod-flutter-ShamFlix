import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

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

async function adminUser(db: any, req: Request) {
  const authorization = req.headers.get("authorization") || "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) return null;
  const { data, error } = await db.auth.getUser(match[1]);
  if (error || !data?.user) return null;
  const user = data.user as any;
  const allowed = user.id === "dda16adb-3b6e-4244-a028-83df88b7801d" ||
    ["admin", "manager"].includes(String(user.app_metadata?.role || ""));
  return allowed ? user : null;
}

async function markStartFailure(db: any, runId: string, part: "movies" | "series" | "channels", message: string) {
  const patch: Record<string, unknown> = {
    [part + "_done"]: true,
    [part + "_error"]: message.slice(0, 1000),
  };
  const { data: run } = await db.from("content_monitor_runs")
    .select("movies_done,series_done,channels_done,movies_error,series_error,channels_error")
    .eq("id", runId).maybeSingle();
  if (run && run.movies_done && run.series_done && run.channels_done) {
    patch.status = run.movies_error || run.series_error || run.channels_error || message ? "partial" : "completed";
    patch.finished_at = new Date().toISOString();
  }
  await db.from("content_monitor_runs").update(patch).eq("id", runId);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return json({ error: "Server configuration missing" }, 500);

  const db = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
  const user = await adminUser(db, req);
  if (!user) return json({ error: "Admin authorization required" }, 403);

  const { data: activeRun, error: activeError } = await db.from("content_monitor_runs")
    .select("id,status,started_at")
    .eq("status", "running")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (activeError) return json({ error: activeError.message }, 500);
  if (activeRun) return json({ success: true, run_id: activeRun.id, status: "running", already_running: true }, 202);

  const { data: run, error: insertError } = await db.from("content_monitor_runs")
    .insert({ triggered_by: user.id, status: "running" })
    .select("id")
    .single();
  if (insertError || !run?.id) return json({ error: insertError?.message || "تعذر إنشاء مهمة الفحص" }, 500);

  const runId = String(run.id);
  const authorization = req.headers.get("authorization") || "";
  const base = url.replace(/\/$/, "");
  const startEndpoint = async (slug: string, body: Record<string, unknown>, part: "movies" | "series" | "channels") => {
    try {
      const response = await fetch(base + "/functions/v1/" + slug, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Authorization": authorization },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(25000),
      });
      if (!response.ok) {
        const detail = (await response.text()).slice(0, 800);
        await markStartFailure(db, runId, part, "HTTP " + response.status + ": " + detail);
      }
    } catch (error) {
      await markStartFailure(db, runId, part, error instanceof Error ? error.message : "تعذر بدء الفحص");
    }
  };

  EdgeRuntime.waitUntil((async () => {
    await Promise.all([
      startEndpoint("movie-auto-monitor", { force: true, run_id: runId }, "movies"),
      startEndpoint("series-auto-monitor", { force: true, run_id: runId }, "series"),
      startEndpoint("tv-channels-auto-sync", { mode: "sync-background", run_id: runId }, "channels"),
    ]);
  })());

  return json({ success: true, run_id: runId, status: "running" }, 202);
});
