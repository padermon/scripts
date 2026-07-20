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

usage() {
  cat <<'EOF'
Verwendung:
  romm_favorites_r36s_export.sh --romm URL --username USER --output ZIEL [Optionen]

Optionen:
  --romm URL          URL der RomM-Instanz (erforderlich)
  --username USER     RomM Benutzername (erforderlich)
  --password PASS     Passwort; sicherer: ROMM_PASSWORD oder Eingabe-Prompt
  --output PFAD       Zielordner, z.B. ./r36s-export oder /Volumes/EASYROMS
  --download-roms     ROM-Dateien herunterladen
  --download-media    Bilder und Videos herunterladen
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
  var fields = [
    r.id, systemFolder(r), title, first(r.summary),
    first(meta.genres,ss.genres,igdb.genres,moby.genres,lb.genres),
    first(lb.developers,companies), first(lb.publishers,companies),
    first(meta.player_count,ss.player_count,igdb.player_count),
    esDate(first(meta.first_release_date,ss.first_release_date,igdb.first_release_date)),
    rating(first(meta.average_rating,ss.ss_score,igdb.total_rating,igdb.aggregated_rating)),
    romfile, basename, fs,
    resource(base,first(ss.miximage_path,gl.miximage_path,r.path_cover_large,r.path_cover_small)),
    resource(base,first(r.path_cover_small,r.path_cover_large,ss.box2d_path,ss.box3d_path,gl.box3d_path)),
    resource(base,first(ss.marquee_path,gl.marquee_path,ss.logo_path)),
    resource(base,first(r.path_video,ss.video_normalized_path,ss.video_path))
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
    *.*) ext=.${name##*.}; case "$ext" in .????????*|.*[!A-Za-z0-9]*) ext=$default_ext ;; esac ;;
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
  if curl --fail --location --silent --show-error --connect-timeout 30 --max-time 600 \
      -H "Authorization: Bearer $TOKEN" -o "$tmp" "$url"; then
    mv "$tmp" "$dest"; return 0
  fi
  rm -f "$tmp"; return 1
}

LOGIN_JSON="$TMPDIR_EXPORT/login.json"
LOGIN_CODE=$(curl --silent --show-error --output "$LOGIN_JSON" --write-out '%{http_code}' \
  --connect-timeout 30 --max-time 60 --request POST "$ROMM/api/token" \
  --data-urlencode 'grant_type=password' \
  --data-urlencode 'scope=roms.read assets.read' \
  --data-urlencode "username=$USERNAME" \
  --data-urlencode "password=$PASSWORD") || fail "Login-Anfrage fehlgeschlagen"
case "$LOGIN_CODE" in 2??) ;; *) fail "Login fehlgeschlagen: HTTP $LOGIN_CODE: $(LC_ALL=C cut -c 1-700 "$LOGIN_JSON")" ;; esac
TOKEN=$(osascript -l JavaScript "$JS_HELPER" token "$LOGIN_JSON" 2>&1) || fail "Login-Antwort ungueltig: $TOKEN"

log "Login bei RomM erfolgreich."
log "Lade Favorites..."
MANIFEST="$TMPDIR_EXPORT/manifest.tsv"
: > "$MANIFEST"
offset=0
limit=100
total=0
while :; do
  PAGE_JSON="$TMPDIR_EXPORT/page-$offset.json"
  PAGE_TSV="$TMPDIR_EXPORT/page-$offset.tsv"
  API_URL="$ROMM/api/roms?favorite=true&with_files=true&with_char_index=false&with_filter_values=false&with_rom_id_index=false&limit=$limit&offset=$offset&order_by=name&order_dir=asc"
  CODE=$(curl --silent --show-error --output "$PAGE_JSON" --write-out '%{http_code}' \
    --connect-timeout 30 --max-time 120 -H "Authorization: Bearer $TOKEN" "$API_URL") || fail "Favorites konnten nicht geladen werden"
  case "$CODE" in 2??) ;; *) fail "Favorites abrufen fehlgeschlagen: HTTP $CODE: $(LC_ALL=C cut -c 1-700 "$PAGE_JSON")" ;; esac
  osascript -l JavaScript "$JS_HELPER" page "$PAGE_JSON" "$ROMM" "$PAGE_TSV" >/dev/null || fail "Favorites-Antwort ist ungueltig"
  meta=$(LC_ALL=C sed -n '1p' "$PAGE_TSV")
  oldIFS=$IFS; IFS="$(printf '\t')"; set -- $meta; IFS=$oldIFS
  total=$2; page_count=$3
  LC_ALL=C sed '1d' "$PAGE_TSV" >> "$MANIFEST"
  offset=$((offset + page_count))
  log "Favorites geladen: $offset/$total"
  [ "$page_count" -gt 0 ] || break
  [ "$offset" -lt "$total" ] || break
