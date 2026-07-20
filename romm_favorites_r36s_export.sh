#!/usr/bin/env bash
# RomM Favorites Export fuer R36S / ArkOS / EmulationStation.
# Keine Python-, pip- oder jq-Abhaengigkeiten.
# Benoetigt nur Bash, curl und auf macOS das vorinstallierte osascript (JXA).

set -u

ROMM=""
USERNAME=""
PASSWORD="${ROMM_PASSWORD:-}"
OUTPUT=""
DOWNLOAD_ROMS=0
DOWNLOAD_MEDIA=0
DRY_RUN=0
COLLECTION_NAMES=()
COLLECTION_IDS=()
COLLECTION_NAME_COUNT=0
COLLECTION_ID_COUNT=0

usage() {
  cat <<'EOF'
Verwendung:
  romm_favorites_r36s_export.sh --romm URL --username USER --output ZIEL [Optionen]

Optionen:
  --romm URL          URL der RomM-Instanz (erforderlich)
  --username USER     RomM Benutzername (erforderlich)
  --password PASS     Passwort; sicherer: ROMM_PASSWORD oder Eingabe-Prompt
  --output PFAD       Zielordner, z.B. ./r36s-export oder /Volumes/EASYROMS
  --collection NAME   RomM Collection exportieren; mehrfach verwendbar
  --collection-id ID  RomM Collection per ID exportieren; mehrfach verwendbar
  --download-roms     ROM-Dateien herunterladen
  --download-media    Alle verfuegbaren RomM-Medien herunterladen
  --dry-run           Nichts ins Ziel schreiben, nur Aktionen anzeigen
  -h, --help          Hilfe anzeigen
EOF
}

fail() { printf 'FEHLER: %s\n' "$*" >&2; exit 1; }
log() { printf '%s\n' "$*"; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --romm) [ "$#" -ge 2 ] || fail "Wert fuer --romm fehlt"; ROMM=$2; shift 2 ;;
    --username) [ "$#" -ge 2 ] || fail "Wert fuer --username fehlt"; USERNAME=$2; shift 2 ;;
    --password) [ "$#" -ge 2 ] || fail "Wert fuer --password fehlt"; PASSWORD=$2; shift 2 ;;
    --output) [ "$#" -ge 2 ] || fail "Wert fuer --output fehlt"; OUTPUT=$2; shift 2 ;;
    --collection) [ "$#" -ge 2 ] || fail "Wert fuer --collection fehlt"; COLLECTION_NAMES+=("$2"); COLLECTION_NAME_COUNT=$((COLLECTION_NAME_COUNT + 1)); shift 2 ;;
    --collection-id) [ "$#" -ge 2 ] || fail "Wert fuer --collection-id fehlt"; case "$2" in ''|*[!0-9]*) fail "Ungueltige Collection-ID: $2" ;; esac; COLLECTION_IDS+=("$2"); COLLECTION_ID_COUNT=$((COLLECTION_ID_COUNT + 1)); shift 2 ;;
    --download-roms) DOWNLOAD_ROMS=1; shift ;;
    --download-media) DOWNLOAD_MEDIA=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) fail "Unbekannte Option: $1" ;;
  esac
done

[ -n "$ROMM" ] || fail "--romm ist erforderlich"
[ -n "$USERNAME" ] || fail "--username ist erforderlich"
[ -n "$OUTPUT" ] || fail "--output ist erforderlich"
command -v curl >/dev/null 2>&1 || fail "curl wurde nicht gefunden"
command -v osascript >/dev/null 2>&1 || fail "osascript wurde nicht gefunden (dieses Script ist fuer macOS)"

