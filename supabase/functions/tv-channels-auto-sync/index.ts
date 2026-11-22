import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SOURCES = [
  { id: "iptv-org", name: "IPTV-ORG", url: "https://iptv-org.github.io/iptv/index.category.m3u" },
  { id: "free-tv", name: "FREE-TV", url: "https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8" },
  { id: "nexus", name: "IPTV-NEXUS", url: "https://dearbulut.github.io/iptv/playlists/index.m3u" },
] as const;

const MAX_PLAYLIST_BYTES = 24 * 1024 * 1024;
const MAX_CHANNELS_PER_RUN = 12000;
const MAX_HEALTH_CHECKS = 600;
const CONCURRENCY = 12;

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

function canonicalKey(tvgId: string, name: string): string {
  const id = normalizeName(tvgId);
  return id ? "id:" + id : "name:" + normalizeName(name);
}

function safeStreamUrl(raw: string): string | null {
  try {
    const u = new URL(raw.trim());
    if (!["http:", "https:"].includes(u.protocol) || u.username || u.password) return null;
    const host = u.hostname.toLowerCase();
    if (host === "localhost" || host.endsWith(".localhost") || host === "0.0.0.0" ||
        host === "::1" || /^127\./.test(host) || /^10\./.test(host) ||
        /^192\.168\./.test(host) || /^172\.(1[6-9]|2\d|3[01])\./.test(host)) return null;
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
  const result: Array<{sourceId:string;sourceName:string;key:string;name:string;nameEn:string;tvgId:string;logo:string;category:string;url:string}> = [];
  let pending: Record<string,string> | null = null;
  let displayName = "";
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
        key: canonicalKey(tvgId, name),
        name,
        nameEn: name,
        tvgId,
        logo: pending["tvg-logo"] || "",
        category: categoryOf(pending["group-title"] || "", name),
        url,
      });
    }
    pending = null;
    displayName = "";
    if (result.length >= MAX_CHANNELS_PER_RUN * 4) break;
  }
  return result;
}

async function fetchPlaylist(source: typeof SOURCES[number]) {
  const response = await fetch(source.url, {
    signal: AbortSignal.timeout(45000),
    headers: { "User-Agent": "ShamFlix-TV-Aggregator/1.0", "Accept": "text/plain,*/*" },
  });
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
    aljazeera: "الجزيرة", aljazeeraenglish: "الجزيرة الإنجليزية",
    alarabiya: "العربية", alhadath: "الحدث",
    skynewsarabia: "سكاي نيوز عربية", bbcnewsarabic: "بي بي سي عربي",
    alhurra: "الحرة", almayadeen: "الميادين",
    rtarabic: "روسيا اليوم عربي", france24arabic: "فرانس 24 عربي",
    euronewsarabic: "يورونيوز عربي", trtarabi: "تي آر تي عربي",
    alikhbaria: "الإخبارية السورية", syria: "سوريا",
  };
  return known[n] || null;
}

async function verifySecret(db: ReturnType<typeof createClient>, token: string) {
  const { data, error } = await db.rpc("verify_tv_channels_cron_secret", { candidate_secret: token });
  return !error && data === true;
}