done
log "Gefunden: $offset Favorites"

if [ "$DOWNLOAD_ROMS" -eq 0 ] && [ "$DOWNLOAD_MEDIA" -eq 0 ]; then
  log "Hinweis: Ohne --download-roms/--download-media werden nur gamelist.xml-Dateien vorbereitet."
fi

GAMEDIR="$TMPDIR_EXPORT/gamelists"
COUNTDIR="$TMPDIR_EXPORT/counts"
mkdir -p "$GAMEDIR" "$COUNTDIR"
SKIPPED="$TMPDIR_EXPORT/skipped.tsv"
: > "$SKIPPED"
index=0

while IFS="$(printf '\t')" read -r marker f_id f_system f_title f_desc f_genre f_developer f_publisher f_players f_date f_rating f_romfile f_basename f_fsname f_image f_thumb f_marquee f_video; do
  [ "$marker" = ROM ] || continue
  index=$((index + 1))
  id=$(dec "$f_id"); system=$(dec "$f_system"); title=$(dec "$f_title")
  desc=$(dec "$f_desc"); genre=$(dec "$f_genre"); developer=$(dec "$f_developer")
  publisher=$(dec "$f_publisher"); players=$(dec "$f_players"); releasedate=$(dec "$f_date")
  rating=$(dec "$f_rating"); romfile=$(dec "$f_romfile"); basename=$(dec "$f_basename")
  fsname=$(dec "$f_fsname"); image_url=$(dec "$f_image"); thumb_url=$(dec "$f_thumb")
  marquee_url=$(dec "$f_marquee"); video_url=$(dec "$f_video")
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
  if [ "$DOWNLOAD_MEDIA" -eq 1 ]; then
    if [ -n "$image_url" ]; then
      ext=$(ext_from_url "$image_url" .png); dest="$system_dir/media/images/$basename$ext"
      download "$image_url" "$dest" && local_image="./media/images/$basename$ext" || log "WARN: Bild-Download fehlgeschlagen: $image_url"
    fi
    if [ -n "$thumb_url" ]; then
      ext=$(ext_from_url "$thumb_url" .png); dest="$system_dir/media/images/$basename$ext"
      download "$thumb_url" "$dest" && local_thumb="./media/images/$basename$ext" || log "WARN: Thumbnail-Download fehlgeschlagen: $thumb_url"
    fi
    if [ -n "$marquee_url" ]; then
      ext=$(ext_from_url "$marquee_url" .png); dest="$system_dir/media/marquees/$basename$ext"
      download "$marquee_url" "$dest" && local_marquee="./media/marquees/$basename$ext" || log "WARN: Marquee-Download fehlgeschlagen: $marquee_url"
    fi
    if [ -n "$video_url" ]; then
      ext=$(ext_from_url "$video_url" .mp4); dest="$system_dir/media/videos/$basename$ext"
      download "$video_url" "$dest" && local_video="./media/videos/$basename$ext" || log "WARN: Video-Download fehlgeschlagen: $video_url"
    fi
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
    xml_field rating "$rating"
    xml_field releasedate "$releasedate"
    xml_field developer "$developer"
    xml_field publisher "$publisher"
    xml_field genre "$genre"
    xml_field players "$players"
    xml_field favorite true
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
    { printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>' '<gameList>'; LC_ALL=C sed 's/[^[:print:]\t]//g' "$gamefile"; printf '%s\n' '</gameList>'; } > "$target"
  fi
done

log ""
log "Fertig."
log "Output: $OUTPUT"
log "Die Systemordner koennen jetzt auf der EASYROMS-Partition genutzt werden."
