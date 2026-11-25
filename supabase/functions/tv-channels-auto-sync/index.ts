import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type PlaylistSource = { id: string; name: string; url: string; dbId: string; sourceType: string; isBuiltin: boolean; storagePath?: string };

// Sources are managed in public.tv_channel_sources so every built-in and custom
// playlist can be enabled or paused independently from the admin panel.
const MAX_CUSTOM_SOURCES = 20;

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
    // Ignore spaces and separators such as hyphens, but preserve meaningful + and &.
    .replace(/[^\p{L}\p{N}+&]+/gu, "");
}

function baseChannelName(value: string): string {
  return clean(value).normalize("NFKC")
    // Remove codec / quality markers that identify a stream variant, not a channel.
    .replace(/\s*[([]?\s*(?:SD|HD|FHD|UHD|4K|8K|H\.?265|HEVC|AVC|X\.?265|HDR|[0-9]{3,4}\s*[pPiI])\s*[)\]]?\s*$/i, "")
    .replace(/\s+(?:FULL\s*HD|ULTRA\s*HD|FHD|UHD|HD|SD)\s*(?=\d+\b)/gi, " ")
    .replace(/\b(?:H\.?265|HEVC|AVC|X\.?265)\b/gi, " ")
    .replace(/\s*[ⓈⒼⓅⒽⓊ]+\s*$/u, "")
    .replace(/\s+/g, " ").trim();
}

function qualityLabel(name: string, url: string): string {
  const value = name + " " + url;
  if (/\b8k\b|7680\s*[xX]\s*4320|4320\s*[pPiI]/i.test(value)) return "8K";
  if (/\b4k\b|2160\s*[pPiI]|3840\s*[xX]\s*2160/i.test(value)) return "4K";
  if (/\b(?:uhd|fhd)\b|1080\s*[pPiI]|1920\s*[xX]\s*1080/i.test(value)) return "FHD";
  if (/\bhd\b|720\s*[pPiI]|1280\s*[xX]\s*720/i.test(value)) return "HD";
  if (/\bsd\b|480\s*[pPiI]|576\s*[pPiI]/i.test(value)) return "SD";
  return "غير محددة";
}

function canonicalKey(_tvgId: string, name: string, _sourceId: string): string {
  const baseName = baseChannelName(name);
  const alias = arabicAlias(baseName);
  // A channel is identified by its normalized display name, not by the source's
  // tvg-id. This merges source variants and resolution variants into one entry.
  return "name:" + normalizeName(alias || baseName);
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
    if (!/\.m3u8?(?:$|\?)|\.mpd(?:$|\?)|\.ts(?:$|\?)/i.test(u.pathname + u.search)) return null;
    u.hash = "";
    return u.toString();
  } catch { return null; }
}

function categoryOf(raw: string, name: string): string {
  const v = (raw + " " + name).toLowerCase();
  if (/\bmbc\b|ام بي سي|إم بي سي/.test(v)) return "MBC";
  if (/\bbein(?:\s*[- ]?\s*sports?)?\b|بي ?إن ?سبورت/.test(v)) return "beIN SPORTS";
  if (/sport|رياض|football|soccer|كرة|الكأس|ssc|sportklub/.test(v)) return "رياضية";
  if (/news|اخبار|إخبار|خبر|العربية|الجزيرة|سكاي نيوز|bbc news|cnn|france 24|euronews/.test(v)) return "إخبارية";
  if (/movie|film|cinema|سينما|أفلام|افلام|قناة فيلم/.test(v)) return "أفلام";
  if (/kids|children|cartoon|animation|طفل|أطفال|اطفال|كرتون|براعم|طيور الجنة/.test(v)) return "أطفال";
  if (/documentary|document|وثائقي|ناشيونال|discovery|history channel|animal planet/.test(v)) return "وثائقية";
  if (/music|موسيقى|اغاني|أغاني|melody|rotana music|mtv music/.test(v)) return "موسيقى";
  if (/relig|islam|quran|قرآن|قران|ديني|كنيسة|church/.test(v)) return "دينية";
  if (/series|drama|مسلسل|دراما|ترفيه|entertainment|comedy/.test(v)) return "ترفيهية";
  return "عامة";
}

function isArabicOrTurkishChannel(entry: {name:string; tvgLanguage:string; tvgCountry:string; groupTitle:string}): boolean {
  const language = normalizeName(entry.tvgLanguage);
  const country = normalizeName(entry.tvgCountry);
  const group = normalizeName(entry.groupTitle);
  const name = normalizeName(entry.name);
  const arabicCountries = new Set(["dz","alg","algeria","bh","bhr","bahrain","km","comoros","dj","djibouti","eg","egy","egypt","iq","irq","iraq","jo","jor","jordan","kw","kwt","kuwait","lb","lbn","lebanon","ly","lby","libya","mr","mauritania","ma","mar","morocco","om","omn","oman","ps","pse","palestine","qa","qat","qatar","sa","sau","saudiarabia","so","somalia","sd","sdn","sudan","sy","syr","syria","tn","tun","tunisia","ye","yem","yemen","ae","are","uae","unitedarabemirates"]);
  const turkishCountries = new Set(["tr","tur","turkey","turkiye","تركيا"]);
  if (/(^|[^a-z])(?:ar|ara|arabic)([^a-z]|$)/i.test(entry.tvgLanguage) ||
      /عربي|العربية|arabic/.test(entry.tvgLanguage + " " + entry.groupTitle) ||
      /[\u0600-\u06FF]/.test(entry.name) || arabicCountries.has(country)) return true;
  if (/(^|[^a-z])(?:tr|tur|turkish)([^a-z]|$)/i.test(entry.tvgLanguage) ||
      /turkce|turkish|turkiye|تركي|تركية/.test(language + " " + group) ||
      turkishCountries.has(country)) return true;
  if (/\b(?:trt ?[1-9]|trt ?haber|atv|kanal ?d|show ?tv|star ?tv|tv8|now ?tv|beyaz ?tv|a ?haber|a ?spor|teve ?2|kanal ?7|fox ?turkey)\b/i.test(entry.name) ||
      /[ğüşöçıİ]/.test(entry.name)) return true;
  return false;
}


