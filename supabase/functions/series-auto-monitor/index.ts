import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-shamflix-monitor-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
function clean(value: string): string {
  return value.replace(/<[^>]*>/g, " ").replace(/&amp;/g, "&").replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'").replace(/&nbsp;/g, " ").replace(/\s+/g, " ").trim();
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
async function fetchHtml(raw: string, originalHost?: string): Promise<{ html: string; url: URL }> {
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
      const next = validateUrl(new URL(location, url).toString());
      if (next.hostname !== allowedHost) throw new Error("تم رفض تحويل الصفحة إلى نطاق آخر");
      url = next; continue;
    }
    if (!response.ok) throw new Error("رفض الموقع قراءة الصفحة: HTTP " + response.status);
    const type = response.headers.get("content-type")?.toLowerCase() ?? "";
    if (type && !type.includes("text/html") && !type.includes("application/xhtml")) throw new Error("الرابط لا يشير إلى صفحة HTML");
    const html = await response.text();
    if (new TextEncoder().encode(html).length > 2 * 1024 * 1024) throw new Error("حجم الصفحة أكبر من الحد المسموح");
    return { html, url };
  }
  throw new Error("تعذر قراءة الصفحة");
}
function titleFromHtml(html: string): string {
  const og = /<meta\b[^>]*(?:property|name)=["'](?:og:title|twitter:title)["'][^>]*>/i.exec(html)?.[0];
  return clean((og ? attrs(og).content : "") || /<title\b[^>]*>([\s\S]*?)<\/title>/i.exec(html)?.[1] || "");
}
function parseSeason(text: string, fallback: number): number {
  const n = Number(/(?:season|الموسم)\s*[-:#]?\s*(\d{1,2})/i.exec(text)?.[1]);
  return Number.isInteger(n) && n > 0 && n <= 100 ? n : fallback;
}
function parseEpisodeNumber(text: string): number | null {
  for (const pattern of [
    /(?:episode|الحلقة|حلقة|ep)\s*[-:#_]?\s*(\d{1,4})/i,
    /(?:episode|ep)[-_](\d{1,4})/i,
    /-(\d{1,4})(?:[/?#]|$)/i,
    /\/(?:episode|episodes)\/[^/]*?(\d{1,4})(?:\/|$)/i,
  ]) {
    const n = Number(pattern.exec(text)?.[1]);
    if (Number.isInteger(n) && n > 0 && n <= 9999) return n;
  }
  return null;
}
function extractEpisodeLinks(html: string, base: URL) {
  const found = new Map<string, { url: string; title: string; number: number }>();
  for (const m of html.matchAll(/<a\b[^>]*>[\s\S]*?<\/a>/gi)) {
    const opening = /^<a\b[^>]*>/i.exec(m[0])?.[0];
    if (!opening) continue;
    const href = attrs(opening).href;
    if (!href || /^javascript:|^#|^mailto:/i.test(href)) continue;
    let target: URL;
    try { target = validateUrl(new URL(href, base).toString()); } catch { continue; }
    const title = clean(m[0]);
    if (target.hostname !== base.hostname ||
        (!/(?:episode|episodes|الحلقة)/i.test(target.pathname) && !/(?:episode|الحلقة|حلقة)\s*[-:#_]?\s*\d+/i.test(title))) continue;
    const number = parseEpisodeNumber(title + " " + target.pathname);
    if (!number) continue;
    target.search = "";
    found.set(target.toString(), { url: target.toString(), title, number });
    if (found.size >= 500) break;
  }
  return [...found.values()].sort((a,b) => a.number-b.number);
}
function extractSources(html: string, base: URL) {
  const found = new Map<string,{url:string;name:string}>();
  const add = (raw: string | undefined, name: string) => {
    if(!raw)return;
    try{
      let value=raw.replace(/&amp;/g,"&").replace(/\\\//g,"/").replace(/\\u0026/g,"&").trim();
      if(value.startsWith("//"))value=base.protocol+value;
      const url=validateUrl(new URL(value,base).toString());
      found.set(url.toString(),{url:url.toString(),name});
    }catch{}
  };
  for(const m of html.matchAll(/<(?:iframe|frame|video|source|embed)\b[^>]*>/gi)){
    const a=attrs(m[0]);
    add(a.src||a["data-src"]||a["data-lazy-src"]||a["data-url"]||a["data-embed"]||a["data-video"]||a["data-href"]||a["data-file"]||a.data,"مشغل الحلقة");
  }
  for(const m of html.matchAll(/(?:src|href|data-src|data-url|data-embed|data-file|file|source|url)\s*[:=]\s*["']([^"']{8,2000})["']/gi)){
    const raw=m[1];
    if(/^(https?:)?\/\//i.test(raw)||/\.(?:m3u8|mp4|mpd|webm)(?:[?#]|$)/i.test(raw)||/(?:embed|player|watch)/i.test(raw))add(raw,"مصدر تشغيل الحلقة");
  }
  for(const m of html.matchAll(/https?:\/\/[^\s"'<>\\]+/gi)){
    const raw=m[0].replace(/&amp;/g,"&");
    if(/\.(?:m3u8|mp4|mpd|m4v|mov|webm|avi)(?:[?#]|$)/i.test(raw)||/(?:\/embed\/|\/player\/|\/watch\/)/i.test(raw))add(raw,"رابط تشغيل الحلقة");
    if(found.size>=60)break;
  }
  return [...found.values()].slice(0,60);
}
async function inspectEpisode(link: {url:string;title:string;number:number}, host: string, fallbackSeason: number) {
  const page = await fetchHtml(link.url, host);
  const title = titleFromHtml(page.html) || link.title || ("الحلقة " + link.number);
  let watchUrl: string | null = null;
  for (const m of page.html.matchAll(/<a\b[^>]*>/gi)) {
    const href = attrs(m[0]).href; if (!href) continue;
    try {
      const candidate = validateUrl(new URL(href,page.url).toString());
      if (candidate.hostname === host && /\/watch(?:\/|$)/i.test(candidate.pathname)) { watchUrl = candidate.toString(); break; }
    } catch { /* ignore */ }
  }
  let sources = extractSources(page.html,page.url);
  if (watchUrl) {
    try { const watch = await fetchHtml(watchUrl,host); sources = [...sources,...extractSources(watch.html,watch.url)]; } catch { /* fallback to watch page */ }
  }
  if (watchUrl && !sources.some(s=>s.url===watchUrl)) sources.push({url:watchUrl,name:"صفحة مشاهدة الحلقة"});
  const unique = [...new Map(sources.map(s=>[s.url,s])).values()].slice(0,15);
  return {
    number: link.number,
    seasonNumber: parseSeason(title + " " + link.url, fallbackSeason),
    title,
    sourcePageUrl: link.url,
    streamUrl: unique[0]?.url ?? null,
    sources: unique,
  };
}


function extractSeriesCards(html: string, base: URL) {
 const found=new Map<string,{url:string;title:string;poster:string}>();
 for(const match of html.matchAll(/<a\b[^>]*>[\s\S]*?<\/a>/gi)){
  const opening=/^<a\b[^>]*>/i.exec(match[0])?.[0]; if(!opening)continue;
  const a=attrs(opening),href=a.href;if(!href||/^javascript:|^#|^mailto:/i.test(href))continue;
  let target:URL;try{target=validateUrl(new URL(href,base).toString());}catch{continue;}
  if(target.hostname!==base.hostname)continue;
  const path=target.pathname.toLowerCase();
  if(!path||path==="/"||/(?:episode|episodes|الحلقة|season|الموسم)/i.test(path)||/\.(jpg|jpeg|png|webp|gif|css|js|pdf|zip)$/i.test(path))continue;
  const imageTag=/<img\b[^>]*>/i.exec(match[0])?.[0],image=imageTag?attrs(imageTag):{};
  const raw=image["data-src"]||image["data-lazy-src"]||image.src||image["data-original"]||"";
  let poster="";try{if(raw)poster=new URL(raw,base).toString();}catch{}
  const title=clean(a.title||(imageTag?match[0].replace(imageTag,""):match[0]));
  const seriesPath=/\/(series|tv|show|shows|anime|drama)\//i.test(path);
  const descriptive=path.split("/").filter(Boolean).length>=2&&!/\/(page|category|tag|genre|author|login|register|movie|movies|film|films)\//i.test(path);
  if(title.length<2||(!seriesPath&&!poster&&!descriptive))continue;
  target.search="";found.set(target.toString(),{url:target.toString(),title,poster});if(found.size>=500)break;
 }
 return [...found.values()];
}
function seriesMetadata(html:string,page:URL,fallbackTitle:string,fallbackPoster:string,fallbackCategory:string){
 const meta:Record<string,string>={};
 for(const m of html.matchAll(/<meta\b[^>]*>/gi)){const a=attrs(m[0]),key=(a.property||a.name||a.itemprop||"").toLowerCase();if(key&&a.content)meta[key]=clean(a.content);}
 let structured:Record<string,unknown>={};
 for(const m of html.matchAll(/<script\b[^>]*type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/gi)){
  try{const parsed=JSON.parse(m[1].trim());const visit=(v:unknown)=>{if(Array.isArray(v))v.forEach(visit);else if(v&&typeof v==="object"){const o=v as Record<string,unknown>;if(!Object.keys(structured).length&&o.name)structured=o;if(o["@graph"])visit(o["@graph"]);}};visit(parsed);}catch{}
 }
 const titleTag=/<title\b[^>]*>([\s\S]*?)<\/title>/i.exec(html)?.[1]||"";
 const title=clean(String(structured.name||structured.headline||meta["og:title"]||meta["twitter:title"]||titleTag||fallbackTitle));
 const iv=structured.image,ir=typeof iv==="string"?iv:Array.isArray(iv)?String(iv[0]||""):iv&&typeof iv==="object"?String((iv as Record<string,unknown>).url||""):"";
 const pr=ir||meta["og:image"]||meta["twitter:image"]||fallbackPoster;
 const description=clean(String(structured.description||meta["og:description"]||meta.description||""));
 const date=String(structured.datePublished||structured.dateCreated||meta["article:published_time"]||"");
 const year=Number(/\b(19|20)\d{2}\b/.exec(date)?.[0]||/\b(19|20)\d{2}\b/.exec(title)?.[0]||0)||null;
 const genre=structured.genre||meta.genre||fallbackCategory;
 const category=Array.isArray(genre)?genre.map(x=>clean(String(x))).filter(Boolean).join("، "):clean(String(genre||""));
 let poster="";try{if(pr)poster=new URL(String(pr),page).toString();}catch{}
 return {title:title||fallbackTitle,poster_url:poster||null,description:description||null,release_year:year,category:category||fallbackCategory||null};
}
function findSeriesNext(html:string,base:URL):string|null{
 for(const m of html.matchAll(/<a\b[^>]*>/gi)){const a=attrs(m[0]),rel=(a.rel||"").toLowerCase(),label=clean(a["aria-label"]||a.title||"");
  if(!a.href||!(rel.split(/\s+/).includes("next")||/^(next|التالي|التالية|›|»|→)$/i.test(label)))continue;
  try{const u=validateUrl(new URL(a.href,base).toString());if(u.hostname===base.hostname)return u.toString();}catch{}
 }return null;
}

async function replaceEpisodePageServers(db: any, episodeId: string, pageUrl: string, sources: {url:string;name:string}[]) {
  if (!sources.length) return null;
  const {data:oldServers,error:readError} = await db.from("playback_servers")
    .select("id,stream_url").eq("episode_id",episodeId).eq("source_page_url",pageUrl);
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
    episode_id:episodeId, source_page_url:pageUrl,
    server_name:source.name || ("السيرفر " + (index + 1)),
    stream_url:source.url, sort_order:index, is_active:true,
  }));
  if (rows.length) {
    const {error:insertError} = await db.from("playback_servers").insert(rows);
    if (insertError) throw insertError;
  }
  return sources[0].url;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok",{headers:corsHeaders});
  if (req.method !== "POST") return json({error:"Method not allowed"},405);
  const cronToken = req.headers.get("x-shamflix-monitor-secret") ?? "";
  if (!cronToken) return json({error:"Unauthorized"},401);
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return json({error:"Server configuration missing"},500);
  const db = createClient(supabaseUrl,serviceKey,{auth:{autoRefreshToken:false,persistSession:false}});
  const {data:tokenValid,error:tokenError} = await db.rpc("verify_series_monitor_cron_secret",{candidate_secret:cronToken});
  if (tokenError || tokenValid !== true) return json({error:"Unauthorized"},401);
  // Avoid PostgREST embedded !inner relation filters here: in production they
  // returned an empty monitor set despite active monitors and enabled series.
  // Resolve enabled series IDs first, then query monitors by their FK directly.
  const {data:enabledSeries,error:enabledSeriesError} = await db.from("series")
    .select("id").eq("source_monitor_enabled",true);
  if (enabledSeriesError) return json({error:enabledSeriesError.message,stage:"enabled_series"},500);
  const enabledSeriesIds = (enabledSeries || []).map((row:any)=>row.id);
  const {data:monitors,error:listError} = enabledSeriesIds.length
    ? await db.from("series_source_monitors")
        .select("id,series_id,source_url,season_number,check_interval_minutes,last_checked_at")
        .eq("is_active",true).in("series_id",enabledSeriesIds)
        .order("last_checked_at",{ascending:true,nullsFirst:true}).limit(100)
    : {data:[],error:null};
  if (listError) return json({error:listError.message,stage:"series_monitors"},500);
  const now = Date.now();
  const summary = {checked:0,added:0,skipped:0,failed:0,results:[] as unknown[]};
  for (const monitor of monitors ?? []) {
    const last = monitor.last_checked_at ? new Date(monitor.last_checked_at).getTime() : 0;
    const interval = Math.max(30,Number(monitor.check_interval_minutes)||60)*60000;
    if (last && now-last < interval) continue;
    let added = 0; let errorMessage: string | null = null;
    try {
      const source = validateUrl(monitor.source_url);
      const allLinks=new Map<string,{url:string;title:string;number:number}>();
      const visitedPages=new Set<string>();
      let nextPage:string|null=source.toString(),listingTitle="";
      let listingHtml="";
      for(let pageNo=0;pageNo<100&&nextPage;pageNo++){
        if(visitedPages.has(nextPage))break;
        visitedPages.add(nextPage);
        const listing=await fetchHtml(nextPage,source.hostname);
        if(!listingTitle){listingTitle=titleFromHtml(listing.html);listingHtml=listing.html;}
        for(const link of extractEpisodeLinks(listing.html,listing.url))allLinks.set(link.url,link);
        nextPage=findSeriesNext(listing.html,listing.url);
      }
      const links=[...allLinks.values()].sort((a,b)=>a.number-b.number);
      if (!links.length) throw new Error("لم يتم العثور على روابط حلقات عامة واضحة خلال أول 100 صفحة");
      const defaultSeason = parseSeason(listingTitle+" "+listingHtml,Number(monitor.season_number)||1);
      const seriesMeta = seriesMetadata(listingHtml,source,listingTitle,"","");
      const seriesUpdates: Record<string,unknown> = {source_page_checked_at:new Date().toISOString(),source_page_last_error:null};
      if (seriesMeta.title) seriesUpdates.title = seriesMeta.title;
      if (seriesMeta.poster_url) seriesUpdates.poster_url = seriesMeta.poster_url;
      if (seriesMeta.description) seriesUpdates.description = seriesMeta.description;
      if (seriesMeta.category) seriesUpdates.category = seriesMeta.category;
      if (seriesMeta.release_year) seriesUpdates.release_year = seriesMeta.release_year;
      const {error:seriesUpdateError} = await db.from("series").update(seriesUpdates).eq("id",monitor.series_id);
      if (seriesUpdateError) throw seriesUpdateError;
      for (const link of links) {
        try {
          const episode = await inspectEpisode(link,source.hostname,defaultSeason);
          if (!episode.streamUrl) { summary.skipped++; continue; }
          const {data:oldSeason,error:seasonReadError} = await db.from("seasons").select("id")
            .eq("series_id",monitor.series_id).eq("season_number",episode.seasonNumber).maybeSingle();
          if (seasonReadError) throw seasonReadError;
          let seasonId = oldSeason?.id;
          if (!seasonId) {
            const {data:newSeason,error:seasonInsertError} = await db.from("seasons").insert({
              series_id:monitor.series_id,season_number:episode.seasonNumber,name:"الموسم "+episode.seasonNumber,
            }).select("id").single();
            if (seasonInsertError) throw seasonInsertError;
            seasonId = newSeason.id;
          }
          const {data:oldEpisode,error:duplicateError} = await db.from("episodes").select("id")
            .eq("season_id",seasonId).eq("episode_number",episode.number).maybeSingle();
          if (duplicateError) throw duplicateError;
          if (oldEpisode) {
            const primaryUrl = await replaceEpisodePageServers(db,oldEpisode.id,episode.sourcePageUrl,episode.sources);
            const {error:updateEpisode}=await db.from("episodes").update({
              stream_url:primaryUrl || episode.streamUrl,
              source_page_url:episode.sourcePageUrl,
              source_monitor_enabled:true,
              source_monitor_interval_minutes:monitor.check_interval_minutes,
              source_page_checked_at:new Date().toISOString(),
              source_page_last_error:null,
            }).eq("id",oldEpisode.id);
            if(updateEpisode)throw updateEpisode;
            summary.skipped++; continue;
          }
          const {data:saved,error:saveError} = await db.from("episodes").insert({
            season_id:seasonId,episode_number:episode.number,title:episode.title||("الحلقة "+episode.number),
            stream_url:episode.streamUrl,is_published:true,source_page_url:episode.sourcePageUrl,
            source_monitor_enabled:true,source_monitor_interval_minutes:monitor.check_interval_minutes,
            source_page_checked_at:new Date().toISOString(),
          }).select("id").single();
          if (saveError) throw saveError;
          if (episode.sources.length) {
            const rows = episode.sources.map((server,index)=>({
              episode_id:saved.id,source_page_url:episode.sourcePageUrl,
              server_name:server.name||("السيرفر "+(index+1)),
              stream_url:server.url,sort_order:index,is_active:true,
            }));
            const {error:serverError} = await db.from("playback_servers").insert(rows);
            if (serverError) throw serverError;
          }
          added++; summary.added++;
        } catch (episodeError) {
          summary.failed++;
          errorMessage = episodeError instanceof Error ? episodeError.message : "تعذر استيراد حلقة";
        }
      }
    } catch (monitorError) {
      errorMessage = monitorError instanceof Error ? monitorError.message : "تعذر فحص صفحة المسلسل";
      summary.failed++;
    }
    await db.from("series_source_monitors").update({
      last_checked_at:new Date().toISOString(),last_error:errorMessage,last_added_count:added,updated_at:new Date().toISOString(),
    }).eq("id",monitor.id);
    await db.from("series").update({
      source_page_checked_at:new Date().toISOString(),source_page_last_error:errorMessage,
    }).eq("id",monitor.series_id);
    summary.checked++;
    summary.results.push({monitor_id:monitor.id,added,error:errorMessage});
  }

  const {data:sectionMonitors,error:sectionListError}=await db.from("series_section_monitors")
    .select("id,package_id,source_url,category,check_interval_minutes,last_checked_at")
    .eq("is_active",true).order("last_checked_at",{ascending:true,nullsFirst:true}).limit(100);
  if(sectionListError)return json({error:sectionListError.message},500);
  for(const monitor of sectionMonitors||[]){
    const last=monitor.last_checked_at?new Date(monitor.last_checked_at).getTime():0;
    const interval=Math.max(30,Number(monitor.check_interval_minutes)||60)*60000;
    if(last&&now-last<interval)continue;
    let added=0,errorMessage:string|null=null;
    try{
      const source=validateUrl(monitor.source_url),cards=new Map<string,{url:string;title:string;poster:string}>(),visited=new Set<string>();
      let next:string|null=source.toString();
      for(let pageNo=0;pageNo<100&&next&&cards.size<500;pageNo++){
        if(visited.has(next))break;visited.add(next);
        const listing=await fetchHtml(next,source.hostname);
        for(const card of extractSeriesCards(listing.html,listing.url)){cards.set(card.url,card);if(cards.size>=500)break;}
        next=findSeriesNext(listing.html,listing.url);
      }
      if(!cards.size)throw new Error("لم يتم العثور على روابط مسلسلات عامة واضحة في صفحة القسم");
      let processed=0;
      for(const card of cards.values()){
        if(processed>=25)break;
        try{
          const exists=await db.from("series").select("id").eq("source_page_url",card.url).maybeSingle();
          if(exists.error)throw exists.error;
          const page=await fetchHtml(card.url,source.hostname),meta=seriesMetadata(page.html,page.url,card.title,card.poster,monitor.category||"");
          if(!meta.title||meta.title.length<2){summary.skipped++;continue;}
          let seriesId:string;
          if(exists.data?.id)seriesId=exists.data.id;
          else{
            let q=db.from("series").select("id").ilike("title",meta.title);
            q=meta.release_year==null?q.is("release_year",null):q.eq("release_year",meta.release_year);
            const {data:old,error:dupError}=await q.limit(1).maybeSingle();if(dupError)throw dupError;
            if(old?.id){seriesId=old.id;const {error:u}=await db.from("series").update({source_page_url:card.url}).eq("id",seriesId).is("source_page_url",null);if(u)throw u;}
            else{
              const {data:saved,error:ins}=await db.from("series").insert({
                title:meta.title,poster_url:meta.poster_url,description:meta.description,category:meta.category,
                release_year:meta.release_year,is_published:true,source_page_url:card.url,
                source_monitor_enabled:true,source_monitor_interval_minutes:monitor.check_interval_minutes,
              }).select("id").single();
              if(ins)throw ins;seriesId=saved.id;
            }
          }
          const metadataUpdates:Record<string,unknown>={
            source_monitor_enabled:true,source_monitor_interval_minutes:monitor.check_interval_minutes,
            source_page_checked_at:new Date().toISOString(),source_page_last_error:null,
          };
          if(meta.title)metadataUpdates.title=meta.title;
          if(meta.poster_url)metadataUpdates.poster_url=meta.poster_url;
          if(meta.description)metadataUpdates.description=meta.description;
          if(meta.category)metadataUpdates.category=meta.category;
          if(meta.release_year)metadataUpdates.release_year=meta.release_year;
          const {error:metadataUpdateError}=await db.from("series").update(metadataUpdates).eq("id",seriesId);
          if(metadataUpdateError)throw metadataUpdateError;
          await db.from("series").update({source_page_url:card.url})
            .eq("id",seriesId).is("source_page_url",null);
          const {error:sourceMonitorError}=await db.from("series_source_monitors").upsert({
            series_id:seriesId,source_url:card.url,source_host:source.hostname,
            season_number:1,check_interval_minutes:monitor.check_interval_minutes,is_active:true,
          },{onConflict:"series_id,source_url"});
          if(sourceMonitorError)throw sourceMonitorError;
          const {error:pkg}=await db.from("content_package_items").upsert({package_id:monitor.package_id,content_type:"series",content_id:seriesId},{onConflict:"package_id,content_type,content_id",ignoreDuplicates:true});
          if(pkg)throw pkg;
          const links=extractEpisodeLinks(page.html,page.url);
          for(const link of links){
            try{
              const episode=await inspectEpisode(link,source.hostname,parseSeason(meta.title+" "+page.html,1));
              if(!episode.streamUrl){summary.skipped++;continue;}
              const {data:oldSeason,error:sr}=await db.from("seasons").select("id").eq("series_id",seriesId).eq("season_number",episode.seasonNumber).maybeSingle();if(sr)throw sr;
              let seasonId=oldSeason?.id;
              if(!seasonId){const {data:s,error:si}=await db.from("seasons").insert({series_id:seriesId,season_number:episode.seasonNumber,name:"الموسم "+episode.seasonNumber}).select("id").single();if(si)throw si;seasonId=s.id;}
              const {data:oldEpisode,error:de}=await db.from("episodes").select("id").eq("season_id",seasonId).eq("episode_number",episode.number).maybeSingle();if(de)throw de;
              if(oldEpisode){
                const primaryUrl=await replaceEpisodePageServers(db,oldEpisode.id,episode.sourcePageUrl,episode.sources);
                const {error:updateEpisode}=await db.from("episodes").update({
                  stream_url:primaryUrl||episode.streamUrl,source_page_url:episode.sourcePageUrl,
                  source_monitor_enabled:true,source_monitor_interval_minutes:monitor.check_interval_minutes,
                  source_page_checked_at:new Date().toISOString(),source_page_last_error:null,
                }).eq("id",oldEpisode.id);if(updateEpisode)throw updateEpisode;
                summary.skipped++;continue;
              }
              const {data:savedEpisode,error:ei}=await db.from("episodes").insert({
                season_id:seasonId,episode_number:episode.number,title:episode.title||("الحلقة "+episode.number),
                stream_url:episode.streamUrl,is_published:true,source_page_url:episode.sourcePageUrl,
                source_monitor_enabled:true,source_monitor_interval_minutes:monitor.check_interval_minutes,
                source_page_checked_at:new Date().toISOString(),
              }).select("id").single();if(ei)throw ei;
              if(episode.sources.length){const rows=episode.sources.map((server,index)=>({
                episode_id:savedEpisode.id,source_page_url:episode.sourcePageUrl,
                server_name:server.name||("السيرفر "+(index+1)),stream_url:server.url,sort_order:index,is_active:true
              }));const {error:se}=await db.from("playback_servers").insert(rows);if(se)throw se;}
              added++;summary.added++;
            }catch(e){summary.failed++;errorMessage=e instanceof Error?e.message:"تعذر استيراد حلقة";}
          }
          processed++;
        }catch(e){summary.failed++;errorMessage=e instanceof Error?e.message:"تعذر استيراد مسلسل";}
      }
    }catch(e){errorMessage=e instanceof Error?e.message:"تعذر فحص قسم المسلسلات";summary.failed++;}
    await db.from("series_section_monitors").update({last_checked_at:new Date().toISOString(),last_error:errorMessage,last_added_count:added,updated_at:new Date().toISOString()}).eq("id",monitor.id);
    summary.checked++;summary.results.push({monitor_id:monitor.id,added,error:errorMessage,mode:"section"});
  }

  // Independently recheck saved episode pages, even if a provider removes
  // an episode from the current series listing.
  const {data:enabledSeasons,error:enabledSeasonsError}=enabledSeriesIds.length
    ? await db.from("seasons").select("id,series_id").in("series_id",enabledSeriesIds)
    : {data:[],error:null};
  if(enabledSeasonsError)return json({error:enabledSeasonsError.message,stage:"enabled_seasons"},500);
  const enabledSeasonIds=(enabledSeasons||[]).map((row:any)=>row.id);
  const {data:episodePages,error:episodePagesError}=enabledSeasonIds.length
    ? await db.from("episodes")
        .select("id,episode_number,title,source_page_url,source_page_checked_at,source_monitor_interval_minutes,season_id")
        .eq("source_monitor_enabled",true).in("season_id",enabledSeasonIds)
        .not("source_page_url","is",null)
        .order("source_page_checked_at",{ascending:true,nullsFirst:true}).limit(200)
    : {data:[],error:null};
  if(episodePagesError)return json({error:episodePagesError.message,stage:"episode_pages"},500);
  const dueEpisodes=(episodePages||[]).filter((row:any)=>{
    const last=row.source_page_checked_at?new Date(row.source_page_checked_at).getTime():0;
    const interval=Math.max(15,Number(row.source_monitor_interval_minutes)||60)*60000;
    return !last||now-last>=interval;
  }).slice(0,20);
  for(let start=0;start<dueEpisodes.length;start+=10){
    await Promise.all(dueEpisodes.slice(start,start+10).map(async (row:any)=>{
    let pageError:string|null=null;
    try{
      const source=validateUrl(row.source_page_url);
      const season=(enabledSeasons||[]).find((item:any)=>item.id===row.season_id);
      const link={url:source.toString(),title:row.title||("الحلقة "+row.episode_number),number:Number(row.episode_number)};
      const episode=await inspectEpisode(link,source.hostname,Number(season?.season_number)||1);
      let primaryUrl:string|null=null;
      if(episode.sources.length)primaryUrl=await replaceEpisodePageServers(db,row.id,source.toString(),episode.sources);
      const updates:Record<string,unknown>={
        source_page_checked_at:new Date().toISOString(),source_page_last_error:null,
      };
      if(primaryUrl)updates.stream_url=primaryUrl;
      const {error:updateError}=await db.from("episodes").update(updates).eq("id",row.id);
      if(updateError)throw updateError;
      summary.checked++;
    }catch(error){
      pageError=error instanceof Error?error.message:"تعذر تحديث صفحة الحلقة";
      await db.from("episodes").update({
        source_page_checked_at:new Date().toISOString(),source_page_last_error:pageError,
      }).eq("id",row.id);
      summary.failed++;
    }
    summary.results.push({episode_id:row.id,mode:"individual_episode_page",error:pageError});
    }));
  }

  return json({success:true,...summary});
});
