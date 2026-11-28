import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-shamflix-monitor-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const MAX_PAGES = 10;
const MAX_ITEMS = 300;
const MAX_NEW_PER_MONITOR = 10;

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
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
function extractCards(html: string, base: URL) {
  const found = new Map<string,{url:string;title:string;poster:string}>();
  for (const match of html.matchAll(/<a\b[^>]*>[\s\S]*?<\/a>/gi)) {
    const opening = /^<a\b[^>]*>/i.exec(match[0])?.[0];
    if (!opening) continue;
    const a = attrs(opening), href = a.href;
    if (!href || /^javascript:|^#|^mailto:/i.test(href)) continue;
    let target: URL;
    try { target = validateUrl(new URL(href,base).toString()); } catch { continue; }
    if (target.hostname !== base.hostname) continue;
    const path = target.pathname.toLowerCase();
    if (!path || path === "/" || /\.(jpg|jpeg|png|webp|gif|css|js|pdf|zip)$/i.test(path)) continue;
    const imageTag = /<img\b[^>]*>/i.exec(match[0])?.[0];
    const image = imageTag ? attrs(imageTag) : {};
    const posterRaw = image["data-src"] || image["data-lazy-src"] || image.src || image["data-original"] || "";
    let poster = "";
    try { if (posterRaw) poster = new URL(posterRaw,base).toString(); } catch {}
    const title = clean(a.title || a["aria-label"] || image.alt || image["data-title"] ||
      image.title || (imageTag ? match[0].replace(imageTag,"") : match[0]));
    const looksLikeContent = /\/(movie|movies|film|films|series|tv|show|shows|anime|watch|content)\//i.test(path);
    const descriptive = path.split("/").filter(Boolean).length >= 2 && !/\/(page|category|tag|genre|author|login|register)\//i.test(path);
    if (title.length < 2 || (!looksLikeContent && !poster && !descriptive)) continue;
    target.search = "";
    found.set(target.toString(),{url:target.toString(),title,poster});
    if (found.size >= MAX_ITEMS) break;
  }
  return [...found.values()];
}
function findNext(html: string, base: URL): string | null {
  for (const match of html.matchAll(/<a\b[^>]*>/gi)) {
    const a = attrs(match[0]), rel = (a.rel || "").toLowerCase();
    const label = clean(a["aria-label"] || a.title || "");
    if (!a.href || !(rel.split(/\s+/).includes("next") || /^(next|التالي|التالية|›|»|→)$/i.test(label))) continue;
    try {
      const next = validateUrl(new URL(a.href,base).toString());
      if (next.hostname === base.hostname) return next.toString();
    } catch {}
  }
  return null;
}
function firstImage(value: unknown): string {
  if (typeof value === "string") return value;
  if (Array.isArray(value) && value.length) return firstImage(value[0]);
  if (value && typeof value === "object") {
    const item = value as Record<string,unknown>;
    return String(item.url || item.contentUrl || "");
  }
  return "";
}
function personNames(value: unknown): string {
  const values = Array.isArray(value) ? value : [value];
  return values.map(v => clean(v && typeof v === "object" ? (v as Record<string,unknown>).name : v)).filter(Boolean).join("، ");
}
function parseMetadata(html: string, page: URL, fallbackTitle: string, fallbackPoster: string, fallbackCategory: string) {
  const meta: Record<string,string> = {};
  for (const m of html.matchAll(/<meta\b[^>]*>/gi)) {
    const a = attrs(m[0]), key = (a.property || a.name || a.itemprop || "").toLowerCase();
    if (key && a.content) meta[key] = clean(a.content);
  }
  const jsonItems: Record<string,unknown>[] = [];
  for (const m of html.matchAll(/<script\b[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)) {
    try {
      const v = JSON.parse(m[1].trim());
      const collect = (x: unknown) => {
        if (Array.isArray(x)) x.forEach(collect);
        else if (x && typeof x === "object") {
          const o = x as Record<string,unknown>; jsonItems.push(o);
          if (o["@graph"]) collect(o["@graph"]);
          if (o.mainEntity) collect(o.mainEntity);
        }
      };
      collect(v);
    } catch {}
  }
  const structured = jsonItems.find(x => String(x["@type"] || "").toLowerCase().includes("movie")) || jsonItems[0] || {};
  const titleTag = /<title\b[^>]*>([\s\S]*?)<\/title>/i.exec(html)?.[1] || "";
  const title = clean(structured.name || structured.headline || meta["og:title"] || meta["twitter:title"] || titleTag || fallbackTitle);
  const posterRaw = firstImage(structured.image) || meta["og:image"] || meta["twitter:image"] || fallbackPoster;
  const description = clean(structured.description || meta["og:description"] || meta.description || "");
  const date = String(structured.datePublished || structured.dateCreated || meta["article:published_time"] || meta.release_date || "");
  const year = Number(/\b(19|20)\d{2}\b/.exec(date)?.[0] || /\b(19|20)\d{2}\b/.exec(title)?.[0] || 0) || null;
  const ratingRaw = (structured.aggregateRating && typeof structured.aggregateRating === "object")
    ? (structured.aggregateRating as Record<string,unknown>).ratingValue : meta.rating;
  const rating = Number(ratingRaw);
  const genre = structured.genre || meta.genre || fallbackCategory;
  const category = Array.isArray(genre) ? genre.map(clean).filter(Boolean).join("، ") : clean(genre);
  const director = personNames(structured.director);
  const cast = personNames(structured.actor);
  let poster = "";
  try { if (posterRaw) poster = new URL(String(posterRaw),page).toString(); } catch {}
  return {title:title || fallbackTitle,poster_url:poster || null,description:description || null,
    release_year:year,rating:Number.isFinite(rating) && rating > 0 ? rating : null,
    category:category || fallbackCategory || null,director:director || null,cast:cast || null};
}

function isDirectMediaUrl(url: URL): boolean {
  return /\.(?:m3u8|mp4|mkv|m4v|mov|webm|avi|wmv|flv|mpg|mpeg|3gp|ts|mpd)(?:$)/i.test(url.pathname);
}
function isGenericPageUrl(url: URL): boolean {
  return url.pathname === "/" ||
    /\.(?:jpe?g|png|gif|webp|svg|css|js|pdf|zip|woff2?|ico)$/i.test(url.pathname) ||
    /\/(?:movies?|films?|series|shows?|episodes?|episode|seasons?|profile|favorite|favorites|contactus|recent|category|categories|tag|genre|login|register|search|about)(?:\/|$)/i.test(url.pathname);
}
function isPlayerEmbedUrl(raw: string, page: URL): boolean {
  try {
    const url = validateUrl(new URL(raw, page).toString());
    if (isDirectMediaUrl(url) || isGenericPageUrl(url)) return isDirectMediaUrl(url);
    const playerPath = /\/(?:embed|player|video|stream|e|d|v)\/(?:[^/]+)(?:\/|$)/i.test(url.pathname) ||
      /\/(?:embed|player)\.php$/i.test(url.pathname);
    if (!playerPath) return false;
    if (url.hostname === page.hostname && !/\/(?:embed|player|video|stream)\//i.test(url.pathname)) return false;
    if (/(?:facebook\.com|fbcdn\.net|instagram\.com|twitter\.com|x\.com|tiktok\.com|pinterest\.com)$/i.test(url.hostname)) return false;
    return true;
  } catch { return false; }
}

function extractSources(html: string, page: URL) {
  const found = new Map<string,{url:string;name:string}>();
  const add = (raw: string | undefined, name: string, tag: "embed" | "media") => {
    if (!raw) return;
    try {
      const value = raw.replace(/&amp;/g,"&").replace(/\\\//g,"/").replace(/\\u0026/g,"&").trim();
      const url = validateUrl(new URL(value,page).toString());
      if (tag === "media" ? !isDirectMediaUrl(url) : !isPlayerEmbedUrl(url.toString(),page)) return;
      found.set(url.toString(),{url:url.toString(),name});
    } catch {}
  };
  for (const match of html.matchAll(/<(?:iframe|frame|embed)\b[^>]*>/gi)) {
    const a = attrs(match[0]);
    for (const key of ["src","data-src","data-lazy-src","data-url","data-embed","data-video","data-href","data-file"]) {
      add(a[key],"مشغل الفيلم","embed");
    }
  }
  for (const match of html.matchAll(/<(?:video|source)\b[^>]*>/gi)) {
    const a = attrs(match[0]);
    for (const key of ["src","data-src","data-lazy-src","data-url","data-file"]) add(a[key],"رابط فيديو مباشر","media");
  }
  const normalized = html.replace(/\\\//g,"/").replace(/\\u0026/g,"&").replace(/&amp;/g,"&");
  const directMedia = /https?:\/\/[^\s"'<>\\]+?\.(?:m3u8|mp4|mkv|m4v|mov|webm|avi|wmv|flv|mpg|mpeg|3gp|ts|mpd)(?:\?[^\s"'<>]*)?/gi;
  for (const match of normalized.matchAll(directMedia)) add(match[0],"رابط تشغيل مباشر","media");
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
async function inspectMovie(card: {url:string;title:string;poster:string}, host: string, category: string) {
  const page = await fetchHtml(card.url,host);
  let sources=extractSources(page.html,page.url);
  const watchUrls=findPublicWatchUrls(page.html,page.url,host);
  // Follow public watch pages (including Akwam's /watch/ route) without
  // attempting to defeat authentication, anti-bot challenges or DRM.
  for(const watchUrl of watchUrls){
    try{
      const watch=await fetchHtml(watchUrl,host);
      sources=[...sources,...extractSources(watch.html,watch.url)];
    }catch{
      // A blocked/removed watch page must not prevent checking other public links.
    }
  }
  const unique=[...new Map(sources.map(item=>[item.url,item])).values()].slice(0,60);
  return {...parseMetadata(page.html,page.url,card.title,card.poster,category),
    page_url:page.url.toString(),sources:unique};
}
async function replaceMoviePageServers(db: any, movieId: string, pageUrl: string, sources: {url:string;name:string}[]) {
  if (!sources.length) return null;
  const {data:oldServers,error:readError} = await db.from("playback_servers")
    .select("id,stream_url").eq("movie_id",movieId).eq("source_page_url",pageUrl);
  if (readError) throw readError;
  const nextUrls = new Set(sources.map(source => source.url));
  const oldUrls = new Set((oldServers || []).map((server:any) => server.stream_url));
  for (const server of oldServers || []) {
    const matchIndex = sources.findIndex(source => source.url === server.stream_url);
    const match = matchIndex >= 0 ? sources[matchIndex] : null;
    const updates:any = {is_active:match !== null};
    if (match) {
      updates.sort_order = matchIndex;
      updates.server_name = match.name || ("السيرفر " + (matchIndex + 1));
    }
    const {error:updateError} = await db.from("playback_servers")
      .update(updates).eq("id",server.id);
    if (updateError) throw updateError;
  }
  const rows = sources.filter(source => !oldUrls.has(source.url)).map((source,index) => ({
    movie_id:movieId, source_page_url:pageUrl,
    server_name:source.name || ("السيرفر " + (index + 1)),
    stream_url:source.url, sort_order:index, is_active:true,
  }));
  if (rows.length) {
    const {error:insertError} = await db.from("playback_servers").insert(rows);
    if (insertError) throw insertError;
  }
  return sources[0].url;
}

async function verifyAdminBearer(db: any, req: Request): Promise<boolean> {
  const authorization = req.headers.get("authorization") || "";
  const match = authorization.match(/^Bearer\\s+(.+)$/i);
  if (!match) return false;
  const { data, error } = await db.auth.getUser(match[1]);
  if (error || !data?.user) return false;
  const user = data.user as any;
  return user.id === "dda16adb-3b6e-4244-a028-83df88b7801d" ||
    ["admin", "manager"].includes(String(user.app_metadata?.role || ""));
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok",{headers:corsHeaders});
  if (req.method !== "POST") return json({error:"Method not allowed"},405);
  const token = req.headers.get("x-shamflix-monitor-secret") || "";
  const url = Deno.env.get("SUPABASE_URL"), key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return json({error:"Server configuration missing"},500);
  const db = createClient(url,key,{auth:{autoRefreshToken:false,persistSession:false}});
  const {data:valid,error:authError} = token
    ? await db.rpc("verify_series_monitor_cron_secret",{candidate_secret:token})
    : {data:false,error:null};
  const adminAuthorized = valid !== true && await verifyAdminBearer(db,req);
  if ((authError || valid !== true) && !adminAuthorized) return json({error:"Unauthorized"},401);
  let body: Record<string,unknown> = {};
  try { body = await req.json(); } catch {}
  const force = adminAuthorized && body.force === true;
  const runId = force && typeof body.run_id === "string" && /^[0-9a-f-]{36}$/i.test(body.run_id)
    ? body.run_id : null;
  let monitorQuery = db.from("movie_source_monitors")
    .select("id,package_id,source_url,category,check_interval_minutes,last_checked_at,last_run_id")
    .eq("is_active",true).order("last_checked_at",{ascending:true,nullsFirst:true}).limit(5);
  if (runId) monitorQuery = monitorQuery.neq("last_run_id",runId);
  const {data:monitors,error} = await monitorQuery;
  if (error) return json({error:error.message},500);
  const summary = {checked:0,added:0,linked:0,skipped:0,failed:0,results:[] as unknown[]};
  const now = Date.now();
  // Fetch each identical listing URL only once per execution. Monitors remain
  // separate so every package still receives its own content links and status.
  const listingCardsCache = new Map<string, Promise<Map<string,{url:string;title:string;poster:string}>>>();
  const getListingCards = (source: URL) => {
    const key = source.toString();
    let cached = listingCardsCache.get(key);
    if (!cached) {
      cached = (async () => {
        const cards = new Map<string,{url:string;title:string;poster:string}>();
        const visited = new Set<string>();
        let next: string | null = key;
        for (let pageNo=0; pageNo<MAX_PAGES && next && cards.size<MAX_ITEMS; pageNo++) {
          if (visited.has(next)) break;
          visited.add(next);
          const listing = await fetchHtml(next,source.hostname);
          for (const card of extractCards(listing.html,listing.url)) {
            cards.set(card.url,card);
            if (cards.size>=MAX_ITEMS) break;
          }
          next = findNext(listing.html,listing.url);
        }
        if (!cards.size) throw new Error("لم يتم العثور على روابط أفلام عامة واضحة في صفحة القسم");
        return cards;
      })();
      listingCardsCache.set(key,cached);
    }
    return cached;
  };
  for (const monitor of monitors || []) {
    const last = monitor.last_checked_at ? new Date(monitor.last_checked_at).getTime() : 0;
    const interval = Math.max(15,Number(monitor.check_interval_minutes)||15)*60000;
    if (!force && last && now-last < interval) continue;
    const startedAt = new Date().toISOString();
    await db.from("movie_source_monitors").update({
      last_status:"running",last_started_at:startedAt,last_error:null,
    }).eq("id",monitor.id);
    let added = 0, linked = 0, errorMessage: string | null = null;
    try {
      const source = validateUrl(monitor.source_url);
      const cards = await getListingCards(source);
      let processed = 0;
      for (const card of cards.values()) {
        if (processed >= MAX_NEW_PER_MONITOR) break;
        try {
          const existsByUrl = await db.from("movies").select("id").eq("source_page_url",card.url).maybeSingle();
          if (existsByUrl.error) throw existsByUrl.error;
          const movie = await inspectMovie(card,source.hostname,monitor.category || "");
          if (existsByUrl.data) {
            const movieId=existsByUrl.data.id;
            const {error:monitorUpdateError}=await db.from("movies").update({
              source_monitor_enabled:true,source_monitor_interval_minutes:monitor.check_interval_minutes,
            }).eq("id",movieId);
            if(monitorUpdateError)throw monitorUpdateError;
            if(movie.sources.length){
              const primaryUrl=await replaceMoviePageServers(db,movieId,card.url,movie.sources);
              const {error:updateMovie}=await db.from("movies").update({stream_url:primaryUrl}).eq("id",movieId);
              if(updateMovie)throw updateMovie;
            }
            const {error:linkError} = await db.from("content_package_items").upsert({
              package_id:monitor.package_id,content_type:"movie",content_id:movieId
            },{onConflict:"package_id,content_type,content_id",ignoreDuplicates:true});
            if (linkError) throw linkError;
            summary.skipped++; processed++; continue;
          }
          if (!movie.title || movie.title.length<2) { summary.skipped++; continue; }
          let duplicateQuery = db.from("movies").select("id").ilike("title",movie.title);
          duplicateQuery = movie.release_year == null
            ? duplicateQuery.is("release_year",null)
            : duplicateQuery.eq("release_year",movie.release_year);
          const {data:old,error:duplicateError} = await duplicateQuery.limit(1).maybeSingle();
          if (duplicateError) throw duplicateError;
          let movieId: string;
          if (old?.id) {
            movieId = old.id;
            await db.from("movies").update({
              source_page_url:card.url,source_monitor_enabled:true,
              source_monitor_interval_minutes:monitor.check_interval_minutes,
            }).eq("id",movieId).is("source_page_url",null);
            const {error:linkError} = await db.from("content_package_items").upsert({
              package_id:monitor.package_id,content_type:"movie",content_id:movieId
            },{onConflict:"package_id,content_type,content_id",ignoreDuplicates:true});
            if (linkError) throw linkError;
            if(movie.sources.length){
              const primaryUrl=await replaceMoviePageServers(db,movieId,card.url,movie.sources);
              const {error:updateMovie}=await db.from("movies").update({stream_url:primaryUrl}).eq("id",movieId);
              if(updateMovie)throw updateMovie;
            }
            linked++; summary.linked++;
          } else {
            const {data:saved,error:insertError} = await db.from("movies").insert({
              title:movie.title,poster_url:movie.poster_url,description:movie.description,
              category:movie.category || monitor.category || null,release_year:movie.release_year,
              rating:movie.rating,director:movie.director,cast:movie.cast,
              stream_url:movie.sources[0]?.url || null,is_published:true,source_page_url:card.url,
              source_monitor_enabled:true,source_monitor_interval_minutes:monitor.check_interval_minutes
            }).select("id").single();
            if (insertError) throw insertError;
            movieId = saved.id;
            added++; summary.added++;
            const {error:packageError} = await db.from("content_package_items").upsert({
              package_id:monitor.package_id,content_type:"movie",content_id:movieId
            },{onConflict:"package_id,content_type,content_id",ignoreDuplicates:true});
            if (packageError) throw packageError;
            if (movie.sources.length) {
              const rows = movie.sources.map((s,index)=>({movie_id:movieId,source_page_url:card.url,server_name:s.name || ("السيرفر "+(index+1)),
                stream_url:s.url,sort_order:index,is_active:true}));
              const {error:serverError} = await db.from("playback_servers").insert(rows);
              if (serverError) throw serverError;
            }
          }
          processed++;
        } catch (itemError) {
          summary.failed++;
          errorMessage = itemError instanceof Error ? itemError.message : "تعذر استيراد فيلم";
        }
      }
    } catch (monitorError) {
      errorMessage = monitorError instanceof Error ? monitorError.message : "تعذر فحص قسم الأفلام";
      summary.failed++;
    }
    const finishedAt = new Date().toISOString();
    await db.from("movie_source_monitors").update({
      last_checked_at:finishedAt,last_error:errorMessage,last_added_count:added,
      last_status:errorMessage ? ((added + linked) > 0 ? "partial" : "failed") : ((added + linked) > 0 ? "updated" : "no_new"),
      last_run_id:runId || monitor.last_run_id,last_finished_at:finishedAt,updated_at:finishedAt,
    }).eq("id",monitor.id);
    summary.checked++;
    summary.results.push({monitor_id:monitor.id,added,linked,error:errorMessage});
  }
  // Individual movie pages remain on the regular monitor cycle. The manual
  // all-servers action targets the configured category/source servers above.
  if (!force) {
  const {data:pageMovies,error:pageMoviesError} = await db.from("movies")
    .select("id,title,source_page_url,source_page_checked_at,source_monitor_interval_minutes")
    .eq("source_monitor_enabled",true).not("source_page_url","is",null)
    .order("source_page_checked_at",{ascending:true,nullsFirst:true}).limit(200);
  if (pageMoviesError) return json({error:pageMoviesError.message},500);
  const dueMovies=(pageMovies||[]).filter((row:any)=>{
    const last=row.source_page_checked_at?new Date(row.source_page_checked_at).getTime():0;
    const interval=Math.max(15,Number(row.source_monitor_interval_minutes)||60)*60000;
    return !last||now-last>=interval;
  }).slice(0,20);
  for (let start=0;start<dueMovies.length;start+=10) {
    await Promise.all(dueMovies.slice(start,start+10).map(async (movieRow:any) => {
    let pageError: string | null = null;
    try {
      const source = validateUrl(movieRow.source_page_url);
      const inspected = await inspectMovie({url:source.toString(),title:movieRow.title,poster:""},source.hostname,"");
      let primaryUrl: string | null = null;
      if (inspected.sources.length) {
        primaryUrl = await replaceMoviePageServers(db,movieRow.id,source.toString(),inspected.sources);
      }
      const updates: Record<string,unknown> = {
        source_page_checked_at:new Date().toISOString(),
        source_page_last_error:null,
      };
      if (primaryUrl) updates.stream_url = primaryUrl;
      if (inspected.poster_url) updates.poster_url = inspected.poster_url;
      if (inspected.description) updates.description = inspected.description;
      if (inspected.category) updates.category = inspected.category;
      if (inspected.release_year) updates.release_year = inspected.release_year;
      if (inspected.rating) updates.rating = inspected.rating;
      if (inspected.director) updates.director = inspected.director;
      if (inspected.cast) updates.cast = inspected.cast;
      const {error:updateError} = await db.from("movies").update(updates).eq("id",movieRow.id);
      if (updateError) throw updateError;
      summary.checked++;
    } catch (error) {
      pageError = error instanceof Error ? error.message : "تعذر تحديث صفحة الفيلم";
      await db.from("movies").update({
        source_page_checked_at:new Date().toISOString(),source_page_last_error:pageError,
      }).eq("id",movieRow.id);
      summary.failed++;
    }
    summary.results.push({movie_id:movieRow.id,mode:"individual_page",error:pageError});
    }));
  }
  }

  let hasMore = false;
  if (runId) {
    const {data:remaining,error:remainingError} = await db.from("movie_source_monitors")
      .select("id").eq("is_active",true).neq("last_run_id",runId).limit(1);
    if (remainingError) return json({error:remainingError.message},500);
    hasMore = (remaining || []).length > 0;
    if (hasMore) {
      const headers = new Headers({"Content-Type":"application/json"});
      const authorization = req.headers.get("authorization");
      if (authorization) headers.set("Authorization",authorization);
      EdgeRuntime.waitUntil(fetch(req.url,{
        method:"POST",headers,body:JSON.stringify({force:true,run_id:runId}),
      }).then(async response => {
        if (!response.ok) throw new Error("Movie monitor continuation HTTP " + response.status);
      }).catch(async error => {
        await db.from("content_monitor_runs").update({
          movies_done:true,movies_error:error instanceof Error ? error.message : "تعذر متابعة فحص الأفلام",
        }).eq("id",runId);
      }));
    } else {
      await db.from("content_monitor_runs").update({
        movies_done:true,movies_error:summary.failed > 0 ? "يوجد مصدر أو أكثر تعذر فحصه؛ راجع حالة كل مصدر" : null,
      }).eq("id",runId);
    }
  }
  return json({success:true,...summary,has_more:hasMore,run_id:runId});
});