function countryPackageLabel(entry: {name:string; tvgLanguage:string; tvgCountry:string; groupTitle:string}): string {
  const raw = normalizeName(entry.tvgCountry);
  const countries: Record<string,string> = {
    dz:"الجزائر", alg:"الجزائر", algeria:"الجزائر", bh:"البحرين", bhr:"البحرين", bahrain:"البحرين",
    km:"جزر القمر", comoros:"جزر القمر", dj:"جيبوتي", djibouti:"جيبوتي", eg:"مصر", egy:"مصر", egypt:"مصر",
    iq:"العراق", irq:"العراق", iraq:"العراق", jo:"الأردن", jor:"الأردن", jordan:"الأردن", kw:"الكويت", kwt:"الكويت", kuwait:"الكويت",
    lb:"لبنان", lbn:"لبنان", lebanon:"لبنان", ly:"ليبيا", lby:"ليبيا", libya:"ليبيا", mr:"موريتانيا", mauritania:"موريتانيا",
    ma:"المغرب", mar:"المغرب", morocco:"المغرب", om:"عُمان", omn:"عُمان", oman:"عُمان", ps:"فلسطين", pse:"فلسطين", palestine:"فلسطين",
    qa:"قطر", qat:"قطر", qatar:"قطر", sa:"السعودية", sau:"السعودية", saudiarabia:"السعودية", so:"الصومال", somalia:"الصومال",
    sd:"السودان", sdn:"السودان", sudan:"السودان", sy:"سوريا", syr:"سوريا", syria:"سوريا", tn:"تونس", tun:"تونس", tunisia:"تونس",
    ye:"اليمن", yem:"اليمن", yemen:"اليمن", ae:"الإمارات", are:"الإمارات", uae:"الإمارات", unitedarabemirates:"الإمارات",
    tr:"تركيا", tur:"تركيا", turkey:"تركيا", turkiye:"تركيا",
  };
  if (countries[raw]) return countries[raw];
  if (/[\u0600-\u06FF]/.test(entry.name) || /arabic|عربي|العربية/i.test(entry.tvgLanguage + " " + entry.groupTitle)) return "قنوات عربية متنوعة";
  if (/turkish|turkce|تركي|تركية/i.test(entry.tvgLanguage + " " + entry.groupTitle) ||
      /\b(?:trt ?[1-9]|trt ?haber|atv|kanal ?d|show ?tv|star ?tv|tv8|now ?tv|beyaz ?tv|a ?haber|a ?spor|teve ?2|kanal ?7|fox ?turkey)\b/i.test(entry.name) ||
      /[ğüşöçıİ]/.test(entry.name)) return "تركيا";
  return "قنوات عربية متنوعة";
}

function extinfNameSeparator(line: string): number {
  // EXTINF attributes may contain commas inside quoted values (notably User-Agent).
  // Only the first comma outside quotes separates attributes from the channel name.
  let quote = "";
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (quote) {
      if (ch === quote && line[i - 1] !== "\\") quote = "";
      continue;
    }
    if (ch === '"' || ch === "'") {
      quote = ch;
      continue;
    }
    if (ch === ",") return i;
  }
  return -1;
}

function parseM3u(text: string, sourceId: string, sourceName: string) {
  const result: Array<{sourceId:string;sourceName:string;key:string;name:string;nameEn:string;tvgId:string;logo:string;category:string;url:string;position:number;tvgLanguage:string;tvgCountry:string;groupTitle:string}> = [];
  let pending: Record<string,string> | null = null;
  let displayName = "";
  let position = 0;
  for (const raw of text.replace(/^\uFEFF/, "").split(/\r?\n/)) {
    const line = raw.trim();
    if (!line) continue;
    if (line.startsWith("#EXTINF")) {
      const comma = extinfNameSeparator(line);
      const attributes = comma >= 0 ? line.slice(0, comma) : line;
      pending = parseAttrs(attributes);
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
        sourceName,
        key: canonicalKey(tvgId, name, sourceId),
        name,
        nameEn: name,
        tvgId,
        logo: pending["tvg-logo"] || "",
        category: categoryOf(pending["group-title"] || "", name),
        url,
        position: position++,
        tvgLanguage: pending["tvg-language"] || pending["tvg-language-code"] || "",
        tvgCountry: pending["tvg-country"] || pending["country"] || (sourceId.startsWith("iptv-org-country-") ? sourceId.slice("iptv-org-country-".length) : ""),
        groupTitle: pending["group-title"] || "",
      });
    }
    pending = null;
    displayName = "";
    if (result.length >= MAX_ENTRIES_PER_SOURCE) break;
  }
  return result;
}
function isPublicIpAddress(address: string): boolean {
  const value = address.toLowerCase().split("%")[0];
  if (value.includes(":")) {
    // Only globally routable IPv6 unicast addresses are accepted.
    if (value.startsWith("2001:db8:")) return false;
    const first = parseInt(value.split(":")[0] || "0", 16);
    return first >= 0x2000 && first <= 0x3fff;
  }
  const parts = value.split(".").map(Number);
  if (parts.length !== 4 || parts.some(x => !Number.isInteger(x) || x < 0 || x > 255)) return false;
  const [a,b] = parts;
  if (a === 0 || a === 10 || a === 127 || a >= 224) return false;
  if (a === 169 && b === 254) return false;
  if (a === 172 && b >= 16 && b <= 31) return false;
  if (a === 192 && (b === 168 || b === 0)) return false;
  if (a === 100 && b >= 64 && b <= 127) return false;
  if (a === 198 && (b === 18 || b === 19 || b === 51)) return false;
  if (a === 203 && b === 0) return false;
  return true;
}

