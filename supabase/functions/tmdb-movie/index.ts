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

async function tmdbFetch(path: string, token: string, language: string) {
  const response = await fetch(`https://api.themoviedb.org/3/${path}?language=${language}`, {
    headers: { Authorization: `Bearer ${token}`, accept: "application/json" },
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(typeof data?.status_message === "string"
      ? data.status_message
      : `TMDB request failed (${response.status})`);
  }
  return data;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const tmdbToken = Deno.env.get("TMDB_ACCESS_TOKEN");

    if (!supabaseUrl || !anonKey) return json({ error: "Server configuration is incomplete" }, 500);
    if (!tmdbToken) return json({ error: "TMDB_ACCESS_TOKEN غير مضبوط في أسرار الخادم." }, 500);

    const authHeader = req.headers.get("Authorization") ?? "";
    const jwt = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : "";
    if (!jwt) return json({ error: "Authentication required" }, 401);

    const userClient = createClient(supabaseUrl, anonKey, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: authHeader } },
    });

    const { data: authData, error: authError } = await userClient.auth.getUser(jwt);
    if (authError || !authData.user) return json({ error: "Invalid session" }, 401);
    const callerRole = authData.user.app_metadata?.role;
    if (authData.user.id !== "dda16adb-3b6e-4244-a028-83df88b7801d" && callerRole !== "admin" && callerRole !== "manager") {
      return json({ error: "Admin access required" }, 403);
    }

    const body = await req.json().catch(() => null);
    const input = String(body?.tmdb_url ?? body?.url ?? body?.id ?? "").trim();
    if (!input) return json({ error: "أرسل رابط صفحة TMDB أو رقم الفيلم." }, 400);

    let mediaType: "movie" | "tv" | null = null;
    let tmdbId = "";

    if (/^\d+$/.test(input)) {
      tmdbId = input;
      mediaType = body?.media_type === "tv" ? "tv" : "movie";
    } else {
      let parsed: URL;
      try { parsed = new URL(input); } catch { return json({ error: "رابط TMDB غير صالح." }, 400); }
      if (!["www.themoviedb.org", "themoviedb.org", "www.themoviedb.com", "themoviedb.com"].includes(parsed.hostname.toLowerCase())) {
        return json({ error: "حط رابط صفحة الفيلم من موقع TMDB." }, 400);
      }
      const match = parsed.pathname.match(/^\/(movie|tv)\/(\d+)/i);
      if (!match) return json({ error: "الرابط لازم يكون من صفحة فيلم أو مسلسل على TMDB." }, 400);
      mediaType = match[1].toLowerCase() as "movie" | "tv";
      tmdbId = match[2];
    }

    const basePath = `${mediaType}/${tmdbId}`;
    const [ar, en, creditsAr, creditsEn] = await Promise.all([
      tmdbFetch(basePath, tmdbToken, "ar-SA"),
      tmdbFetch(basePath, tmdbToken, "en-US"),
      tmdbFetch(`${basePath}/credits`, tmdbToken, "ar-SA"),
      tmdbFetch(`${basePath}/credits`, tmdbToken, "en-US"),
    ]);

    const titleAr = mediaType === "movie" ? ar.title : ar.name;
    const titleEn = mediaType === "movie" ? en.title : en.name;
    const overview = ar.overview || en.overview || "";
    const releaseDate = ar.release_date || ar.first_air_date || en.release_date || en.first_air_date || "";
    const genres = (ar.genres?.length ? ar.genres : en.genres ?? []).map((g: any) => g.name).filter(Boolean);
    const credits = creditsAr.cast?.length ? creditsAr : creditsEn;
    const crew = creditsAr.crew?.length ? creditsAr.crew : creditsEn.crew ?? [];
    const director = crew.find((person: any) =>
      person.job === "Director" || person.job === "Creator"
    )?.name ?? crew.find((person: any) => person.department === "Directing")?.name ?? "";

    return json({
      success: true,
      tmdb_id: Number(tmdbId),
      media_type: mediaType,
      title: titleAr || titleEn || "",
      title_ar: titleAr || "",
      title_en: titleEn || "",
      poster_url: ar.poster_path || en.poster_path
        ? `https://image.tmdb.org/t/p/w500${ar.poster_path || en.poster_path}`
        : "",
      description: overview,
      release_date: releaseDate,
      release_year: releaseDate ? releaseDate.slice(0, 4) : "",
      category: genres.join("، "),
      genres,
      rating: Number(ar.vote_average ?? en.vote_average ?? 0),
      vote_count: Number(ar.vote_count ?? en.vote_count ?? 0),
      director,
      cast: (credits.cast ?? []).slice(0, 10).map((person: any) => ({
        name: person.name ?? "",
        character: person.character ?? "",
        profile_url: person.profile_path
          ? `https://image.tmdb.org/t/p/w185${person.profile_path}`
          : "",
      })),
      backdrop_url: ar.backdrop_path || en.backdrop_path
        ? `https://image.tmdb.org/t/p/w1280${ar.backdrop_path || en.backdrop_path}`
        : "",
      original_language: ar.original_language || en.original_language || "",
      source: "TMDB",
    });
  } catch (error) {
    console.error("tmdb-movie error:", error);
    return json({
      error: error instanceof Error ? error.message : "حدث خطأ غير متوقع أثناء جلب بيانات TMDB.",
    }, 400);
  }
});
// ShamFlix - آخر تحديث: 21-11-2026
// المالك الأساسي والمدير والأدمن يستطيعون استيراد بيانات TMDB.
