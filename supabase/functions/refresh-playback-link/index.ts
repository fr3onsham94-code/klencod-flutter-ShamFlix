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

async function fetchHtml(raw: string, originalHost?: string): Promise<{html:string;url:URL}> {
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


type PlaybackServerRow = {
  id: string;
  server_name?: string | null;
  stream_url: string;
  source_page_url?: string | null;
  user_agent?: string | null;
  referer?: string | null;
  origin?: string | null;
  cookie?: string | null;
  drm_key?: string | null;
  license_url?: string | null;
  sort_order?: number | null;
};

async function probePlaybackUrl(server: PlaybackServerRow): Promise<boolean> {
  try {
    const original = validateUrl(server.stream_url);
    const headers: Record<string, string> = {
      "User-Agent": server.user_agent?.trim() || "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36",
      "Range": "bytes=0-1023",
      "Accept": "*/*",
    };
    if (server.referer?.trim()) headers["Referer"] = server.referer.trim();
    if (server.origin?.trim()) headers["Origin"] = server.origin.trim();
    if (server.cookie?.trim()) headers["Cookie"] = server.cookie.trim();

    const request = async (method: "GET"): Promise<boolean> => {
      let url = original;
      for (let redirect = 0; redirect <= 4; redirect++) {
        const response = await fetch(url, {
          method,
          redirect: "manual",
          signal: AbortSignal.timeout(7000),
          headers,
        });
        if ([301, 302, 303, 307, 308].includes(response.status)) {
          const location = response.headers.get("location");
          if (!location || redirect === 4) return false;
          const nextUrl = validateUrl(new URL(location, url).toString());
          if (nextUrl.hostname !== url.hostname) {
            // Never forward a source-specific cookie to a different CDN host.
            delete headers["Cookie"];
          }
          url = nextUrl;
          continue;
        }
        if (response.status >= 200 && response.status < 300 && response.status !== 204) {
          const contentType = response.headers.get("content-type")?.toLowerCase() ?? "";
          const directMediaPath = /\.(?:m3u8|mp4|m4v|mov|webm|avi|mpd|ts)$/i.test(url.pathname);
          if (directMediaPath && contentType.includes("text/html")) return false;
          if (!response.body) return false;
          const reader = response.body.getReader();
          let hasBody = false;
          try {
            const chunk = await reader.read();
            hasBody = !chunk.done && Boolean(chunk.value?.byteLength);
          } finally {
            await reader.cancel().catch(() => {});
          }
          return hasBody;
        }
        return false;
      }
      return false;
    };

    // GET with a small byte range is more representative than HEAD:
    // many media hosts allow HEAD even when the actual stream is unavailable.
    return await request("GET");
  } catch {
    return false;
  }
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
    .select("id,is_published,source_page_url,source_monitor_enabled,stream_url")
    .eq("id", contentId).maybeSingle();
  if (contentError) return json({ error: contentError.message }, 500);
  if (!content || content.is_published !== true) return json({ error: "Content not found" }, 404);
  const sourcePageUrl = String(content.source_page_url || "").trim();
  if (content.source_monitor_enabled !== true || !sourcePageUrl) {
    return json({ success: false, refreshed: false, reason: "no_managed_source", servers: [] });
  }

  // Fetch and validate new public candidates without deleting existing servers.
  // Old failed rows are removed only after the player confirms a replacement.
  if (body.mode === "refresh_candidates") {
    try {
      const { data: allContentServers, error: allServersReadError } = await db.from("playback_servers")
        .select("stream_url").eq(foreignKey, contentId);
      if (allServersReadError) throw allServersReadError;
      const allKnownUrls = new Set((allContentServers || []).map((row: any) => String(row.stream_url || "")));

      const inspected = await inspectSourcePage(sourcePageUrl);
      const candidates = inspected.sources.filter(source => !allKnownUrls.has(source.url)).slice(0, 30);
      const probed: Array<{ source: Source; healthy: boolean }> = [];
      for (let index = 0; index < candidates.length; index += 6) {
        const batch = await Promise.all(candidates.slice(index, index + 6).map(async source => ({
          source,
          healthy: await probePlaybackUrl({ id: "", stream_url: source.url, referer: sourcePageUrl }),
        })));
        probed.push(...batch);
      }

      const valid = probed.filter(item => item.healthy);
      if (!valid.length) {
        await db.from(table).update({
          source_page_last_error: "لم يتم العثور على سيرفرات بديلة يمكن الوصول إليها",
        }).eq("id", contentId);
        return json({ success: false, refreshed: false, reason: "no_healthy_new_sources", newServers: [], servers: [] });
      }

      const inserts = valid.map((item, index) => ({
        [foreignKey]: contentId,
        source_page_url: sourcePageUrl,
        server_name: item.source.name || ("السيرفر الجديد " + (index + 1)),
        stream_url: item.source.url,
        user_agent: "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36",
        referer: sourcePageUrl,
        sort_order: allKnownUrls.size + index,
        is_active: true,
      }));
      const { data: saved, error: insertError } = await db.from("playback_servers")
        .insert(inserts)
        .select("id,server_name,stream_url,sort_order,user_agent,referer,origin,cookie,source_page_url");
      if (insertError) throw insertError;
      if (!saved || saved.length !== inserts.length) throw new Error("لم يتم التحقق من حفظ كل السيرفرات البديلة");

      const { data: managedServers, error: finalReadError } = await db.from("playback_servers")
        .select("*")
        .eq(foreignKey, contentId).eq("source_page_url", sourcePageUrl).eq("is_active", true)
        .order("sort_order", { ascending: true });
      if (finalReadError) throw finalReadError;
      const savedIds = new Set((managedServers || []).map((row: any) => row.id));
      if (!(saved as PlaybackServerRow[]).every(server => savedIds.has(server.id))) {
        throw new Error("لم يتم التحقق من ظهور كل السيرفرات الجديدة ضمن قائمة التشغيل");
      }

      return json({
        success: true,
        refreshed: true,
        addedServers: saved.length,
        newServers: saved,
        servers: managedServers || [],
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : "تعذر جلب سيرفرات بديلة";
      await db.from(table).update({ source_page_last_error: message }).eq("id", contentId);
      return json({ success: false, refreshed: false, error: message, newServers: [], servers: [] }, 502);
    }
  }

  // Probe every saved server independently after playback starts.
  // Only a server that failed the probe is eligible for cleanup; manual and
  // DRM-configured rows are never deleted by this automatic process.
  if (body.mode === "health_check") {
    try {
      const { data: activeServers, error: activeReadError } = await db.from("playback_servers")
        .select("id,server_name,stream_url,source_page_url,user_agent,referer,origin,cookie,drm_key,license_url,sort_order")
        .eq(foreignKey, contentId).eq("is_active", true)
        .order("sort_order", { ascending: true }).limit(30);
      if (activeReadError) throw activeReadError;

      const rows = (activeServers || []) as PlaybackServerRow[];
      const preserveServerId = String(body.preserveServerId || "");
      const checked: Array<{ row: PlaybackServerRow; healthy: boolean }> = [];
      for (let index = 0; index < rows.length; index += 6) {
        const batch = await Promise.all(rows.slice(index, index + 6).map(async row => ({
          row,
          healthy: !row.drm_key?.trim() && !row.license_url?.trim() &&
            (row.id === preserveServerId || await probePlaybackUrl(row)),
        })));
        checked.push(...batch);
      }

      const failedManaged = checked
        .filter(item => !item.healthy &&
          !item.row.drm_key?.trim() && !item.row.license_url?.trim() &&
          item.row.source_page_url === sourcePageUrl)
        .map(item => item.row);
      const healthyReplacements = checked
        .filter(item => item.healthy)
        .map(item => item.row);
      const staleIds = failedManaged
        .filter(failed => healthyReplacements.some(replacement =>
          replacement.id !== failed.id && replacement.stream_url !== failed.stream_url))
        .map(server => server.id);

      if (staleIds.length) {
        const staleUrls = new Set(failedManaged
          .filter(server => staleIds.includes(server.id))
          .map(server => server.stream_url));
        const replacement = healthyReplacements
          .filter(server => !staleUrls.has(server.stream_url))
          .sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0))[0];

        if (replacement && staleUrls.has(String(content.stream_url || ""))) {
          const { error: contentUpdateError } = await db.from(table).update({
            stream_url: replacement.stream_url,
            source_page_checked_at: new Date().toISOString(),
            source_page_last_error: null,
          }).eq("id", contentId);
          if (contentUpdateError) throw contentUpdateError;
        }

        // Verify a healthy replacement still exists in the database before deletion.
        const { data: verified, error: verifyError } = await db.from("playback_servers")
          .select("id").eq(foreignKey, contentId).eq("is_active", true);
        if (verifyError) throw verifyError;
        const verifiedIds = new Set((verified || []).map((row: any) => row.id));
        if (!healthyReplacements.some(server => verifiedIds.has(server.id))) {
          throw new Error("لم يتم التحقق من وجود سيرفر بديل محفوظ");
        }

        const { data: deleted, error: deleteError } = await db.from("playback_servers")
          .delete().in("id", staleIds).eq("source_page_url", sourcePageUrl).select("id");
        if (deleteError) throw deleteError;
        if ((deleted || []).length !== staleIds.length) {
          throw new Error("لم يكتمل حذف السيرفرات المعطّلة");
        }
      }

      const { data: finalServers, error: finalReadError } = await db.from("playback_servers")
        .select("*")
        .eq(foreignKey, contentId).eq("is_active", true)
        .order("sort_order", { ascending: true });
      if (finalReadError) throw finalReadError;

      return json({
        success: true,
        checkedServers: checked.filter(item =>
          !item.row.drm_key?.trim() && !item.row.license_url?.trim()).length,
        failedServers: checked.filter(item => !item.healthy &&
          !item.row.drm_key?.trim() && !item.row.license_url?.trim()).length,
        removedOldServers: staleIds.length,
        servers: finalServers || [],
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : "تعذر فحص سيرفرات التشغيل";
      return json({ success: false, refreshed: false, error: message, servers: [] }, 502);
    }
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

    // Save newly discovered links first. If this fails, no old managed link is deleted.
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

    // Reactivate/update only old managed links that still exist in the source.
    // Rows for manual servers are excluded by the exact source_page_url filter above.
    for (const old of oldManaged || []) {
      const index = sources.findIndex(source => source.url === old.stream_url);
      if (index < 0) continue;
      const { error } = await db.from("playback_servers").update({
        is_active: true,
        source_page_url: sourcePageUrl,
        sort_order: index,
        server_name: sources[index].name || ("السيرفر " + (index + 1)),
      }).eq("id", old.id);
      if (error) throw error;
    }

    const primaryUrl = sources[0].url;
    const { error: contentUpdateError } = await db.from(table).update({
      stream_url: primaryUrl,
      source_page_checked_at: new Date().toISOString(),
      source_page_last_error: null,
    }).eq("id", contentId);
    if (contentUpdateError) throw contentUpdateError;

    const { data: verifiedServers, error: serverReadError } = await db.from("playback_servers")
      .select("id,server_name,stream_url,sort_order,user_agent,referer,origin,cookie,source_page_url")
      .eq(foreignKey, contentId).eq("source_page_url", sourcePageUrl).eq("is_active", true)
      .order("sort_order", { ascending: true });
    if (serverReadError) throw serverReadError;
    if (!verifiedServers?.length) throw new Error("لم يتم حفظ أي رابط مشاهدة صالح");

    // Delete only stale rows owned by this exact source page, and only after
    // the replacement links and the content's primary URL were saved/read back.
    const staleIds = (oldManaged || [])
      .filter((row: any) => !sourceUrls.has(String(row.stream_url || "")))
      .map((row: any) => row.id);
    if (staleIds.length) {
      const { data: deletedRows, error: deleteError } = await db.from("playback_servers")
        .delete().in("id", staleIds).select("id");
      if (deleteError) throw deleteError;
      if ((deletedRows || []).length !== staleIds.length) {
        throw new Error("لم يكتمل تنظيف روابط المشاهدة القديمة");
      }
    }

    // Read the final active list after cleanup so deleted links are never
    // returned to the player as if they were still available.
    const { data: finalServers, error: finalReadError } = await db.from("playback_servers")
      .select("id,server_name,stream_url,sort_order,user_agent,referer,origin,cookie,source_page_url")
      .eq(foreignKey, contentId).eq("source_page_url", sourcePageUrl).eq("is_active", true)
      .order("sort_order", { ascending: true });
    if (finalReadError) throw finalReadError;
    if (!finalServers?.length) throw new Error("لم يتبق أي رابط مشاهدة فعال بعد التنظيف");

    return json({
      success: true,
      refreshed: true,
      changed: sources.some(source => !oldUrls.has(source.url)) || staleIds.length > 0,
      removedOldServers: staleIds.length,
      servers: finalServers,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "تعذر تحديث روابط المصدر";
    await db.from(table).update({ source_page_last_error: message }).eq("id", contentId);
    return json({ success: false, refreshed: false, error: message, servers: [] }, 502);
  }
});