async function validatePublicPlaylistUrl(url: URL, allowNonStandardPort = false) {
  const host = url.hostname.toLowerCase();
  if (url.protocol !== "https:" || url.username || url.password ||
      (url.port && url.port !== "443" && !allowNonStandardPort) || !host || host === "localhost" ||
      host.endsWith(".localhost") || host.endsWith(".local") ||
      host.endsWith(".internal") || host.endsWith(".test") ||
      host.includes(":") || /^\d{1,3}(?:\.\d{1,3}){3}$/.test(host)) {
    throw new Error("Only public HTTPS playlist URLs are allowed");
  }
  const records: string[] = [];
  try { records.push(...await Deno.resolveDns(host, "A")); } catch {}
  try { records.push(...await Deno.resolveDns(host, "AAAA")); } catch {}
  if (!records.length || records.some(address => !isPublicIpAddress(address))) {
    throw new Error("Playlist host did not resolve exclusively to public IP addresses");
  }
}

async function fetchPlaylist(source: PlaylistSource, db: any) {
  if (source.sourceType === "m3u_file") {
    if (!source.storagePath) throw new Error(source.id + " has no uploaded playlist file");
    const { data, error } = await db.storage.from("tv-source-playlists").download(source.storagePath);
    if (error || !data) throw new Error(source.id + " playlist file could not be read");
    if (data.size > MAX_PLAYLIST_BYTES) throw new Error(source.id + " playlist exceeds size limit");
    const body = await data.text();
    if (!body.trimStart().startsWith("#EXTM3U")) throw new Error(source.id + " uploaded file is not a valid M3U playlist");
    const entries = parseM3u(body, source.id, source.name);
    if (!entries.length) throw new Error(source.id + " contained no supported direct HLS/DASH streams");
    return entries;
  }
  let current = new URL(source.url);
  let response: Response | null = null;
  for (let hop = 0; hop <= 3; hop++) {
    await validatePublicPlaylistUrl(current, source.sourceType === "xtream");
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
  const entries = parseM3u(body, source.id, source.name);
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
  const beinNumber = n.match(/^(?:بينسبورت|بيانسبورت|بينسبورتس|بيانسبورتس)(\d+)$/);
  if (beinNumber) return "beIN SPORTS " + beinNumber[1];
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


function countriesOrder(label: string): number {
  const order = ["السعودية","الإمارات","مصر","قطر","الكويت","البحرين","عُمان","اليمن","العراق","سوريا","لبنان","الأردن","فلسطين","المغرب","الجزائر","تونس","ليبيا","السودان","موريتانيا","الصومال","جيبوتي","جزر القمر","تركيا","قنوات عربية متنوعة"];
  const index = order.indexOf(label);
  return index < 0 ? 100 : 40 + index;
}


async function verifyAdminBearer(db: any, req: Request): Promise<boolean> {
  const authorization = req.headers.get("authorization") || "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match) return false;
  const { data, error } = await db.auth.getUser(match[1]);
  if (error || !data?.user) return false;
  const user = data.user as any;
  return user.id === "dda16adb-3b6e-4244-a028-83df88b7801d" ||
    ["admin","manager"].includes(String(user.app_metadata?.role || ""));
}


async function getBuiltinImportEnabled(db: any): Promise<boolean> {
  const { data, error } = await db.from("tv_source_global_settings")
    .select("built_in_import_enabled").eq("id", "global").maybeSingle();
  if (error) throw new Error("Built-in TV setting lookup: " + JSON.stringify(error));
  return data?.built_in_import_enabled !== false;
}

async function deleteEmptyAutomaticChannelPackages(db: any) {
  const { data: packages, error: packageError } = await db.from("content_packages")
    .select("id").eq("content_type", "channel").like("name", "قنوات تلقائية — %");
  if (packageError) throw new Error("automatic package cleanup lookup: " + JSON.stringify(packageError));

  const packageIds = (packages || []).map((row: any) => String(row.id));
  if (!packageIds.length) return { checked: 0, deleted: 0 };

  // Consider every membership type before deleting a package. This protects any
  // package that still contains content, even if its type metadata is unexpected.
  const nonEmptyPackageIds = new Set<string>();
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await db.from("content_package_items")
      .select("package_id").in("package_id", packageIds)
      .order("package_id").range(offset, offset + 999);
    if (error) throw new Error("automatic package contents lookup: " + JSON.stringify(error));
    for (const item of data || []) nonEmptyPackageIds.add(String(item.package_id));
    if (!data || data.length < 1000) break;
  }

  const emptyPackageIds = packageIds.filter((id: string) => !nonEmptyPackageIds.has(id));
  for (let i = 0; i < emptyPackageIds.length; i += 500) {
    const { error } = await db.from("content_packages").delete().in("id", emptyPackageIds.slice(i, i + 500));
    if (error) throw new Error("empty automatic package deletion: " + JSON.stringify(error));
  }
  return { checked: packageIds.length, deleted: emptyPackageIds.length };
}

async function mergeDuplicateImportedChannels(db: any, rows: any[]) {
  const groups = new Map<string, any[]>();
  for (const row of rows) {
    const key = canonicalKey("", String(row.name_en || row.name || ""), "");
    if (!key || key === "name:") continue;
    const group = groups.get(key) || [];
    group.push(row);
    groups.set(key, group);
  }

  const mergedIds = new Set<string>();
  let mergedChannels = 0;
  for (const group of groups.values()) {
    if (group.length < 2) continue;
    group.sort((a, b) =>
      Number(b.is_published === true) - Number(a.is_published === true) ||
      String(a.id).localeCompare(String(b.id))
    );
    const survivor = group[0];
    const aliases = new Set<string>(Array.isArray(survivor.aliases) ? survivor.aliases.map(String) : []);
    for (const duplicate of group.slice(1)) {
      if (String(duplicate.id) === String(survivor.id)) continue;

      const duplicateNames = [duplicate.name, duplicate.name_en]
        .map((x: unknown) => clean(x))
        .filter((x: string) => x && x !== survivor.name && x !== survivor.name_en);
      for (const name of duplicateNames) aliases.add(name);
      if (Array.isArray(duplicate.aliases)) {
        for (const alias of duplicate.aliases) {
          const value = clean(alias);
          if (value) aliases.add(value);
        }
      }

      const { error: serverError } = await db.from("playback_servers")
        .update({ channel_id: survivor.id }).eq("channel_id", duplicate.id);
      if (serverError) throw new Error("duplicate channel server merge: " + JSON.stringify(serverError));

      const { data: memberships, error: membershipError } = await db.from("content_package_items")
        .select("id,package_id")
        .eq("content_type", "channel")
        .eq("content_id", duplicate.id);
      if (membershipError) throw new Error("duplicate channel package lookup: " + JSON.stringify(membershipError));
      if (memberships?.length) {
        const moved = memberships.map((item: any) => ({
          package_id: item.package_id,
          content_type: "channel",
          content_id: survivor.id,
        }));
        const { error: moveError } = await db.from("content_package_items")
          .upsert(moved, { onConflict: "package_id,content_type,content_id", ignoreDuplicates: true });
        if (moveError) throw new Error("duplicate channel package merge: " + JSON.stringify(moveError));
        const { error: deleteMembershipError } = await db.from("content_package_items")
          .delete().in("id", memberships.map((item: any) => item.id));
        if (deleteMembershipError) throw new Error("duplicate channel old package cleanup: " + JSON.stringify(deleteMembershipError));
      }

      const { error: hideError } = await db.from("channels")
        .update({ is_published: false }).eq("id", duplicate.id);
      if (hideError) throw new Error("duplicate channel hide: " + JSON.stringify(hideError));
      mergedIds.add(String(duplicate.id));
      mergedChannels++;
    }

    const { error: aliasError } = await db.from("channels")
      .update({ aliases: [...aliases] }).eq("id", survivor.id);
    if (aliasError) throw new Error("merged channel aliases update: " + JSON.stringify(aliasError));
  }
  return { rows: rows.filter(row => !mergedIds.has(String(row.id))), mergedChannels };
}

async function disableInactiveSourceServers(db: any, activeSourceIds: Set<string>) {
  const staleServerIds: string[] = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await db.from("playback_servers")
      .select("id,source_id")
      .not("source_id", "is", null)
      .eq("is_active", true)
      .order("id")
      .range(offset, offset + 999);
    if (error) throw new Error("active imported server lookup: " + JSON.stringify(error));
    for (const row of data || []) {
      if (!activeSourceIds.has(String(row.source_id))) staleServerIds.push(String(row.id));
    }
    if (!data || data.length < 1000) break;
  }
  for (let i = 0; i < staleServerIds.length; i += 500) {
    const { error } = await db.from("playback_servers")
      .update({ is_active: false }).in("id", staleServerIds.slice(i, i + 500));
    if (error) throw new Error("inactive/orphan source server pause: " + JSON.stringify(error));
  }
  return staleServerIds.length;
}