async function syncChannels(db: ReturnType<typeof createClient>) {
  const sourceResults = await Promise.all(SOURCES.map(async source => ({
    source,
    entries: await fetchPlaylist(source),
  })));
  const grouped = new Map<string, typeof sourceResults[number]["entries"]>();
  for (const { entries } of sourceResults) {
    for (const entry of entries) {
      const group = grouped.get(entry.key) || [];
      if (!group.some(x => x.url === entry.url)) group.push(entry);
      grouped.set(entry.key, group);
    }
  }
  if (!grouped.size) throw new Error("No channels were aggregated; existing catalogue was left untouched");

  const { data: oldChannels, error: oldError } = await db.from("channels")
    .select("id,name,external_source_key").limit(10000);
  if (oldError) throw oldError;
  const byName = new Map<string, any>();
  for (const row of oldChannels || []) byName.set(normalizeName(row.name || ""), row);

  const summary = { channels: 0, servers: 0, packages: 0, sources: sourceResults.map(x => ({ id:x.source.id, entries:x.entries.length })) };
  const packageIds = new Map<string,string>();

  for (const [key, entries] of grouped) {
    const uniqueStreams = [...new Map(entries.map(e => [e.url,e])).values()];
    const preferred = uniqueStreams.find(x => x.sourceId === "nexus") ||
      uniqueStreams.find(x => x.sourceId === "iptv-org") || uniqueStreams[0];
    const categoryCounts = new Map<string,number>();
    for (const e of uniqueStreams) categoryCounts.set(e.category,(categoryCounts.get(e.category)||0)+1);
    const category = [...categoryCounts.entries()].sort((a,b)=>b[1]-a[1])[0]?.[0] || "عامة";
    const aliases = [...new Set(uniqueStreams.map(x=>x.name).filter(x=>x !== preferred.name))];
    const arabic = uniqueStreams.map(x=>x.name).find(x=>/[\u0600-\u06FF]/.test(x)) || arabicAlias(preferred.name);
    const channelName = arabic || preferred.name;
    const externalKey = key;
    let existing = (oldChannels || []).find((x:any) => x.external_source_key === externalKey) ||
      byName.get(normalizeName(channelName)) || byName.get(normalizeName(preferred.name));

    let channelId: string;
    if (existing) {
      channelId = existing.id;
      const update: Record<string,unknown> = {
        name: channelName,
        name_en: preferred.name,
        aliases,
        category,
        stream_url: preferred.url,
        logo_url: preferred.logo || null,
        is_live: true,
        is_published: true,
        external_source_key: externalKey,
        updated_at: new Date().toISOString(),
      };
      const { error } = await db.from("channels").update(update).eq("id", channelId);
      if (error) throw error;
    } else {
      const { data, error } = await db.from("channels").insert({
        name: channelName, name_en: preferred.name, aliases, category,
        stream_url: preferred.url, logo_url: preferred.logo || null,
        is_live: true, is_published: true, external_source_key: externalKey,
      }).select("id").single();
      if (error) throw error;
      channelId = data.id;
      byName.set(normalizeName(channelName), { id: channelId, name: channelName, external_source_key: externalKey });
    }
    summary.channels++;

    for (const stream of uniqueStreams) {
      const sourceKey = stream.sourceId + ":" + await hash(externalKey + "|" + stream.url);
      const { error } = await db.from("playback_servers").upsert({
        channel_id: channelId,
        server_name: stream.sourceName + " • " + (stream.url.includes(".m3u8") ? "HLS" : "DASH"),
        stream_url: stream.url,
        source_key: sourceKey,
        source_id: stream.sourceId,
        source_failures: 0,
        is_active: true,
        sort_order: stream.sourceId === "nexus" ? 0 : stream.sourceId === "iptv-org" ? 1 : 2,
      }, { onConflict: "source_key" });
      if (error) throw error;
      summary.servers++;
    }

    if (!packageIds.has(category)) {
      const packageName = "قنوات تلقائية — " + category;
      const { data, error } = await db.from("content_packages").upsert({
        name: packageName, content_type: "channel", sort_order: 900,
      }, { onConflict: "content_type,name" }).select("id").single();
      if (error) throw error;
      packageIds.set(category, data.id);
      summary.packages++;
    }
    const { error: itemError } = await db.from("content_package_items").upsert({
      package_id: packageIds.get(category),
      content_type: "channel",
      content_id: channelId,
    }, { onConflict: "package_id,content_type,content_id", ignoreDuplicates: true });
    if (itemError) throw itemError;
  }
  return summary;
}

async function probeServer(url: string): Promise<"ok"|"blocked"|"bad"> {
  try {
    const response = await fetch(url, {
      method: "GET",
      redirect: "follow",
      signal: AbortSignal.timeout(12000),
      headers: { "Range": "bytes=0-1023", "User-Agent": "ShamFlix-TV-Health/1.0", "Accept": "*/*" },
    });
    if (response.body) await response.body.cancel().catch(() => {});
    if (response.status === 401 || response.status === 403 || response.status === 451) return "blocked";
    if (response.status === 404 || response.status === 410 || response.status >= 500) return "bad";
    return response.ok || response.status === 206 ? "ok" : "bad";
  } catch { return "bad"; }
}

async function healthCheck(db: ReturnType<typeof createClient>) {
  const { data: servers, error } = await db.from("playback_servers")
    .select("id,stream_url,source_failures")
    .not("source_id","is",null).eq("is_active",true)
    .order("source_checked_at",{ascending:true,nullsFirst:true}).limit(MAX_HEALTH_CHECKS);
  if (error) throw error;
  let checked=0, recovered=0, disabled=0, blocked=0;
  const rows = servers || [];
  for (let i=0; i<rows.length; i+=CONCURRENCY) {
    await Promise.all(rows.slice(i,i+CONCURRENCY).map(async (server:any) => {
      const result = await probeServer(server.stream_url);
      const failures = Number(server.source_failures || 0);
      const nextFailures = result === "bad" ? failures + 1 : result === "ok" ? 0 : failures;
      const active = nextFailures < 3;
      const { error: updateError } = await db.from("playback_servers").update({
        source_checked_at: new Date().toISOString(),
        source_failures: nextFailures,
        is_active: active,
      }).eq("id",server.id);
      if (updateError) throw updateError;
      checked++;
      if (result === "blocked") blocked++;
      if (result === "ok" && failures > 0) recovered++;
      if (!active) disabled++;
    }));
  }
  return { checked, recovered, disabled, geoBlockedOrAuthProtected: blocked };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const token = req.headers.get("x-shamflix-tv-secret") || "";
  if (!token) return json({ error: "Unauthorized" }, 401);
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return json({ error: "Server configuration missing" }, 500);

  const db = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
  if (!await verifySecret(db, token)) return json({ error: "Unauthorized" }, 401);

  let body: Record<string,unknown> = {};
  try { body = await req.json(); } catch {}
  try {
    if (body.mode === "health") return json({ ok: true, mode: "health", result: await healthCheck(db) });
    return json({ ok: true, mode: "sync", result: await syncChannels(db) });
  } catch (error) {
    return json({ ok: false, error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
