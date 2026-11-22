import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SOURCES = [
  { id: "iptv-org", name: "IPTV-ORG", url: "https://iptv-org.github.io/iptv/index.category.m3u" },
  { id: "free-tv", name: "FREE-TV", url: "https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8" },
  { id: "nexus", name: "IPTV-NEXUS", url: "https://dearbulut.github.io/iptv/playlists/index.m3u" },
] as const;

const MAX_PLAYLIST_BYTES = 24 * 1024 * 1024;
const MAX_CHANNELS_PER_RUN = 6000;
const MAX_ENTRIES_PER_SOURCE = 2000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, x-shamflix-tv-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function clean(value: unknown): string {
  return String(value ?? "")
    .replace(/&amp;/gi, "&").replace(/&quot;/gi, '"')
    .replace(/&#39;|&apos;/gi, "'").replace(/&nbsp;/gi, " ")
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#([0-9]+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/[\u200B-\u200F\uFEFF]/g, "")
    .replace(/\s+/g, " ").trim();
}

function parseAttrs(line: string): Record<string, string> {
  const out: Record<string, string> = {};
  const re = /([\w-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^,\s]+))/g;
  for (const m of line.matchAll(re)) out[m[1].toLowerCase()] = clean(m[2] ?? m[3] ?? m[4] ?? "");
  return out;
}

function normalizeName(value: string): string {
  return clean(value).toLowerCase()
    .replace(/[\u064B-\u065F\u0670]/g, "")
    .replace(/[أإآ]/g, "ا").replace(/ى/g, "ي").replace(/ة/g, "ه")
    .replace(/[^\p{L}\p{N}]+/gu, "");
}

function canonicalKey(tvgId: string, name: string, sourceId: string): string {
  const id = normalizeName(tvgId);
  const alias = arabicAlias(name);
  if (id) return "id:" + id;
  // Cross-source merging without a stable ID is allowed only for an explicit,
  // reviewed alias. Similar display names alone are not proof of identity.
  if (alias) return "alias:" + normalizeName(alias);
  return "source:" + sourceId + ":name:" + normalizeName(name);
}

function safeStreamUrl(raw: string): string | null {
  try {
    const u = new URL(raw.trim());
    if (!["http:", "https:"].includes(u.protocol) || u.username || u.password) return null;
    const host = u.hostname.toLowerCase();
    const ipHost = host.replace(/^\[|\]$/g, "");
    if (host === "localhost" || host.endsWith(".localhost") || ipHost === "0.0.0.0" ||
        ipHost === "::" || ipHost === "::1" || /^127\./.test(ipHost) ||
        /^10\./.test(ipHost) || /^192\.168\./.test(ipHost) ||
        /^169\.254\./.test(ipHost) || /^172\.(1[6-9]|2\d|3[01])\./.test(ipHost) ||
        /^f[cd][0-9a-f]{2}:/i.test(ipHost) || /^fe80:/i.test(ipHost) ||
        /^::ffff:(127|10|192\.168|169\.254)\./i.test(ipHost)) return null;
    if (/youtube\.com|youtu\.be|twitch\.tv|facebook\.com|instagram\.com/i.test(host)) return null;
    if (!/\.m3u8?(?:$|\?)|\.mpd(?:$|\?)/i.test(u.pathname + u.search)) return null;
    u.hash = "";
    return u.toString();
  } catch { return null; }
}

function categoryOf(raw: string, name: string): string {
  const v = (raw + " " + name).toLowerCase();
  if (/news|اخبار|إخبار|خبر|العربية|الجزيرة|سكاي نيوز|bbc news|cnn|france 24|euronews/.test(v)) return "إخبارية";
  if (/sport|رياض|bein|football|soccer|كرة|الكأس|ssc|sportklub/.test(v)) return "رياضية";
  if (/movie|film|cinema|سينما|أفلام|افلام|قناة فيلم/.test(v)) return "أفلام";
  if (/kids|children|cartoon|animation|طفل|أطفال|اطفال|كرتون|براعم|طيور الجنة/.test(v)) return "أطفال";
  if (/documentary|document|وثائقي|ناشيونال|discovery|history channel|animal planet/.test(v)) return "وثائقية";
  if (/music|موسيقى|اغاني|أغاني|melody|rotana music|mtv music/.test(v)) return "موسيقى";
  if (/relig|islam|quran|قرآن|قران|ديني|كنيسة|church/.test(v)) return "دينية";
  if (/series|drama|مسلسل|دراما|ترفيه|entertainment|comedy/.test(v)) return "ترفيهية";
  return "عامة";
}