ROMM=${ROMM%/}
case "$OUTPUT" in
  ~/*) OUTPUT="$HOME/${OUTPUT#~/}" ;;
esac
case "$OUTPUT" in
  /*) ;;
  *) OUTPUT="$(pwd)/$OUTPUT" ;;
esac

if [ -z "$PASSWORD" ]; then
  printf 'RomM Passwort: ' >&2
  stty -echo
  IFS= read -r PASSWORD
  stty echo
  printf '\n' >&2
fi

TMPDIR_EXPORT=$(mktemp -d "${TMPDIR:-/tmp}/romm-export.XXXXXX") || fail "Temp-Verzeichnis konnte nicht erstellt werden"
cleanup() { rm -rf "$TMPDIR_EXPORT"; }
trap cleanup EXIT HUP INT TERM

JS_HELPER="$TMPDIR_EXPORT/helper.js"
cat > "$JS_HELPER" <<'JXA'
ObjC.import('Foundation');

function text(path) {
  var e = Ref();
  var s = $.NSString.stringWithContentsOfFileEncodingError(path, $.NSUTF8StringEncoding, e);
  if (!s) throw Error('Datei kann nicht gelesen werden: ' + path);
  return ObjC.unwrap(s);
}
function write(path, value) {
  var e = Ref();
  var ok = $(value).writeToFileAtomicallyEncodingError(path, true, $.NSUTF8StringEncoding, e);
  if (!ok) throw Error('Datei kann nicht geschrieben werden: ' + path);
}
function b64(value) {
  var s = String(value == null ? '' : value);
  if (!s) return '-'; // Bash IFS wuerde leere TSV-Spalten zusammenziehen.
  var d = $(s).dataUsingEncoding($.NSUTF8StringEncoding);
  return ObjC.unwrap(d.base64EncodedStringWithOptions(0));
}
function first() {
  for (var i = 0; i < arguments.length; i++) {
    var v = arguments[i];
    if (v == null) continue;
    if (Array.isArray(v)) {
      var a = v.map(String).map(function(x){ return x.trim(); }).filter(Boolean);
      if (a.length) return a.join(', ');
    } else if (String(v).trim()) return String(v).trim();
  }
  return '';
}
function safe(s) {
  s = String(s || '').trim().replace(/[\\/:*?"<>|]+/g, '_').replace(/\s+/g, ' ').replace(/^[ .]+|[ .]+$/g, '');
  return (s.slice(0, 180) || 'unnamed');
}
var platformMap = {
  '3do':'3do','amiga':'amiga','amstrad-cpc':'amstradcpc','arcade':'arcade','atari-2600':'atari2600',
  'atari-5200':'atari5200','atari-7800':'atari7800','atari-800':'atari800','atari-lynx':'atarilynx',
  'atarilynx':'atarilynx','atomiswave':'atomiswave','colecovision':'coleco','commodore-64':'c64','c64':'c64',
  'dreamcast':'dreamcast','famicom':'nes','fbneo':'fbneo','finalburn-neo':'fbneo','game-and-watch':'gameandwatch',
  'game-gear':'gamegear','gamegear':'gamegear','game-boy':'gb','gb':'gb','game-boy-color':'gbc','gbc':'gbc',
  'game-boy-advance':'gba','gba':'gba','genesis':'genesis','intellivision':'intellivision','mame':'mame',
  'mastersystem':'mastersystem','sega-master-system':'mastersystem','mega-drive':'megadrive','megadrive':'megadrive',
  'sega-mega-drive':'megadrive','mega-cd':'segacd','sega-cd':'segacd','msx':'msx','msx2':'msx2',
  'n64':'n64','nintendo-64':'n64','nds':'nds','nintendo-ds':'nds','neogeo':'neogeo','neo-geo':'neogeo',
  'neo-geo-pocket':'ngp','neo-geo-pocket-color':'ngpc','nes':'nes','nintendo-entertainment-system':'nes',
  'nintendo-3ds':'n3ds','3ds':'n3ds','pc-engine':'pcengine','turbografx-16':'pcengine',
  'pc-engine-cd':'pcenginecd','turbografx-cd':'pcenginecd','pico-8':'pico-8','pico8':'pico-8',
  'playstation':'psx','playstation-1':'psx','psx':'psx','psp':'psp','saturn':'saturn','sega-saturn':'saturn',
  'sega-32x':'sega32x','sg-1000':'sg-1000','snes':'snes','super-nintendo':'snes',
  'super-nintendo-entertainment-system':'snes','vectrex':'vectrex','wonderswan':'wonderswan',
  'wonderswan-color':'wonderswancolor','zx-spectrum':'zxspectrum'
};
function systemFolder(r) {
  var keys = [r.platform_fs_slug, r.platform_slug, r.platform_display_name];
  for (var i=0; i<keys.length; i++) {
    var k = String(keys[i] || '').toLowerCase().replace(/_/g,'-').replace(/ /g,'-');
    if (platformMap[k]) return platformMap[k];
  }
  return safe(String(keys[0] || 'unknown').replace(/_/g,'-'));
}
function esDate(v) {
  if (!v) return '';
  var n = Number(v);
  if (!isFinite(n)) return '';
  if (n >= 19000101 && n <= 21001231) return String(Math.floor(n)) + 'T000000';
  var d = new Date(Math.floor(n) * 1000);
  if (isNaN(d.getTime())) return '';
  function z(x){ return String(x).padStart(2,'0'); }
  return d.getUTCFullYear()+z(d.getUTCMonth()+1)+z(d.getUTCDate())+'T000000';
}
function rating(v) {
  if (v == null || v === '') return '';
  var n = Number(String(v).replace(',','.'));
  if (!isFinite(n)) return '';
  if (n > 1) n /= 100;
  return Math.max(0, Math.min(1,n)).toFixed(2);
}
function resource(base, p) {
  if (!p) return '';
  var raw = String(p).trim();
  if (/^https?:\/\//i.test(raw)) return raw;
  var q = raw.indexOf('?');
  var path = q >= 0 ? raw.slice(0, q) : raw;
  var query = q >= 0 ? raw.slice(q).replace(/\s/g, function(c) { return encodeURIComponent(c); }) : '';
  path = path.replace(/^\/+/, '');
  if (!/^assets\//.test(path)) path = 'assets/romm/resources/' + path;
  return base.replace(/\/$/,'') + '/' + path.split('/').map(encodeURIComponent).join('/') + query;
}
function record(r, base) {
  var meta=r.metadatum||{}, igdb=r.igdb_metadata||{}, ss=r.ss_metadata||{}, moby=r.moby_metadata||{}, lb=r.launchbox_metadata||{}, gl=r.gamelist_metadata||{};
  var title=first(r.name,r.fs_name_no_tags,r.fs_name_no_ext,r.fs_name);
  var companies=first(meta.companies,ss.companies,igdb.companies,moby.companies);
  var fs=first(r.fs_name,r.name,'rom-'+r.id);
  var romfile=(r.has_multiple_files && !/\.zip$/i.test(fs)) ? safe(fs)+'.zip' : safe(fs);
  var basename=safe(first(r.fs_name_no_ext,title,'rom-'+r.id));
  // Prefer RomM-managed resource paths over provider URLs. Provider URLs are
  // useful fallbacks when an asset has not been cached by RomM yet.
  var bezel=first(ss.bezel_path,ss.bezel_url);
  var box2d=first(ss.box2d_path,ss.box2d_url,r.path_cover_small,r.path_cover_large,gl.box2d_url);
  var box2dBack=first(ss.box2d_back_path,ss.box2d_back_url,gl.box2d_back_url);
  var box2dSide=first(ss.box2d_side_path,ss.box2d_side_url);
  var box3d=first(ss.box3d_path,ss.box3d_url,gl.box3d_path,gl.box3d_url);
  var miximage=first(ss.miximage_path,ss.miximage_url,gl.miximage_path,gl.miximage_url);
  var miximageV2=first(ss.miximage_v2_path,ss.miximage_v2_url);
  var physical=first(ss.physical_path,ss.physical_url,gl.physical_path,gl.physical_url);
  var screenshot=first(r.screenshot_path,ss.screenshot_path,ss.screenshot_url,gl.screenshot_url,gl.image_url);
  var titleScreen=first(ss.title_screen_path,ss.title_screen_url,gl.title_screen_url);
  var marquee=first(ss.marquee_path,ss.marquee_url,gl.marquee_path,gl.marquee_url);
  var logo=first(ss.logo_path,ss.logo_url);
  var fanart=first(ss.fanart_path,ss.fanart_url,gl.fanart_url);
  var video=first(ss.video_path,ss.video_url,gl.video_path,gl.video_url,r.path_video);
  var videoNormalized=first(ss.video_normalized_path,ss.video_normalized_url);
  var manual=first(r.path_manual,r.url_manual,ss.manual_path,ss.manual_url,gl.manual_url);
  var fields = [
    r.id, systemFolder(r), title, first(r.summary),
    first(meta.genres,ss.genres,igdb.genres,moby.genres,lb.genres),
    first(lb.developers,companies), first(lb.publishers,companies),
    first(meta.player_count,ss.player_count,igdb.player_count),
    esDate(first(meta.first_release_date,ss.first_release_date,igdb.first_release_date)),
    rating(first(meta.average_rating,ss.ss_score,igdb.total_rating,igdb.aggregated_rating)),
    romfile, basename, fs,
    resource(base,bezel), resource(base,box2d), resource(base,box2dBack),
    resource(base,box2dSide), resource(base,box3d), resource(base,miximage),
    resource(base,miximageV2), resource(base,physical), resource(base,screenshot),
    resource(base,titleScreen), resource(base,marquee), resource(base,logo),
    resource(base,fanart), resource(base,video), resource(base,videoNormalized),
    resource(base,manual),
    // Elementerial core slots: best available artwork for each theme feature.
    resource(base,first(miximageV2,miximage,screenshot,r.path_cover_large,box2d,box3d)),
    resource(base,first(box2d,r.path_cover_small,r.path_cover_large,screenshot)),
    resource(base,first(marquee,logo)),
    resource(base,first(videoNormalized,video,r.path_video))
  ];
  return fields.map(b64).join('\t');
}
function run(argv) {
  var mode=argv[0];
  if (mode === 'token') {
    var t=JSON.parse(text(argv[1])).access_token;
    if (!t) throw Error('access_token fehlt');
    return t;
  }
  if (mode === 'page') {
    var data=JSON.parse(text(argv[1]));
    var items=data.items || data.results || [];
    var out=['META\t'+String(data.total == null ? items.length : data.total)+'\t'+String(items.length)];
    items.forEach(function(r){ out.push('ROM\t'+record(r,argv[2])); });
    write(argv[3],out.join('\n')+'\n');
    return '';
  }
  if (mode === 'collections') {
    var collections=JSON.parse(text(argv[1]));
    if (!Array.isArray(collections)) collections=collections.items || collections.results || [];
    var ids=[], seen={};
    argv.slice(3).forEach(function(requested) {
      var key=String(requested).toLocaleLowerCase();
      var matches=collections.filter(function(c){ return String(c.name || '').toLocaleLowerCase() === key; });
      if (!matches.length) throw Error('Collection nicht gefunden: ' + requested);
      if (matches.length > 1) throw Error('Collection-Name ist mehrdeutig: ' + requested);
      var id=String(matches[0].id);
      if (!seen[id]) { ids.push(id); seen[id]=true; }
    });
    write(argv[2],ids.join('\n')+(ids.length?'\n':''));
    return '';
  }
  throw Error('Unbekannter Modus: '+mode);
}
JXA

b64decode() {
  if printf '' | base64 -D >/dev/null 2>&1; then base64 -D
  else base64 --decode
  fi
}
dec() {
  [ "$1" = - ] && return 0
  printf '%s' "$1" | b64decode
}
xml_escape() {
  LC_ALL=C sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\\&apos;/g"
}
xml_field() {
  [ -n "$2" ] || return 0
  printf '    <%s>' "$1"
  printf '%s' "$2" | xml_escape
  printf '</%s>\n' "$1"
}
ext_from_url() {
  local u path name ext default_ext
  u=$1; default_ext=$2; path=${u%%\?*}; name=${path##*/}
  case "$name" in
    *.*)
      ext=.${name##*.}
      case "$ext" in
        .php|.cgi|.asp|.aspx|.jsp|.do|.action|.????????*|.*[!A-Za-z0-9]*) ext=$default_ext ;;
      esac
      ;;
    *) ext=$default_ext ;;
  esac
  printf '%s' "$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"
}
download() {
  local url=$1 dest=$2 tmp
  if [ "$DRY_RUN" -eq 1 ]; then log "[dry-run] download $url -> $dest"; return 0; fi
  mkdir -p "$(dirname "$dest")" || return 1
  if [ -s "$dest" ]; then return 0; fi
  tmp="$dest.part"
  case "$url" in
    "$ROMM"/*)
      if curl --fail --location --silent --show-error --connect-timeout 30 --max-time 600 \
          -H "Authorization: Bearer $TOKEN" -o "$tmp" "$url"; then
        mv "$tmp" "$dest"; return 0
      fi
      ;;
    http://*|https://*)
      # Never disclose the RomM bearer token to external metadata providers.
      if curl --fail --location --silent --show-error --connect-timeout 30 --max-time 600 \
          -o "$tmp" "$url"; then
        mv "$tmp" "$dest"; return 0
      fi
      ;;
    *)
      log "WARN: Ungueltige Download-URL: $url"
      ;;
  esac
  rm -f "$tmp"; return 1
}

LOGIN_JSON="$TMPDIR_EXPORT/login.json"
LOGIN_SCOPE='roms.read assets.read'
[ "$COLLECTION_NAME_COUNT" -eq 0 ] && [ "$COLLECTION_ID_COUNT" -eq 0 ] || LOGIN_SCOPE="$LOGIN_SCOPE collections.read"
LOGIN_CODE=$(curl --silent --show-error --output "$LOGIN_JSON" --write-out '%{http_code}' \
  --connect-timeout 30 --max-time 60 --request POST "$ROMM/api/token" \
  --data-urlencode 'grant_type=password' \
  --data-urlencode "scope=$LOGIN_SCOPE" \
  --data-urlencode "username=$USERNAME" \
  --data-urlencode "password=$PASSWORD") || fail "Login-Anfrage fehlgeschlagen"
case "$LOGIN_CODE" in 2??) ;; *) fail "Login fehlgeschlagen: HTTP $LOGIN_CODE: $(LC_ALL=C cut -c 1-700 "$LOGIN_JSON")" ;; esac
TOKEN=$(osascript -l JavaScript "$JS_HELPER" token "$LOGIN_JSON" 2>&1) || fail "Login-Antwort ungueltig: $TOKEN"

log "Login bei RomM erfolgreich."
MANIFEST="$TMPDIR_EXPORT/manifest.tsv"
: > "$MANIFEST"
limit=100

load_source() {
  source_query=$1; source_label=$2; source_number=$3
  offset=0; total=0
  while :; do
    PAGE_JSON="$TMPDIR_EXPORT/page-$source_number-$offset.json"
    PAGE_TSV="$TMPDIR_EXPORT/page-$source_number-$offset.tsv"
    API_URL="$ROMM/api/roms?$source_query&with_files=true&with_char_index=false&with_filter_values=false&with_rom_id_index=false&limit=$limit&offset=$offset&order_by=name&order_dir=asc"
    CODE=$(curl --silent --show-error --output "$PAGE_JSON" --write-out '%{http_code}' \
      --connect-timeout 30 --max-time 120 -H "Authorization: Bearer $TOKEN" "$API_URL") || fail "$source_label konnte nicht geladen werden"
    case "$CODE" in 2??) ;; *) fail "$source_label abrufen fehlgeschlagen: HTTP $CODE: $(LC_ALL=C cut -c 1-700 "$PAGE_JSON")" ;; esac
    osascript -l JavaScript "$JS_HELPER" page "$PAGE_JSON" "$ROMM" "$PAGE_TSV" >/dev/null || fail "$source_label-Antwort ist ungueltig"
    meta=$(LC_ALL=C sed -n '1p' "$PAGE_TSV")
    oldIFS=$IFS; IFS="$(printf '\t')"; set -- $meta; IFS=$oldIFS
    total=$2; page_count=$3
    LC_ALL=C sed '1d' "$PAGE_TSV" >> "$MANIFEST"
    offset=$((offset + page_count))
    log "$source_label geladen: $offset/$total"
    [ "$page_count" -gt 0 ] || break
    [ "$offset" -lt "$total" ] || break
  done
}

if [ "$COLLECTION_NAME_COUNT" -gt 0 ] || [ "$COLLECTION_ID_COUNT" -gt 0 ]; then
  COLLECTION_ID_FILE="$TMPDIR_EXPORT/collection-ids.txt"
  : > "$COLLECTION_ID_FILE"
  if [ "$COLLECTION_ID_COUNT" -gt 0 ]; then
    for collection_id in "${COLLECTION_IDS[@]}"; do
      COLLECTION_JSON="$TMPDIR_EXPORT/collection-$collection_id.json"
      CODE=$(curl --silent --show-error --output "$COLLECTION_JSON" --write-out '%{http_code}' \
        --connect-timeout 30 --max-time 120 -H "Authorization: Bearer $TOKEN" "$ROMM/api/collections/$collection_id") || fail "Collection-ID $collection_id konnte nicht validiert werden"
      case "$CODE" in 2??) ;; *) fail "Collection-ID $collection_id ist ungueltig: HTTP $CODE: $(LC_ALL=C cut -c 1-700 "$COLLECTION_JSON")" ;; esac
      printf '%s\n' "$collection_id" >> "$COLLECTION_ID_FILE"
    done
  fi
  if [ "$COLLECTION_NAME_COUNT" -gt 0 ]; then
    log "Lade Collections..."
    COLLECTIONS_JSON="$TMPDIR_EXPORT/collections.json"
    RESOLVED_COLLECTION_IDS="$TMPDIR_EXPORT/resolved-collection-ids.txt"
    CODE=$(curl --silent --show-error --output "$COLLECTIONS_JSON" --write-out '%{http_code}' \
      --connect-timeout 30 --max-time 120 -H "Authorization: Bearer $TOKEN" "$ROMM/api/collections") || fail "Collections konnten nicht geladen werden"
    case "$CODE" in 2??) ;; *) fail "Collections abrufen fehlgeschlagen: HTTP $CODE: $(LC_ALL=C cut -c 1-700 "$COLLECTIONS_JSON")" ;; esac
    osascript -l JavaScript "$JS_HELPER" collections "$COLLECTIONS_JSON" "$RESOLVED_COLLECTION_IDS" "${COLLECTION_NAMES[@]}" >/dev/null || fail "Collections konnten nicht aufgeloest werden"
    LC_ALL=C sed -n 'p' "$RESOLVED_COLLECTION_IDS" >> "$COLLECTION_ID_FILE"
  fi
  COLLECTION_ID_FILE_UNIQUE="$TMPDIR_EXPORT/collection-ids-unique.txt"
  LC_ALL=C awk '!seen[$0]++' "$COLLECTION_ID_FILE" > "$COLLECTION_ID_FILE_UNIQUE"
  source_number=0
  while IFS= read -r collection_id; do
    [ -n "$collection_id" ] || continue
    source_number=$((source_number + 1))
    load_source "collection_id=$collection_id" "Collection $collection_id" "$source_number"
  done < "$COLLECTION_ID_FILE_UNIQUE"
else
  log "Lade Favorites..."
  load_source 'favorite=true' Favorites 0
fi

# Eine ROM kann in mehreren gewaehlten Collections enthalten sein.
MANIFEST_UNIQUE="$TMPDIR_EXPORT/manifest-unique.tsv"
LC_ALL=C awk -F "$(printf '\t')" '!seen[$2]++' "$MANIFEST" > "$MANIFEST_UNIQUE"
mv "$MANIFEST_UNIQUE" "$MANIFEST"
offset=$(LC_ALL=C sed -n '$=' "$MANIFEST")
offset=${offset:-0}
log "Gefunden: $offset eindeutige Spiele"

if [ "$DOWNLOAD_ROMS" -eq 0 ] && [ "$DOWNLOAD_MEDIA" -eq 0 ]; then
  log "Hinweis: Ohne --download-roms/--download-media werden nur gamelist.xml-Dateien vorbereitet."
fi

GAMEDIR="$TMPDIR_EXPORT/gamelists"
COUNTDIR="$TMPDIR_EXPORT/counts"
mkdir -p "$GAMEDIR" "$COUNTDIR"
SKIPPED="$TMPDIR_EXPORT/skipped.tsv"
: > "$SKIPPED"
index=0

while IFS="$(printf '\t')" read -r marker f_id f_system f_title f_desc f_genre f_developer f_publisher f_players f_date f_rating f_romfile f_basename f_fsname f_bezel f_box2d f_box2d_back f_box2d_side f_box3d f_miximage f_miximage_v2 f_physical f_screenshot f_title_screen f_marquee_source f_logo f_fanart f_video_source f_video_normalized f_manual f_image f_thumb f_marquee f_video; do
  [ "$marker" = ROM ] || continue
  index=$((index + 1))
  id=$(dec "$f_id"); system=$(dec "$f_system"); title=$(dec "$f_title")
  desc=$(dec "$f_desc"); genre=$(dec "$f_genre"); developer=$(dec "$f_developer")
  publisher=$(dec "$f_publisher"); players=$(dec "$f_players"); releasedate=$(dec "$f_date")
  rating=$(dec "$f_rating"); romfile=$(dec "$f_romfile"); basename=$(dec "$f_basename")
  fsname=$(dec "$f_fsname"); image_url=$(dec "$f_image"); thumb_url=$(dec "$f_thumb")
  marquee_url=$(dec "$f_marquee"); video_url=$(dec "$f_video")
  bezel_url=$(dec "$f_bezel"); box2d_url=$(dec "$f_box2d"); box2d_back_url=$(dec "$f_box2d_back")
  box2d_side_url=$(dec "$f_box2d_side"); box3d_url=$(dec "$f_box3d"); miximage_url=$(dec "$f_miximage")
  miximage_v2_url=$(dec "$f_miximage_v2"); physical_url=$(dec "$f_physical"); screenshot_url=$(dec "$f_screenshot")
  title_screen_url=$(dec "$f_title_screen"); marquee_source_url=$(dec "$f_marquee_source"); logo_url=$(dec "$f_logo")
  fanart_url=$(dec "$f_fanart"); video_source_url=$(dec "$f_video_source"); video_normalized_url=$(dec "$f_video_normalized")
  manual_url=$(dec "$f_manual")
  system_dir="$OUTPUT/$system"
  log "[$index/$offset] $system: $title"

  if [ "$DOWNLOAD_ROMS" -eq 1 ]; then
    encoded_name=$(osascript -l JavaScript -e 'function run(a){return encodeURIComponent(a[0])}' "$fsname")
    if ! download "$ROMM/api/roms/$id/content/$encoded_name" "$system_dir/$romfile"; then
      log "WARN: ROM-Download fehlgeschlagen: $title"
      printf '%s\t%s\trom download failed\n' "$f_id" "$f_title" >> "$SKIPPED"
      continue
    fi
  fi

  local_image=""; local_thumb=""; local_marquee=""; local_video=""
  local_bezel=""; local_box2d=""; local_box2d_back=""; local_box2d_side=""; local_box3d=""
  local_miximage=""; local_miximage_v2=""; local_physical=""; local_screenshot=""; local_title_screen=""
  local_logo=""; local_fanart=""; local_video_source=""; local_video_normalized=""; local_manual=""
  if [ "$DOWNLOAD_MEDIA" -eq 1 ]; then
    fetch_media() {
      media_url=$1; media_dir=$2; media_default_ext=$3; MEDIA_RESULT=""
      [ -n "$media_url" ] || return 0
      media_ext=$(ext_from_url "$media_url" "$media_default_ext")
      media_dest="$system_dir/media/$media_dir/$basename$media_ext"
      if download "$media_url" "$media_dest"; then
        MEDIA_RESULT="./media/$media_dir/$basename$media_ext"
      else
        log "WARN: Medien-Download fehlgeschlagen ($media_dir): $media_url"
      fi
    }

    fetch_media "$bezel_url" bezels .png; local_bezel=$MEDIA_RESULT
    fetch_media "$box2d_url" box2d .png; local_box2d=$MEDIA_RESULT
    fetch_media "$box2d_back_url" box2d-back .png; local_box2d_back=$MEDIA_RESULT
    fetch_media "$box2d_side_url" box2d-side .png; local_box2d_side=$MEDIA_RESULT
    fetch_media "$box3d_url" box3d .png; local_box3d=$MEDIA_RESULT
    fetch_media "$miximage_url" miximages .png; local_miximage=$MEDIA_RESULT
    fetch_media "$miximage_v2_url" miximages-v2 .png; local_miximage_v2=$MEDIA_RESULT
    fetch_media "$physical_url" physical .png; local_physical=$MEDIA_RESULT
    fetch_media "$screenshot_url" screenshots .png; local_screenshot=$MEDIA_RESULT
    fetch_media "$title_screen_url" title-screens .png; local_title_screen=$MEDIA_RESULT
    fetch_media "$marquee_source_url" marquees .png; local_marquee=$MEDIA_RESULT
    fetch_media "$logo_url" logos .png; local_logo=$MEDIA_RESULT
    fetch_media "$fanart_url" fanart .png; local_fanart=$MEDIA_RESULT
    fetch_media "$video_source_url" videos .mp4; local_video_source=$MEDIA_RESULT
    fetch_media "$video_normalized_url" videos-normalized .mp4; local_video_normalized=$MEDIA_RESULT
    fetch_media "$manual_url" manuals .pdf; local_manual=$MEDIA_RESULT

    # Download the selected Elementerial assets only when their source was not
    # already exported to the exact core slot.
    case "$image_url" in
      "$miximage_v2_url") local_image=$local_miximage_v2 ;;
      "$miximage_url") local_image=$local_miximage ;;
      "$screenshot_url") local_image=$local_screenshot ;;
      "$box2d_url") local_image=$local_box2d ;;
      "$box3d_url") local_image=$local_box3d ;;
      *) fetch_media "$image_url" images .png; local_image=$MEDIA_RESULT ;;
    esac
    case "$thumb_url" in
      "$box2d_url") local_thumb=$local_box2d ;;
      "$screenshot_url") local_thumb=$local_screenshot ;;
      *) fetch_media "$thumb_url" thumbnails .png; local_thumb=$MEDIA_RESULT ;;
    esac
    [ -n "$local_marquee" ] || local_marquee=$local_logo
    [ -n "$local_video_normalized" ] && local_video=$local_video_normalized || local_video=$local_video_source
  fi
  [ -n "$local_thumb" ] || local_thumb=$local_image

  gamefile="$GAMEDIR/$system.games"
  {
    printf '  <game>\n'
    xml_field path "./$romfile"
    xml_field name "$title"
    xml_field desc "$desc"
    xml_field image "$local_image"
    xml_field thumbnail "$local_thumb"
    xml_field marquee "$local_marquee"
    xml_field video "$local_video"
    # Extended media fields are ignored safely by older EmulationStation
    # builds, while compatible forks and tools can use them directly.
    xml_field fanart "$local_fanart"
    xml_field manual "$local_manual"
    xml_field boxart "$local_box2d"
    xml_field boxback "$local_box2d_back"
    xml_field cartridge "$local_physical"
    xml_field screenshot "$local_screenshot"
    xml_field titleshot "$local_title_screen"
    xml_field wheel "$local_marquee"
    xml_field mix "${local_miximage_v2:-$local_miximage}"
    xml_field bezel "$local_bezel"
    xml_field rating "$rating"
    xml_field releasedate "$releasedate"
    xml_field developer "$developer"
    xml_field publisher "$publisher"
    xml_field genre "$genre"
    xml_field players "$players"
    printf '  </game>\n'
  } >> "$gamefile"
  count_file="$COUNTDIR/$system"
  count=0; [ ! -f "$count_file" ] || count=$(LC_ALL=C sed -n '1p' "$count_file")
  printf '%s\n' $((count + 1)) > "$count_file"
done < "$MANIFEST"

for gamefile in "$GAMEDIR"/*.games; do
  [ -e "$gamefile" ] || continue
  system=${gamefile##*/}; system=${system%.games}
  count=$(LC_ALL=C sed -n '1p' "$COUNTDIR/$system")
  target="$OUTPUT/$system/gamelist.xml"
  if [ "$DRY_RUN" -eq 1 ]; then
    log "[dry-run] write $target ($count games)"
  else
    mkdir -p "$OUTPUT/$system"
    { printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>' '<gameList>'; LC_ALL=C tr -d '\000-\010\013\014\016-\037' < "$gamefile"; printf '%s\n' '</gameList>'; } > "$target"
  fi
done

log ""
log "Fertig."
log "Output: $OUTPUT"
log "Die Systemordner koennen jetzt auf der EASYROMS-Partition genutzt werden."
