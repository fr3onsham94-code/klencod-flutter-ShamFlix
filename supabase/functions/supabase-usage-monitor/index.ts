import { withSupabase } from "npm:@supabase/server";

const OWNER_USER_ID = "dda16adb-3b6e-4244-a028-83df88b7801d";
const DATABASE_FREE_LIMIT_BYTES = 500 * 1024 * 1024;
const STORAGE_FREE_LIMIT_BYTES = 1024 * 1024 * 1024;

Deno.serve(
  withSupabase({ auth: "user" }, async (_request, ctx) => {
    if (ctx.userClaims?.sub !== OWNER_USER_ID) {
      return Response.json(
        { error: "هذه البيانات متاحة لمالك التطبيق فقط." },
        { status: 403 },
      );
    }

    const { data, error } = await ctx.supabaseAdmin.rpc(
      "shamflix_usage_metrics",
    );

    if (error) {
      console.error("Usage metrics query failed:", error.message);
      return Response.json(
        { error: "تعذر قراءة مؤشرات استهلاك المشروع حالياً." },
        { status: 500 },
      );
    }

    return Response.json({
      ...data,
      measured_at: new Date().toISOString(),
      reference_limits: {
        database_bytes: DATABASE_FREE_LIMIT_BYTES,
        storage_bytes: STORAGE_FREE_LIMIT_BYTES,
        plan_label: "حدود مرجعية تقريبية للخطة المجانية",
      },
      api_metrics: {
        available: false,
        note: "مؤشرات Egress وطلبات API تحتاج Management API token محفوظاً كسرّ في Edge Functions.",
      },
    });
  }),
);