function parseM3u(text: string, sourceId: string) {
  const result: Array<{sourceId:string;sourceName:string;key:string;name:string;nameEn:string;tvgId:string;logo:string;category:string;url:string;position:number}> = [];
  let pending: Record<string,string> | null = null;
  let displayName = "";
  let position = 0;
  for (const raw of text.replace(/^\uFEFF/, "").split(/\r?\n/)) {
    const line = raw.trim();
    if (!line) continue;
    if (line.startsWith("#EXTINF")) {
      const comma = line.indexOf(",");
      pending = parseAttrs(line);
      displayName = comma >= 0 ? clean(line.slice(comma + 1)) : "";
      continue;
    }
    if (line.startsWith("#")) continue;
    if (!pending) continue;
    const url = safeStreamUrl(line);
    const name = clean(displayName || pending["tvg-name"] || pending["tvg-id"]);
    if (url && name) {
      const tvgId = pending["tvg-id"] || "";
      result.push({
        sourceId,
        sourceName: sourceId === "iptv-org" ? "IPTV-ORG" : sourceId === "free-tv" ? "FREE-TV" : "IPTV-NEXUS",
        key: canonicalKey(tvgId, name, sourceId),
        name,
        nameEn: name,
        tvgId,
        logo: pending["tvg-logo"] || "",
        category: categoryOf(pending["group-title"] || "", name),
        url,
        position: position++,
      });
    }
    pending = null;
    displayName = "";
    if (result.length >= MAX_ENTRIES_PER_SOURCE) break;
  }
  return result;
}

const ALLOWED_PLAYLIST_HOSTS = new Set([
  "iptv-org.github.io",
  "raw.githubusercontent.com",
  "dearbulut.github.io",
]);

async function fetchPlaylist(source: typeof SOURCES[number]) {
  let current = new URL(source.url);
  let response: Response | null = null;
  for (let hop = 0; hop <= 3; hop++) {
    if (current.protocol !== "https:" || !ALLOWED_PLAYLIST_HOSTS.has(current.hostname.toLowerCase())) {
      throw new Error(source.id + " redirected to a non-approved playlist host");
    }
    response = await fetch(current.toString(), {
      redirect: "manual",
      signal: AbortSignal.timeout(45000),
      headers: { "User-Agent": "ShamFlix-TV-Aggregator/1.0", "Accept": "text/plain,*/*" },
    });
    if (response.status < 300 || response.status >= 400) break;
    const location = response.headers.get("location");
    if (!location || hop === 3) throw new Error(source.id + " returned an invalid or excessive redirect");
    current = new URL(location, current);
  }
  if (!response) throw new Error(source.id + " did not return a response");
  if (!response.ok) throw new Error(source.id + " returned HTTP " + response.status);
  const body = await response.text();
  if (new TextEncoder().encode(body).length > MAX_PLAYLIST_BYTES) throw new Error(source.id + " playlist exceeds size limit");
  if (!body.trimStart().startsWith("#EXTM3U")) throw new Error(source.id + " returned an invalid M3U playlist");
  const entries = parseM3u(body, source.id);
  if (!entries.length) throw new Error(source.id + " contained no supported direct HLS/DASH streams");
  return entries;
}

async function hash(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)].map(x => x.toString(16).padStart(2, "0")).join("").slice(0, 24);
}