async function hideInactiveImportedChannels(db: any) {
  const activeChannelIds = new Set<string>();
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await db.from("playback_servers")
      .select("channel_id").not("source_id", "is", null).eq("is_active", true)
      .order("channel_id").range(offset, offset + 999);
    if (error) throw new Error("active channel lookup: " + JSON.stringify(error));
    for (const row of data || []) if (row.channel_id) activeChannelIds.add(String(row.channel_id));
    if (!data || data.length < 1000) break;
  }

  const importedIds: string[] = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await db.from("channels").select("id")
      .not("external_source_key", "is", null).order("id").range(offset, offset + 999);
    if (error) throw new Error("imported channel lookup: " + JSON.stringify(error));
    for (const row of data || []) importedIds.push(String(row.id));
    if (!data || data.length < 1000) break;
  }
  const visible = importedIds.filter(id => activeChannelIds.has(id));
  const hidden = importedIds.filter(id => !activeChannelIds.has(id));
  for (let i = 0; i < visible.length; i += 500) {
    const { error } = await db.from("channels").update({ is_published: true }).in("id", visible.slice(i, i + 500));
    if (error) throw new Error("restore channel visibility: " + JSON.stringify(error));
  }
  for (let i = 0; i < hidden.length; i += 500) {
    const { error } = await db.from("channels").update({ is_published: false }).in("id", hidden.slice(i, i + 500));
    if (error) throw new Error("hide channel visibility: " + JSON.stringify(error));
  }

  const { data: packages, error: packageError } = await db.from("content_packages")
    .select("id").eq("content_type", "channel").like("name", "قنوات تلقائية — %");
  if (packageError) throw new Error("automatic package lookup: " + JSON.stringify(packageError));
  const packageIds = (packages || []).map((row: any) => String(row.id));
  if (packageIds.length) {
    const staleIds: string[] = [];
    for (let offset = 0; ; offset += 1000) {
      const { data, error } = await db.from("content_package_items")
        .select("id,content_id").in("package_id", packageIds).eq("content_type", "channel")
        .order("id").range(offset, offset + 999);
      if (error) throw new Error("automatic package membership lookup: " + JSON.stringify(error));
      for (const item of data || []) {
        if (!activeChannelIds.has(String(item.content_id))) staleIds.push(String(item.id));
      }
      if (!data || data.length < 1000) break;
    }
    for (let i = 0; i < staleIds.length; i += 500) {
      const { error } = await db.from("content_package_items").delete().in("id", staleIds.slice(i, i + 500));
      if (error) throw new Error("automatic package cleanup: " + JSON.stringify(error));
    }
  }
  await deleteEmptyAutomaticChannelPackages(db);
}

