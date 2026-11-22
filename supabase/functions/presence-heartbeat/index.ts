import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anonKey || !serviceRoleKey) {
      return json({ error: "Server configuration is incomplete" }, 500);
    }

    const body = await req.json();
    const sessionId = String(body?.session_id ?? "");
    if (!/^[A-Za-z0-9_-]{12,80}$/.test(sessionId)) {
      return json({ error: "Invalid session id" }, 400);
    }

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    let userId: string | null = null;
    let displayName = "زائر";

    // Guest requests use the publishable key. User JWTs are verified against Auth.
    if (token.startsWith("eyJ")) {
      const userClient = createClient(url, anonKey, {
        auth: { autoRefreshToken: false, persistSession: false },
      });
      const { data, error } = await userClient.auth.getUser(token);
      if (error || !data.user) return json({ error: "Invalid session" }, 401);
      userId = data.user.id;
      displayName = data.user.email?.trim() || "مستخدم مسجل";
    }

    const admin = createClient(url, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const now = new Date().toISOString();
    const { error } = await admin.from("app_presence").upsert({
      session_id: sessionId,
      user_id: userId,
      display_name: displayName,
      last_seen: now,
    }, { onConflict: "session_id" });

    if (error) return json({ error: "Could not update presence" }, 500);
    return json({ success: true, last_seen: now });
  } catch {
    return json({ error: "Invalid request" }, 400);
  }
});

// ShamFlix - آخر تعديل: 22/11/2026 - تحديث جلسات الزوار والمستخدمين عبر UPSERT آمن.
