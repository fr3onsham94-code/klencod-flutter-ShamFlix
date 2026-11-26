import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info, x-supabase-api-version",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type Source = { url: string; name: string };

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function clean(value: unknown): string {
  return String(value ?? "").replace(/<[^>]*>/g, " ").replace(/&amp;/g, "&").replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'").replace(/&nbsp;/g, " ").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/\s+/g, " ").trim();
}

function attrs(tag: string): Record<string, string> {
  const result: Record<string, string> = {};
  const pattern = /([a-zA-Z_:][-a-zA-Z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g;
  for (const m of tag.matchAll(pattern)) result[m[1].toLowerCase()] = m[2] ?? m[3] ?? m[4] ?? "";
  return result;
}

function validateUrl(raw: string): URL {
  const url = new URL(raw);
  if (!["http:", "https:"].includes(url.protocol) || url.username || url.password ||
      (url.port && !["80", "443"].includes(url.port))) throw new Error("رابط المصدر غير صالح");
  const host = url.hostname.toLowerCase();
  if (host === "localhost" || host.endsWith(".localhost") || host === "0.0.0.0" || host === "::1" ||
      /^127\./.test(host) || /^10\./.test(host) || /^192\.168\./.test(host) || /^172\.(1[6-9]|2\d|3[01])\./.test(host)) {
    throw new Error("تم رفض عنوان شبكة محلية");
  }
  url.hash = "";
  return url;
}

function fetchHtml(raw: string, originalHost?: string): Promise<{html:string;url:URL}> {
  let url = validateUrl(raw);
  const allowedHost = originalHost ?? url.hostname;
  for (let redirect = 0; redirect <= 4; redirect++) {
    const response = await fetch(url, {
      redirect: "manual", signal: AbortSignal.timeout(18000),
      headers: {
        "User-Agent": "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36",
        "Accept": "text/html,application/xhtml+xml;q=0.9,*/*;q=0.5",
        "Accept-Language": "ar,en-US;q=0.9,en;q=0.8",
        "Referer": `${url.protocol}//${url.host}/`,
        "Cache-Control": "no-cache",
      },
    });
    if ([301,302,303,307,308].includes(response.status)) {
      const location = response.headers.get("location");
      if (!location || redirect === 4) throw new Error("تجاوز الموقع عدد التحويلات المسموح");
      const next = validateUrl(new URL(location,url).toString());
      if (next.hostname !== allowedHost) throw new Error("تم رفض تحويل الصفحة إلى نطاق آخر");
      url = next; continue;
    }
    if (!response.ok) throw new Error("رفض الموقع قراءة الصفحة: HTTP " + response.status);
    const type = response.headers.get("content-type")?.toLowerCase() ?? "";
    if (type && !type.includes("text/html") && !type.includes("application/xhtml")) throw new Error("الرابط لا يشير إلى صفحة HTML");
    const html = await response.text();
    if (new TextEncoder().encode(html).length > 2 * 1024 * 1024) throw new Error("حجم الصفحة أكبر من الحد المسموح");
    return {html,url};
  }
  throw new Error("تعذر قراءة الصفحة");
}

function extractSources(html: string, page: URL) {
  const found = new Map<string,{url:string;name:string}>();
  const add = (raw: string | undefined, name: string) => {
    if (!raw) return;
    try {
      let value = raw.replace(/&amp;/g,"&").replace(/\\\//g,"/").replace(/\\u0026/g,"&").trim();
      if (value.startsWith("//")) value = page.protocol + value;
      const url = validateUrl(new URL(value,page).toString());
      found.set(url.toString(),{url:url.toString(),name});
    } catch {}
  };

  // Match the manual importer: accept only actual player elements and media files.
  for (const m of html.matchAll(/<(?:iframe|frame|video|source|embed)\b[^>]*>/gi)) {
    const a = attrs(m[0]);
    const raw = a.src || a["data-src"] || a["data-lazy-src"] || a["data-url"] ||
      a["data-embed"] || a["data-video"] || a["data-href"] || a["data-file"] || a.data;
    if (raw) add(raw,"مشغل الفيلم");
  }

  // Some Akwam player pages place the media URL inside inline scripts.
  const normalizedHtml = html.replace(/\\\//g,"/").replace(/\\u0026/g,"&");
  const directMedia = /https?:\/\/[^\s"'<>\\]+?\.(?:m3u8|mp4|m4v|mov|webm|avi|mpd)(?:\?[^\s"'<>]*)?/gi;
  for (const m of normalizedHtml.matchAll(directMedia)) {
    add(m[0],"رابط تشغيل مباشر");
    if (found.size >= 60) break;
  }

  return [...found.values()].slice(0,60);
}

function findPublicWatchUrls(html: string, page: URL, allowedHost: string): string[] {
  const normalized = html.replaceAll("\\/", "/").replaceAll("\\u0026", "&").replaceAll("&amp;", "&");
  const candidates = new Set<string>();
  const routePattern = new RegExp(String.raw`(?:https?:\/\/[^\s"'<>]+)?\/watch\/[^\s"'<>\\)]+`, "gi");
  const add = (raw: string) => {
    const value = raw.trim().replace(/^["']|["']$/g, "");
    if (!value || /^(javascript:|#|mailto:)/i.test(value)) return;
    try {
      const target = validateUrl(new URL(value, page).toString());
      if (target.hostname === allowedHost && target.pathname.toLowerCase().includes("/watch/")) {
        target.hash = "";
        candidates.add(target.toString());
      }
    } catch {}
  };
  // Akwam and similar sites may store the watch route in data-* attributes.
  for (const match of normalized.matchAll(/<(?:a|button|iframe|frame|div|span)[^>]*>/gi)) {
    const a = attrs(match[0]);
    for (const key of ["href", "data-href", "data-url", "data-link", "data-src", "data-embed", "onclick"]) {
      if (!a[key]) continue;
      const route = routePattern.exec(a[key]);
      routePattern.lastIndex = 0;
      if (route) add(route[0]);
    }
  }
  // Some versions expose the public /watch/ route only inside inline scripts.
  for (const match of normalized.matchAll(routePattern)) {
    add(match[0]);
    if (candidates.size >= 5) break;
  }
  return [...candidates].slice(0, 5);
}

async function inspectSourcePage(sourceUrl: string): Promise<{ pageUrl: string; sources: Source[] }> {
  const original = validateUrl(sourceUrl);
  const page = await fetchHtml(original.toString(), original.hostname);
  let sources = extractSources(page.html, page.url);
  const watchUrls = findPublicWatchUrls(page.html, page.url, original.hostname);
  for (const watchUrl of watchUrls) {
    try {
      const watch = await fetchHtml(watchUrl, original.hostname);
      sources = [...sources, ...extractSources(watch.html, watch.url)];
    } catch {
      // Keep other public sources; never bypass a blocked page or protection.
    }
  }
  const unique = [...new Map(sources.map(source => [source.url, source])).values()].slice(0, 30);
  return { pageUrl: sourceUrl, sources: unique };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") || Deno.env.get("SUPABASE_PUBLISHABLE_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) return json({ error: "Server configuration missing" }, 500);

  // The app's publishable key is public by design. Writes remain restricted
  // to published, explicitly source-managed movies/episodes and their managed servers.
  const suppliedApiKey = req.headers.get("apikey") || "";
  if (!suppliedApiKey || suppliedApiKey !== anonKey) return json({ error: "Unauthorized" }, 401);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON body" }, 400); }
  const contentType = String(body.contentType || "");
  const contentId = String(body.contentId || "");
  if (!["movie", "episode"].includes(contentType) ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(contentId)) {
    return json({ error: "Invalid content reference" }, 400);
  }

  const db = createClient(supabaseUrl, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const table = contentType === "movie" ? "movies" : "episodes";
  const foreignKey = contentType === "movie" ? "movie_id" : "episode_id";
  const { data: content, error: contentError } = await db.from(table)
    .select("id,is_published,source_page_url,source_monitor_enabled")
    .eq("id", contentId).maybeSingle();
  if (contentError) return json({ error: contentError.message }, 500);
  if (!content || content.is_published !== true) return json({ error: "Content not found" }, 404);
  const sourcePageUrl = String(content.source_page_url || "").trim();
  if (content.source_monitor_enabled !== true || !sourcePageUrl) {
    return json({ success: false, refreshed: false, reason: "no_managed_source", servers: [] });
  }

  try {
    const inspected = await inspectSourcePage(sourcePageUrl);
    if (!inspected.sources.length) {
      await db.from(table).update({ source_page_last_error: "لم يتم العثور على روابط مشاهدة عامة جديدة" }).eq("id", contentId);
      return json({ success: false, refreshed: false, reason: "no_public_sources", servers: [] }, 200);
    }

    const { data: oldManaged, error: oldError } = await db.from("playback_servers")
      .select("id,stream_url").eq(foreignKey, contentId).eq("source_page_url", sourcePageUrl);
    if (oldError) throw oldError;

    const oldUrls = new Set((oldManaged || []).map((row: any) => String(row.stream_url || "")));
    const sources = inspected.sources;
    const sourceUrls = new Set(sources.map(source => source.url));

    for (const old of oldManaged || []) {
      const index = sources.findIndex(source => source.url === old.stream_url);
      const updates: Record<string, unknown> = {
        is_active: index >= 0,
        source_page_url: sourcePageUrl,
      };
      if (index >= 0) {
        updates.sort_order = index;
        updates.server_name = sources[index].name || ("السيرفر " + (index + 1));
      }
      const { error } = await db.from("playback_servers").update(updates).eq("id", old.id);
      if (error) throw error;
    }

    const inserts = sources.filter(source => !oldUrls.has(source.url)).map((source, index) => ({
      [foreignKey]: contentId,
      source_page_url: sourcePageUrl,
      server_name: source.name || ("السيرفر " + (index + 1)),
      stream_url: source.url,
      sort_order: index,
      is_active: true,
    }));
    if (inserts.length) {
      const { error } = await db.from("playback_servers").insert(inserts);
      if (error) throw error;
    }

    const primaryUrl = sources[0].url;
    const { error: contentUpdateError } = await db.from(table).update({
      stream_url: primaryUrl,
      source_page_checked_at: new Date().toISOString(),
      source_page_last_error: null,
    }).eq("id", contentId);
    if (contentUpdateError) throw contentUpdateError;

    const { data: refreshedServers, error: serverReadError } = await db.from("playback_servers")
      .select("id,server_name,stream_url,sort_order,user_agent,referer,origin,cookie,source_page_url")
      .eq(foreignKey, contentId).eq("source_page_url", sourcePageUrl).eq("is_active", true)
      .order("sort_order", { ascending: true });
    if (serverReadError) throw serverReadError;

    return json({
      success: true,
      refreshed: true,
      changed: sources.some(source => !oldUrls.has(source.url)) || (oldManaged || []).some((row: any) => !sourceUrls.has(String(row.stream_url || ""))),
      servers: refreshedServers || [],
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "تعذر تحديث روابط المصدر";
    await db.from(table).update({ source_page_last_error: message }).eq("id", contentId);
    return json({ success: false, refreshed: false, error: message, servers: [] }, 502);
  }
});