async function setBuiltinImportEnabled(db: any, enabled: boolean) {
  const { error: settingError } = await db.from("tv_source_global_settings").upsert({
    id: "global", built_in_import_enabled: enabled, updated_at: new Date().toISOString(),
  }, { onConflict: "id" });
  if (settingError) throw new Error("Built-in TV setting update: " + JSON.stringify(settingError));

  if (!enabled) {
    const { data: builtins, error } = await db.from("tv_channel_sources")
      .select("source_key").eq("is_builtin", true);
    if (error) throw new Error("Built-in source lookup: " + JSON.stringify(error));
    const sourceIds = (builtins || []).map((row: any) => String(row.source_key || "")).filter(Boolean);
    if (sourceIds.length) {
      const { error: pauseError } = await db.from("playback_servers")
        .update({ is_active: false }).in("source_id", sourceIds);
      if (pauseError) throw new Error("Built-in stream pause: " + JSON.stringify(pauseError));
    }
    await hideInactiveImportedChannels(db);
    return { enabled: false, hiddenImmediately: true };
  }

  const sync = await syncChannels(db);
  return { enabled: true, sync };
}

async function syncChannels(db: any) {
  const { data: allSourceRows, error: sourceLookupError } = await db.from("tv_channel_sources")
    .select("id,name,playlist_url,source_key,is_builtin,is_active,source_type,xtream_server_url,xtream_username,xtream_password,playlist_storage_path")
    .order("created_at", { ascending: true });
  if (sourceLookupError) throw new Error("TV source lookup: " + JSON.stringify(sourceLookupError));
  const builtinEnabled = await getBuiltinImportEnabled(db);
  const customRows = (allSourceRows || []).filter((row: any) => row.is_builtin !== true);
  if (customRows.length > MAX_CUSTOM_SOURCES) {
    throw new Error("Too many custom TV sources; maximum is " + MAX_CUSTOM_SOURCES);
  }
  const sources: PlaylistSource[] = (allSourceRows || [])
    .filter((row: any) => row.is_active === true && (row.is_builtin !== true || builtinEnabled))
    .map((row: any) => {
      const sourceType = String(row.source_type || "m3u_url");
      let sourceUrl = String(row.playlist_url || "");
      if (sourceType === "xtream") {
        try {
          const base = new URL(String(row.xtream_server_url || ""));
          if (base.protocol !== "https:" || base.username || base.password) {
            throw new Error("invalid Xtream URL");
          }
          base.pathname = base.pathname.replace(/\/$/, "") + "/get.php";
          base.search = "";
          base.searchParams.set("username", String(row.xtream_username || ""));
          base.searchParams.set("password", String(row.xtream_password || ""));
          base.searchParams.set("type", "m3u_plus");
          base.searchParams.set("output", "m3u8");
          sourceUrl = base.toString();
        } catch {
          // Keep this source isolated; its failure is recorded without aborting other sources.
          sourceUrl = "invalid://xtream-source";
        }
      }
      return {
        id: row.source_key ? String(row.source_key) : (sourceType === "xtream" ? "xtream:" : "custom:") + String(row.id),
        dbId: String(row.id),
        name: clean(row.name).slice(0, 80),
        url: sourceUrl,
        sourceType,
        isBuiltin: row.is_builtin === true,
        storagePath: row.playlist_storage_path ? String(row.playlist_storage_path) : undefined,
      };
    });

  // Pausing a source immediately disables its previously imported stream rows.
  // A channel remains visible if another active source still provides a stream for it.
  const pausedSourceIds = (allSourceRows || [])
    .filter((row: any) => row.is_active !== true || (row.is_builtin === true && !builtinEnabled))
    .map((row: any) => row.source_key ? String(row.source_key) :
      (String(row.source_type || "m3u_url") === "xtream" ? "xtream:" : "custom:") + String(row.id));
  if (pausedSourceIds.length) {
    const { error } = await db.from("playback_servers")
      .update({ is_active: false })
      .in("source_id", pausedSourceIds);
    if (error) throw new Error("paused source stream update: " + JSON.stringify(error));
  }
  // Also disable legacy/orphan stream rows whose source was deleted or no longer
  // exists in tv_channel_sources. Only currently enabled sources remain active.
  const activeSourceIds = new Set(sources.map(source => source.id));
  const disabledStaleServers = await disableInactiveSourceServers(db, activeSourceIds);

  // Each source is reconciled independently. A failed source must never affect its saved servers.
  const settledSources = await Promise.all(sources.map(async source => {
    try {
      return { status: "fulfilled" as const, source, entries: await fetchPlaylist(source, db) };
    } catch (reason) {
      return { status: "rejected" as const, source, reason };
    }
  }));
  const sourceResults = settledSources
    .filter((x): x is {status:"fulfilled";source:PlaylistSource;entries:ReturnType<typeof parseM3u>} => x.status === "fulfilled")
    .map(x => ({
      source: x.source,
      // Built-in public catalogues keep their Arabic/Turkish focus.
      // User-added Xtream and M3U sources are imported in every language.
      entries: x.source.isBuiltin ? x.entries.filter(isArabicOrTurkishChannel) : x.entries,
    }));
  const sourceErrors = settledSources.filter((x): x is {status:"rejected";source:PlaylistSource;reason:unknown} => x.status === "rejected");

  const checkedAt = new Date().toISOString();
  for (const result of settledSources) {
    if (!result.source.dbId) continue;
    const status = result.status === "fulfilled"
      ? { last_checked_at: checkedAt, last_error: null, last_entry_count: result.source.isBuiltin ? result.entries.filter(isArabicOrTurkishChannel).length : result.entries.length }
      : { last_checked_at: checkedAt, last_error: String(result.reason instanceof Error ? result.reason.message : result.reason).slice(0, 1000) };
    const { error } = await db.from("tv_channel_sources").update({ ...status, updated_at: checkedAt }).eq("id", result.source.dbId);
    if (error) throw new Error("TV source status update: " + JSON.stringify(error));
  }
  if (!sourceResults.length && !pausedSourceIds.length && activeSourceIds.size > 0) {
    throw new Error("All active playlist sources failed; existing catalogue was left untouched");
  }
  const grouped = new Map<string, typeof sourceResults[number]["entries"]>();
  for (const { entries } of sourceResults) {
    for (const entry of entries) {
      const group = grouped.get(entry.key) || [];
      if (!group.some(x => x.url === entry.url)) group.push(entry);
      grouped.set(entry.key, group);
    }
  }
  if (!grouped.size && !pausedSourceIds.length && activeSourceIds.size > 0) {
    throw new Error("No channels were aggregated from active sources; existing catalogue was left untouched");
  }
  if (grouped.size > MAX_CHANNELS_PER_RUN) throw new Error("Playlist set exceeded the safe per-run channel limit; existing catalogue was left untouched");

  const oldChannels: any[] = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await db.from("channels")
      .select("id,external_source_key,name,name_en,aliases,is_published").not("external_source_key","is",null)
      .order("id").range(offset, offset + 999);
    if (error) throw new Error("existing channel lookup: " + JSON.stringify(error));
    oldChannels.push(...(data || []));
    if (!data || data.length < 1000) break;
  }
  const dedupeResult = await mergeDuplicateImportedChannels(db, oldChannels);
  const canonicalChannels = dedupeResult.rows;
  const byExternalKey = new Map<string, any>();
  const byCanonicalName = new Map<string, any>();
  for (const row of canonicalChannels) {
    byExternalKey.set(row.external_source_key, row);
    const canonical = canonicalKey("", String(row.name_en || row.name || ""), "");
    if (!byCanonicalName.has(canonical)) byCanonicalName.set(canonical, row);
  }

  const channelRows: Record<string,unknown>[] = [];
  const streamRows: Record<string,unknown>[] = [];
  const categoryByKey = new Map<string,string>();
  const assignedChannelIds = new Set<string>();
  for (const [key, entries] of grouped) {
    // The same URL may legitimately belong to multiple sources; dedupe only within a source.
    const uniqueStreams = [...new Map(entries.map(e => [e.sourceId + "|" + e.url,e])).values()];
    const preferred = uniqueStreams.find(x => x.sourceId === "iptv-org") ||
      uniqueStreams.find(x => x.sourceId === "nexus") || uniqueStreams[0];
    const categoryCounts = new Map<string,number>();
    for (const e of uniqueStreams) categoryCounts.set(e.category,(categoryCounts.get(e.category)||0)+1);
    const category = [...categoryCounts.entries()].sort((a,b)=>b[1]-a[1])[0]?.[0] || "عامة";
    const aliases = [...new Set(uniqueStreams.map(x=>x.name).filter(x=>x !== preferred.name))];
    const arabic = uniqueStreams.map(x=>x.name).find(x=>/[\u0600-\u06FF]/.test(x)) || arabicAlias(preferred.name);
    const channelName = arabic || baseChannelName(preferred.name);
    const existing = byExternalKey.get(key) || byCanonicalName.get(key) || null;
    const assignedId = existing?.id && !assignedChannelIds.has(existing.id) ? existing.id : crypto.randomUUID();
    assignedChannelIds.add(assignedId);
    const channelRow: Record<string,unknown> = {
      id: assignedId,
      name: channelName,
      name_en: baseChannelName(preferred.name),
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
        server_name: stream.sourceName + " • " + qualityLabel(stream.name, stream.url) + " • " + (stream.url.includes(".m3u8") ? "HLS" : stream.url.includes(".ts") ? "MPEG-TS" : "DASH"),
        stream_url: stream.url,
        source_key: stream.sourceId + ":" + await hash(key + "|" + stream.url),
        source_id: stream.sourceId,
        source_seen_at: new Date().toISOString(),
        source_position: stream.position,
        source_failures: 0,
        is_active: true,
        sort_order: stream.sourceId === "iptv-org" ? 0 : stream.sourceId === "nexus" ? 1 : 2,
      });
    }
  }

  // Upsert channel rows in batches; stable source keys prevent duplicate channels on each run.
  for (let i=0; i<channelRows.length; i+=100) {
    const { error } = await db.from("channels").upsert(channelRows.slice(i,i+100), { onConflict:"id" });
    if (error) throw new Error("channels upsert: " + JSON.stringify(error));
  }
  const syncedChannels: any[] = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await db.from("channels")
      .select("id,external_source_key").not("external_source_key","is",null)
      .eq("is_published", true)
      .order("id").range(offset, offset + 999);
    if (error) throw new Error("channel ID lookup: " + JSON.stringify(error));
    syncedChannels.push(...(data || []));
    if (!data || data.length < 1000) break;
  }
  const channelIds = new Map(syncedChannels.map((x:any)=>[x.external_source_key,x.id]));
  const serverRows = streamRows.map((row:any) => {
    const channelId = channelIds.get(row.channel_key);
    const { channel_key, ...server } = row;
    return { ...server, channel_id: channelId };
  }).filter((row:any)=>row.channel_id);

  // Upsert only URLs observed in successfully parsed sources. source_seen_at is refreshed
  // for links still present, while older links that disappeared remain as fallbacks.
  for (let i=0; i<serverRows.length; i+=500) {
    const { error } = await db.from("playback_servers").upsert(serverRows.slice(i,i+500), { onConflict:"source_key" });
    if (error) throw new Error("playback server upsert: " + JSON.stringify(error));
  }

  // Keep only the two most recently observed URLs for each channel + source pair.
  // This bounds history without allowing one source to delete another source's servers.
  const sourceServers: any[] = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await db.from("playback_servers")
      .select("id,channel_id,source_id,source_seen_at,source_position")
      .not("source_id","is",null)
      .order("source_seen_at",{ascending:false,nullsFirst:false})
      .order("source_position",{ascending:false,nullsFirst:false})
      .order("id",{ascending:true})
      .range(offset, offset + 999);
    if (error) throw new Error("server retention lookup: " + JSON.stringify(error));
    sourceServers.push(...(data || []));
    if (!data || data.length < 1000) break;
  }
  const groupedServers = new Map<string, any[]>();
  const successfullySyncedSourceIds = new Set(sourceResults.map(x => x.source.id));
  for (const server of sourceServers || []) {
    // Never prune a source whose playlist failed to fetch or parse in this run.
    if (!successfullySyncedSourceIds.has(server.source_id)) continue;
    const groupKey = server.channel_id + "|" + server.source_id + "|" + (String(server.server_name || "").match(/(?:SD|FHD|UHD|4K|8K|HD|غير محددة)/)?.[0] || "غير محددة");
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

  const packageDefinitions = new Map<string,number>();
  const memberships = new Map<string,Set<string>>();
  for (const [key, entries] of grouped) {
    const uniqueStreams = [...new Map(entries.map(e => [e.sourceId + "|" + e.url,e])).values()];
    const category = categoryByKey.get(key) || "عامة";
    const labels = new Set<string>();
    const country = uniqueStreams.map(countryPackageLabel).find(label => label !== "قنوات عربية متنوعة") || "قنوات عربية متنوعة";
    labels.add(country);
    if (uniqueStreams.some(e => /\bmbc\b|ام بي سي|إم بي سي/i.test(e.name + " " + e.groupTitle))) labels.add("MBC");
    if (uniqueStreams.some(e => /\bbein(?:\s*[- ]?\s*sports?)?\b|بي ?إن ?سبورت/i.test(e.name + " " + e.groupTitle))) labels.add("beIN SPORTS");
    if (category === "رياضية" || category === "beIN SPORTS") labels.add("رياضية");
    if (category !== "رياضية" && category !== "beIN SPORTS" && category !== "MBC") labels.add(category);
    memberships.set(key, labels);
    for (const label of labels) {
      const priority = label === "beIN SPORTS" ? 10 : label === "رياضية" ? 20 : label === "MBC" ? 30 : countriesOrder(label);
      packageDefinitions.set(label, priority);
    }
  }
  const packageRows = [...packageDefinitions.entries()].map(([label,sort_order]) => ({
    name: "قنوات تلقائية — " + label, content_type: "channel", sort_order,
  }));
  if (packageRows.length) {
    const { error: packageError } = await db.from("content_packages")
      .upsert(packageRows, { onConflict:"content_type,name" });
    if (packageError) throw new Error("package upsert: " + JSON.stringify(packageError));
  }
  const { data: packages, error: packagesError } = await db.from("content_packages")
    .select("id,name").like("name","قنوات تلقائية — %").eq("content_type","channel");
  if (packagesError) throw new Error("package lookup: " + JSON.stringify(packagesError));
  const packageIds = new Map((packages || []).map((x:any)=>[x.name,x.id]));
  const itemRows: Record<string,unknown>[] = [];
  for (const [key,labels] of memberships) {
    const channelId = channelIds.get(key);
    if (!channelId) continue;
    for (const label of labels) {
      const packageId = packageIds.get("قنوات تلقائية — " + label);
      if (packageId) itemRows.push({ package_id:packageId, content_type:"channel", content_id:channelId });
    }
  }
  // Add/update automatic package memberships for channels supplied by active sources.
  for (let i=0; i<itemRows.length; i+=500) {
    const { error } = await db.from("content_package_items")
      .upsert(itemRows.slice(i,i+500), { onConflict:"package_id,content_type,content_id", ignoreDuplicates:true });
    if (error) throw error;
  }

  // Hide channels that no longer have any active source stream from automatic channel
  // packages. If another active source still provides the same channel, it stays visible.
  const activeSourceChannelIds = new Set<string>();
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await db.from("playback_servers")
      .select("channel_id")
      .not("source_id","is",null)
      .eq("is_active",true)
      .order("channel_id")
      .range(offset, offset + 999);
    if (error) throw new Error("active source channel lookup: " + JSON.stringify(error));
    for (const row of data || []) if (row.channel_id) activeSourceChannelIds.add(String(row.channel_id));
    if (!data || data.length < 1000) break;
  }

  // The all-channels screen reads channels.is_published directly, so synchronize
  // publication state as well as automatic package membership.
  const importedChannelIds: string[] = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await db.from("channels")
      .select("id")
      .not("external_source_key","is",null)
      .order("id")
      .range(offset, offset + 999);
    if (error) throw new Error("imported channel visibility lookup: " + JSON.stringify(error));
    for (const row of data || []) importedChannelIds.push(String(row.id));
    if (!data || data.length < 1000) break;
  }
  const visibleImportedIds = importedChannelIds.filter(id => activeSourceChannelIds.has(id));
  const hiddenImportedIds = importedChannelIds.filter(id => !activeSourceChannelIds.has(id));
  for (let i=0; i<visibleImportedIds.length; i+=500) {
    const { error } = await db.from("channels")
      .update({ is_published: true })
      .in("id", visibleImportedIds.slice(i,i+500));
    if (error) throw new Error("restore active channel visibility: " + JSON.stringify(error));
  }
  for (let i=0; i<hiddenImportedIds.length; i+=500) {
    const { error } = await db.from("channels")
      .update({ is_published: false })
      .in("id", hiddenImportedIds.slice(i,i+500));
    if (error) throw new Error("hide paused-only channels: " + JSON.stringify(error));
  }

  const autoPackageIds = [...packageIds.values()].map(String);
  if (autoPackageIds.length) {
    const staleMembershipIds: string[] = [];
    for (let offset = 0; ; offset += 1000) {
      const { data, error } = await db.from("content_package_items")
        .select("id,content_id")
        .in("package_id", autoPackageIds)
        .eq("content_type","channel")
        .order("id")
        .range(offset, offset + 999);
      if (error) throw new Error("automatic package membership lookup: " + JSON.stringify(error));
      for (const item of data || []) {
        if (!activeSourceChannelIds.has(String(item.content_id))) staleMembershipIds.push(String(item.id));
      }
      if (!data || data.length < 1000) break;
    }
    for (let i=0; i<staleMembershipIds.length; i+=500) {
      const { error } = await db.from("content_package_items")
        .delete()
        .in("id", staleMembershipIds.slice(i,i+500));
      if (error) throw new Error("automatic package membership cleanup: " + JSON.stringify(error));
    }
  }
  await deleteEmptyAutomaticChannelPackages(db);

  return {
    channels: channelRows.length,
    servers: serverRows.length,
    packages: packageRows.length,
    sources: [
      ...sourceResults.map(x => ({ id:x.source.id, entries:x.entries.length, status:"synced" })),
      ...sourceErrors.map(x => ({ id:x.source.id, status:"failed", error:String(x.reason instanceof Error ? x.reason.message : x.reason || "fetch failed") })),
    ],
    retainedServerLimit: 2,
    retentionScope: "two latest URLs per channel, source, and quality",
    languageFilter: { builtIn: ["Arabic", "Turkish"], custom: "all" },
    filteredEntries: sourceResults.reduce((n,x)=>n+x.entries.length,0),
    customSources: customRows.length,
    disabledStaleServers,
    mergedDuplicateChannels: dedupeResult.mergedChannels,
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
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return json({ error: "Server configuration missing" }, 500);

  const db: any = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } });
  const cronAuthorized = token ? await verifySecret(db, token) : false;
  const adminAuthorized = cronAuthorized ? false : await verifyAdminBearer(db, req);
  if (!cronAuthorized && !adminAuthorized) return json({ error: "Unauthorized" }, 401);

  let body: Record<string,unknown> = {};
  try { body = await req.json(); } catch {}
  try {
    if (body.mode === "health") return json({ ok: true, mode: "health", result: await healthCheck(db) });
    if (body.mode === "builtin-status") {
      if (!adminAuthorized) return json({ error: "Admin authorization required" }, 403);
      return json({ ok: true, mode: "builtin-status", enabled: await getBuiltinImportEnabled(db) });
    }
    if (body.mode === "set-builtin-import") {
      if (!adminAuthorized || typeof body.enabled !== "boolean") {
        return json({ error: "Admin authorization and a boolean enabled value are required" }, 403);
      }
      return json({ ok: true, mode: "set-builtin-import", result: await setBuiltinImportEnabled(db, body.enabled) });
    }
    return json({ ok: true, mode: "sync", result: await syncChannels(db) });
  } catch (error) {
    return json({ ok: false, error: error instanceof Error ? error.message : JSON.stringify(error) }, 500);
  }
});
