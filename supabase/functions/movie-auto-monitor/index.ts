import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-shamflix-monitor-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const MAX_PAGES = 100;
const MAX_ITEMS = 500;
const MAX_NEW_PER_MONITOR = 100;

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
    const title = clean(a.title || (imageTag ? match[0].replace(imageTag,"") : match[0]));
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
function extractSources(html: string, page: URL) {
  const found = new Map<string,{url:string;name:string}>();
  const add = (raw: string | undefined, name: string) => {
    if (!raw) return;
    try {
      let value=raw.replace(/&amp;/g,"&").replace(/\\\//g,"/").replace(/\\u0026/g,"&").trim();
      if(value.startsWith("//")) value=page.protocol+value;
      const url=validateUrl(new URL(value,page).toString());
      found.set(url.toString(),{url:url.toString(),name});
    } catch {}
  };
  for(const m of html.matchAll(/<(?:iframe|frame|video|source|embed)\b[^>]*>/gi)){
    const a=attrs(m[0]);
    add(a.src||a["data-src"]||a["data-lazy-src"]||a["data-url"]||a["data-embed"]||a["data-video"]||a["data-href"]||a["data-file"]||a.data,"مشغل الفيلم");
  }
  for(const m of html.matchAll(/(?:src|href|data-src|data-url|data-embed|data-file|file|source|url)\s*[:=]\s*["']([^"']{8,2000})["']/gi)){
    const raw=m[1];
    if(/^(https?:)?\/\//i.test(raw)||/\.(?:m3u8|mp4|mpd|webm)(?:[?#]|$)/i.test(raw)||/(?:embed|player|watch)/i.test(raw)) add(raw,"مصدر تشغيل");
  }
  for(const m of html.matchAll(/https?:\/\/[^\s"'<>\\]+/gi)){
    const raw=m[0].replace(/&amp;/g,"&");
    if(/\.(?:m3u8|mp4|mpd|m4v|mov|webm|avi)(?:[?#]|$)/i.test(raw)||/(?:\/embed\/|\/player\/|\/watch\/)/i.test(raw)) add(raw,"رابط تشغيل");
    if(found.size>=60) break;
  }
  return [...found.values()].slice(0,60);
}
async function inspectMovie(card: {url:string;title:string;poster:string}, host: string, category: string) {
  const page = await fetchHtml(card.url,host);
  return {...parseMetadata(page.html,page.url,card.title,card.poster,category),
    page_url:page.url.toString(),sources:extractSources(page.html,page.url)};
}
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok",{headers:corsHeaders});
  if (req.method !== "POST") return json({error:"Method not allowed"},405);
  const token = req.headers.get("x-shamflix-monitor-secret") || "";
  if (!token) return json({error:"Unauthorized"},401);
  const url = Deno.env.get("SUPABASE_URL"), key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return json({error:"Server configuration missing"},500);
  const db = createClient(url,key,{auth:{autoRefreshToken:false,persistSession:false}});
  const {data:valid,error:authError} = await db.rpc("verify_series_monitor_cron_secret",{candidate_secret:token});
  if (authError || valid !== true) return json({error:"Unauthorized"},401);
  const {data:monitors,error} = await db.from("movie_source_monitors")
    .select("id,package_id,source_url,category,check_interval_minutes,last_checked_at")
    .eq("is_active",true).order("created_at",{ascending:true}).limit(100);
  if (error) return json({error:error.message},500);
  const summary = {checked:0,added:0,linked:0,skipped:0,failed:0,results:[] as unknown[]};
  const now = Date.now();
  for (const monitor of monitors || []) {
    const last = monitor.last_checked_at ? new Date(monitor.last_checked_at).getTime() : 0;
    const interval = Math.max(30,Number(monitor.check_interval_minutes)||60)*60000;
    if (last && now-last < interval) continue;
    let added = 0, linked = 0, errorMessage: string | null = null;
    try {
      const source = validateUrl(monitor.source_url);
      const cards = new Map<string,{url:string;title:string;poster:string}>();
      const visited = new Set<string>();
      let next: string | null = source.toString();
      for (let pageNo=0; pageNo<MAX_PAGES && next && cards.size<MAX_ITEMS; pageNo++) {
        if (visited.has(next)) break;
        visited.add(next);
        const listing = await fetchHtml(next,source.hostname);
        for (const card of extractCards(listing.html,listing.url)) {
          cards.set(card.url,card); if(cards.size>=MAX_ITEMS) break;
        }
        next = findNext(listing.html,listing.url);
      }
      if (!cards.size) throw new Error("لم يتم العثور على روابط أفلام عامة واضحة في صفحة القسم");
      let processed = 0;
      for (const card of cards.values()) {
        if (processed >= MAX_NEW_PER_MONITOR) break;
        try {
          const existsByUrl = await db.from("movies").select("id").eq("source_page_url",card.url).maybeSingle();
          if (existsByUrl.error) throw existsByUrl.error;
          const movie = await inspectMovie(card,source.hostname,monitor.category || "");
          if (existsByUrl.data) {
            const movieId=existsByUrl.data.id;
            if(movie.sources.length){
              const {data:oldServers,error:readServersError}=await db.from("playback_servers").select("stream_url").eq("movie_id",movieId);
              if(readServersError)throw readServersError;
              const oldUrls=new Set((oldServers||[]).map((x:any)=>x.stream_url));
              const rows=movie.sources.filter(x=>!oldUrls.has(x.url)).map((x,index)=>({movie_id:movieId,server_name:x.name||("السيرفر "+(index+1)),stream_url:x.url,sort_order:(oldServers||[]).length+index,is_active:true}));
              if(rows.length){const {error:saveServersError}=await db.from("playback_servers").insert(rows);if(saveServersError)throw saveServersError;}
              const {error:updateMovie}=await db.from("movies").update({stream_url:movie.sources[0].url}).eq("id",movieId);
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
            await db.from("movies").update({source_page_url:card.url})
              .eq("id",movieId).is("source_page_url",null);
            const {error:linkError} = await db.from("content_package_items").upsert({
              package_id:monitor.package_id,content_type:"movie",content_id:movieId
            },{onConflict:"package_id,content_type,content_id",ignoreDuplicates:true});
            if (linkError) throw linkError;
            if(movie.sources.length){
              const {data:oldServers,error:readServersError}=await db.from("playback_servers").select("stream_url").eq("movie_id",movieId);
              if(readServersError)throw readServersError;
              const oldUrls=new Set((oldServers||[]).map((x:any)=>x.stream_url));
              const rows=movie.sources.filter(x=>!oldUrls.has(x.url)).map((x,index)=>({movie_id:movieId,server_name:x.name||("السيرفر "+(index+1)),stream_url:x.url,sort_order:(oldServers||[]).length+index,is_active:true}));
              if(rows.length){const {error:saveServersError}=await db.from("playback_servers").insert(rows);if(saveServersError)throw saveServersError;}
              const {error:updateMovie}=await db.from("movies").update({stream_url:movie.sources[0].url}).eq("id",movieId);
              if(updateMovie)throw updateMovie;
            }
            linked++; summary.linked++;
          } else {
            const {data:saved,error:insertError} = await db.from("movies").insert({
              title:movie.title,poster_url:movie.poster_url,description:movie.description,
              category:movie.category || monitor.category || null,release_year:movie.release_year,
              rating:movie.rating,director:movie.director,cast:movie.cast,
              stream_url:movie.sources[0]?.url || null,is_published:true,source_page_url:card.url
            }).select("id").single();
            if (insertError) throw insertError;
            movieId = saved.id;
            added++; summary.added++;
            const {error:packageError} = await db.from("content_package_items").upsert({
              package_id:monitor.package_id,content_type:"movie",content_id:movieId
            },{onConflict:"package_id,content_type,content_id",ignoreDuplicates:true});
            if (packageError) throw packageError;
            if (movie.sources.length) {
              const rows = movie.sources.map((s,index)=>({movie_id:movieId,server_name:s.name || ("السيرفر "+(index+1)),
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
    await db.from("movie_source_monitors").update({
      last_checked_at:new Date().toISOString(),last_error:errorMessage,last_added_count:added,updated_at:new Date().toISOString()
    }).eq("id",monitor.id);
    summary.checked++;
    summary.results.push({monitor_id:monitor.id,added,linked,error:errorMessage});
  }
  return json({success:true,...summary});
});
