import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const OWNER_USER_ID = "dda16adb-3b6e-4244-a028-83df88b7801d";

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

    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!token) return json({ error: "Authentication required" }, 401);

    const userClient = createClient(url, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: authHeader } },
    });

    const { data: authData, error: authError } = await userClient.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "Invalid session" }, 401);

    const caller = authData.user;
    const callerRole = caller.app_metadata?.role;
    if (caller.id !== OWNER_USER_ID && callerRole !== "admin" && callerRole !== "manager") {
      return json({ error: "Admin access required" }, 403);
    }

    const admin = createClient(url, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const body = await req.json();
    const action = body?.action;

    if (action === "list") {
      const page = Math.max(1, Math.min(Number(body.page) || 1, 1000));
      const perPage = 50;
      const { data, error } = await admin.auth.admin.listUsers({ page, perPage });
      if (error) return json({ error: error.message }, 400);

      const users = (data.users ?? []).map((u) => ({
        id: u.id,
        email: u.email ?? "",
        created_at: u.created_at,
        last_sign_in_at: u.last_sign_in_at ?? null,
        banned_until: u.banned_until ?? null,
        role: ["admin", "manager"].includes(String(u.app_metadata?.role ?? "")) ? "admin" : "user",
      }));

      users.sort((a, b) => {
        if (a.role === b.role) return 0;
        return a.role === "admin" ? -1 : 1;
      });

      return json({ users, page, per_page: perPage, total: data.total ?? null });
    }

    const userId = String(body?.user_id ?? "");
    if (!userId) return json({ error: "user_id is required" }, 400);

    if (userId === OWNER_USER_ID && ["ban", "delete"].includes(action)) {
      return json({ error: "لا يمكن حظر أو حذف حساب مالك التطبيق الأساسي." }, 403);
    }

    if (action === "delete" && userId === OWNER_USER_ID) {
      return json({ error: "لا يمكن حذف حساب مالك التطبيق الأساسي." }, 403);
    }

    const { data: targetData, error: targetError } = await admin.auth.admin.getUserById(userId);
    if (targetError || !targetData.user) return json({ error: "User not found" }, 404);
    const target = targetData.user;

    if (action === "ban" || action === "unban") {
      const { error } = await admin.auth.admin.updateUserById(userId, {
        ban_duration: action === "ban" ? "876000h" : "none",
      });
      if (error) return json({ error: error.message }, 400);
      return json({ success: true, action, user_id: userId });
    }

    if (action === "set_admin") {
      // Only the primary application owner may promote or demote administrators.
      if (caller.id !== OWNER_USER_ID) {
        return json({ error: "فقط مالك التطبيق الأساسي يستطيع تعيين المدراء أو إزالة صلاحياتهم." }, 403);
      }

      if (typeof body.is_admin !== "boolean") {
        return json({ error: "is_admin must be true or false" }, 400);
      }

      if (userId === OWNER_USER_ID && body.is_admin === false) {
        return json({ error: "لا يمكن إزالة صلاحيات مالك التطبيق الأساسي." }, 403);
      }

      const nextMetadata = { ...(target.app_metadata ?? {}) };
      nextMetadata.role = body.is_admin ? "admin" : "user";

      const { data: updatedData, error: updateError } =
        await admin.auth.admin.updateUserById(userId, {
          app_metadata: nextMetadata,
        });

      if (updateError) return json({ error: updateError.message }, 400);

      const updatedRole = updatedData.user?.app_metadata?.role;
      if (updatedRole !== nextMetadata.role) {
        return json({
          error: "تم تنفيذ طلب التحديث لكن تعذر تأكيد الصلاحية الجديدة. أعد المحاولة.",
          expected_role: nextMetadata.role,
          actual_role: updatedRole ?? null,
        }, 500);
      }

      return json({
        success: true,
        action,
        user_id: userId,
        is_admin: body.is_admin,
        role: updatedRole,
      });
    }

    if (action === "delete") {
      const { error } = await admin.auth.admin.deleteUser(userId);
      if (error) return json({ error: error.message }, 400);
      return json({ success: true, action, user_id: userId });
    }

    return json({ error: "Unknown action" }, 400);
  } catch (error) {
    return json({
      error: error instanceof Error ? error.message : "Unexpected server error",
    }, 500);
  }
});
// ShamFlix - آخر تحديث: 21-11-2026
// المالك الأساسي يحتفظ بالدخول الكامل، والمدير والأدمن لهما صلاحيات متطابقة.