function arabicAlias(name: string): string | null {
  const n = normalizeName(name);
  const known: Record<string,string> = {
    aljazeera: "الجزيرة الإخبارية", aljazeeraenglish: "الجزيرة الإنجليزية",
    aljazeeraarabic: "الجزيرة الإخبارية", "الجزيرهالاخباريه": "الجزيرة الإخبارية",
    "قناهالجزيره": "الجزيرة الإخبارية", "الجزيره": "الجزيرة الإخبارية",
    alarabiya: "العربية", alhadath: "الحدث",
    skynewsarabia: "سكاي نيوز عربية", bbcnewsarabic: "بي بي سي عربي",
    alhurra: "الحرة", almayadeen: "الميادين",
    rtarabic: "روسيا اليوم عربي", france24arabic: "فرانس 24 عربي",
    euronewsarabic: "يورونيوز عربي", trtarabi: "تي آر تي عربي",
    alikhbaria: "الإخبارية السورية", syria: "سوريا",
  };
  return known[n] || null;
}

async function verifySecret(db: any, token: string) {
  const { data, error } = await db.rpc("verify_tv_channels_cron_secret", { candidate_secret: token });
  return !error && data === true;
}

async function syncChannels(db: any) {
  // Each source is reconciled independently. A failed source must never affect its saved servers.
  const settledSources = await Promise.all(SOURCES.map(async source => ({
    source,
    entries: await fetchPlaylist(source),
  })).map(p => p.then(value => ({ status: "fulfilled" as const, value }))
    .catch(reason => ({ status: "rejected" as const, reason }))));
  const sourceResults = settledSources.filter((x): x is {status:"fulfilled";value:{source:typeof SOURCES[number];entries:ReturnType<typeof parseM3u>}} => x.status === "fulfilled").map(x => x.value);
  const sourceErrors = settledSources.filter(x => x.status === "rejected");
  if (!sourceResults.length) throw new Error("All playlist sources failed; existing catalogue was left untouched");
  const grouped = new Map<string, typeof sourceResults[number]["entries"]>();
  for (const { entries } of sourceResults) {
    for (const entry of entries) {
      const group = grouped.get(entry.key) || [];
      if (!group.some(x => x.url === entry.url)) group.push(entry);
      grouped.set(entry.key, group);
    }
  }
  if (!grouped.size) throw new Error("No channels were aggregated; existing catalogue was left untouched");
  if (grouped.size > MAX_CHANNELS_PER_RUN) throw new Error("Playlist set exceeded the safe per-run channel limit; existing catalogue was left untouched");

  const { data: oldChannels, error: oldError } = await db.from("channels")
    .select("id,name,external_source_key").limit(100000);
  if (oldError) throw oldError;
  const byName = new Map<string, any>();
  const byExternalKey = new Map<string, any>();
  const claimedManualIds = new Set<string>();
  for (const row of oldChannels || []) {
    byName.set(normalizeName(row.name || ""), row);
    if (row.external_source_key) byExternalKey.set(row.external_source_key, row);
  }

  const channelRows: Record<string,unknown>[] = [];
  const streamRows: Record<string,unknown>[] = [];
  const categoryByKey = new Map<string,string>();
  const assignedChannelIds = new Set<string>();
  for (const [key, entries] of grouped) {
    // The same URL may legitimately belong to multiple sources; dedupe only within a source.
    const uniqueStreams = [...new Map(entries.map(e => [e.sourceId + "|" + e.url,e])).values()];
    const preferred = uniqueStreams.find(x => x.sourceId === "nexus") ||
      uniqueStreams.find(x => x.sourceId === "iptv-org") || uniqueStreams[0];
    const categoryCounts = new Map<string,number>();
    for (const e of uniqueStreams) categoryCounts.set(e.category,(categoryCounts.get(e.category)||0)+1);
    const category = [...categoryCounts.entries()].sort((a,b)=>b[1]-a[1])[0]?.[0] || "عامة";
    const aliases = [...new Set(uniqueStreams.map(x=>x.name).filter(x=>x !== preferred.name))];
    const arabic = uniqueStreams.map(x=>x.name).find(x=>/[\u0600-\u06FF]/.test(x)) || arabicAlias(preferred.name);
    const channelName = arabic || preferred.name;
    const nameMatch = byName.get(normalizeName(channelName)) || byName.get(normalizeName(preferred.name));
    const existing = byExternalKey.get(key) || (nameMatch && !nameMatch.external_source_key && !claimedManualIds.has(nameMatch.id) ? nameMatch : null);
    if (existing?.id && !existing.external_source_key) claimedManualIds.add(existing.id);
    const assignedId = existing?.id && !assignedChannelIds.has(existing.id) ? existing.id : crypto.randomUUID();
    assignedChannelIds.add(assignedId);
    const channelRow: Record<string,unknown> = {
      id: assignedId,
      name: channelName,
      name_en: preferred.name,
      aliases,
      category,
      stream_url: preferred.url,
      logo_url: preferred.logo || null,
      is_live: true,
      is_published: true,
      external_source_key: key,
      updated_at: new Date().toISOString(),
    };
    channelRows.push(channelRow);
    categoryByKey.set(key,category);
    for (const stream of uniqueStreams) {
      streamRows.push({
        channel_id: null,
        channel_key: key,
        server_name: stream.sourceName + " • " + (stream.url.includes(".m3u8") ? "HLS" : "DASH"),
        stream_url: stream.url,
        source_key: stream.sourceId + ":" + await hash(key + "|" + stream.url),
        source_id: stream.sourceId,
        source_seen_at: new Date().toISOString(),
        source_position: stream.position,
        source_failures: 0,
        is_active: true,
        sort_order: stream.sourceId === "nexus" ? 0 : stream.sourceId === "iptv-org" ? 1 : 2,
      });
    }
  }

  // Upsert channel rows in batches; stable source keys prevent duplicate channels on each run.
  for (let i=0; i<channelRows.length; i+=500) {
    const { error } = await db.from("channels").upsert(channelRows.slice(i,i+500), { onConflict:"external_source_key" });
    if (error) throw error;
  }
  const { data: syncedChannels, error: syncedError } = await db.from("channels")
    .select("id,external_source_key").not("external_source_key","is",null).limit(50000);
  if (syncedError) throw syncedError;
  const channelIds = new Map((syncedChannels || []).map((x:any)=>[x.external_source_key,x.id]));
  const serverRows = streamRows.map((row:any) => {
    const channelId = channelIds.get(row.channel_key);
    const { channel_key, ...server } = row;
    return { ...server, channel_id: channelId };
  }).filter((row:any)=>row.channel_id);

  // Upsert only URLs observed in successfully parsed sources. source_seen_at is refreshed
  // for links still present, while older links that disappeared remain as fallbacks.
  for (let i=0; i<serverRows.length; i+=500) {
    const { error } = await db.from("playback_servers").upsert(serverRows.slice(i,i+500), { onConflict:"source_key" });
    if (error) throw error;
  }

  // Keep only the two most recently observed URLs for each channel + source pair.
  // This bounds history without allowing one source to delete another source's servers.
  const { data: sourceServers, error: sourceServersError } = await db.from("playback_servers")
    .select("id,channel_id,source_id,source_seen_at")
    .not("source_id","is",null)
    .order("source_seen_at",{ascending:false,nullsFirst:false})
    .order("source_position",{ascending:false,nullsFirst:false})
    .limit(50000);
  if (sourceServersError) throw sourceServersError;
  const groupedServers = new Map<string, any[]>();
  const successfullySyncedSourceIds = new Set(sourceResults.map(x => x.source.id));
  for (const server of sourceServers || []) {
    // Never prune a source whose playlist failed to fetch or parse in this run.
    if (!successfullySyncedSourceIds.has(server.source_id)) continue;
    const groupKey = server.channel_id + "|" + server.source_id;
    const group = groupedServers.get(groupKey) || [];
    group.push(server);
    groupedServers.set(groupKey,group);
  }
  const deleteIds: string[] = [];
  for (const servers of groupedServers.values()) {
    for (const stale of servers.slice(2)) deleteIds.push(stale.id);
  }
  for (let i=0; i<deleteIds.length; i+=500) {
    const { error } = await db.from("playback_servers").delete().in("id",deleteIds.slice(i,i+500));
    if (error) throw error;
  }

  const categories = [...new Set(categoryByKey.values())];
  const packageRows = categories.map(category => ({
    name: "قنوات تلقائية — " + category, content_type: "channel", sort_order: 900,
  }));
  const { error: packageError } = await db.from("content_packages")
    .upsert(packageRows, { onConflict:"content_type,name" });
  if (packageError) throw packageError;
  const { data: packages, error: packagesError } = await db.from("content_packages")
    .select("id,name").like("name","قنوات تلقائية — %").eq("content_type","channel");
  if (packagesError) throw packagesError;
  const packageIds = new Map((packages || []).map((x:any)=>[x.name,x.id]));
  const itemRows: Record<string,unknown>[] = [];
  for (const [key,category] of categoryByKey) {
    const channelId = channelIds.get(key);
    const packageId = packageIds.get("قنوات تلقائية — " + category);
    if (channelId && packageId) itemRows.push({ package_id:packageId, content_type:"channel", content_id:channelId });
  }
  const syncedChannelIdList = [...new Set(itemRows.map(row => String(row.content_id)))];
  if (syncedChannelIdList.length) {
    const automaticPackageIds = (packages || []).map((x:any) => x.id);
    if (automaticPackageIds.length) {
      const { error: removeOldAutomaticMemberships } = await db.from("content_package_items")
        .delete()
        .eq("content_type","channel")
        .in("content_id",syncedChannelIdList)
        .in("package_id",automaticPackageIds);
      if (removeOldAutomaticMemberships) throw removeOldAutomaticMemberships;
    }
  }
  for (let i=0; i<itemRows.length; i+=500) {
    const { error } = await db.from("content_package_items")
      .upsert(itemRows.slice(i,i+500), { onConflict:"package_id,content_type,content_id", ignoreDuplicates:true });
    if (error) throw error;
  }

  return {
    channels: channelRows.length,
    servers: serverRows.length,
    packages: packageRows.length,
    sources: [
      ...sourceResults.map(x => ({ id:x.source.id, entries:x.entries.length, status:"synced" })),
      ...sourceErrors.map((x:any, index:number) => ({ id:SOURCES[settledSources.indexOf(x)]?.id || "unknown", status:"failed", error:String(x.reason?.message || x.reason || "fetch failed") })),
    ],
    retainedServerLimit: 2,
    retentionScope: "per channel and per source",
  };
}

async function healthCheck(db: any) {
  const { count, error } = await db.from("playback_servers")
    .select("id", { count: "exact", head: true })
    .not("source_id","is",null);
  if (error) throw error;
  // Stream hosts originate in third-party playlists and are not safe to fetch from
  // the Edge Function without DNS pinning and redirect validation. Keep their state
  // unchanged until a safe external health-check mechanism is configured.
  return {
    checked: 0,
    skipped: count || 0,
    reason: "Server-side probing of untrusted stream hosts is disabled to prevent SSRF",
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const token = req.headers.get("x-shamflix-tv-secret") || "";
  if (!token) return json({ error: "Unauthorized" }, 401);
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return json({ error: "Server configuration missing" }, 500);

  const db: any = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
  if (!await verifySecret(db, token)) return json({ error: "Unauthorized" }, 401);

  let body: Record<string,unknown> = {};
  try { body = await req.json(); } catch {}
  try {
    if (body.mode === "health") return json({ ok: true, mode: "health", result: await healthCheck(db) });
    return json({ ok: true, mode: "sync", result: await syncChannels(db) });
  } catch (error) {
    return json({ ok: false, error: error instanceof Error ? error.message : JSON.stringify(error) }, 500);
  }
});
