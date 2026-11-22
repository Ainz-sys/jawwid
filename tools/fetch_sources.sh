#!/usr/bin/env bash
# Downloads the official sources that tools/build_data.py turns into the app's data files.
# Runs on GitHub (workflow "Fetch source data"); the results are published on the "rawdata" branch.
set -u
OUT="${1:-raw}"
mkdir -p "$OUT/quran-align"
cd "$OUT"

log() { echo "$@" | tee -a fetch.log; }
get() { # url file
  if curl -fsSL --retry 3 --retry-delay 5 -o "$2" "$1"; then
    log "OK   $2  $(wc -c < "$2") bytes  sha256 $(sha256sum "$2" | cut -c1-16)"
  else
    log "FAIL $2  <- $1"
    rm -f "$2"
  fi
}

# 1. Word timings — quran-align official release (CC BY 4.0)
get "https://github.com/cpfair/quran-align/releases/download/release-2016-11-24/quran-align-data-2016-11-24.zip" qa.zip
if [ -f qa.zip ]; then
  unzip -o -q qa.zip -d qa
  find qa -type f | sort | tee -a fetch.log
  for f in Minshawy_Murattal_128kbps Minshawy_Mujawwad_192kbps; do
    src=$(find qa -type f -name "$f.json" | head -1)
    if [ -n "$src" ]; then cp "$src" "quran-align/$f.json"; log "copied $f.json"; else log "MISSING $f.json"; fi
  done
  rm -rf qa qa.zip
fi

# 2. Tanzil Uthmani text, version 1.1 (verbatim; CC BY 3.0 — see tanzil.net/download)
T="https://tanzil.net/pub/download/index.php"
get "$T?marks=true&sajdah=true&quranType=uthmani&outType=txt-2&agree=true" tanzil-uthmani-marks.txt
get "$T?quranType=uthmani&outType=txt-2&agree=true" tanzil-uthmani-plain.txt
get "$T?marks=true&sajdah=true&quranType=uthmani&outType=xml&agree=true" tanzil-uthmani.xml
get "https://tanzil.net/download/" tanzil-download-page.html
get "https://tanzil.net/res/text/metadata/quran-data.js" tanzil-quran-data.js

# 3. The Tanzil text (2017) that the quran-tajweed annotations were made for
get "https://github.com/cpfair/quran-tajweed/files/7281388/quran-uthmani.txt" tajweed-2017-quran-uthmani.txt

# 4. Do the audio addresses the app uses answer?
for u in \
  "https://everyayah.com/data/Minshawy_Murattal_128kbps/001001.mp3" \
  "https://everyayah.com/data/Minshawy_Murattal_128kbps/078014.mp3" \
  "https://everyayah.com/data/Minshawy_Mujawwad_192kbps/078014.mp3" \
  "https://cdn.mp3quran.net/audio/muhammad-minshawi/r3/001.mp3" \
  "https://cdn.mp3quran.net/audio/muhammad-minshawi/r3/078.mp3"; do
  code=$(curl -sSL -o /dev/null -r 0-1023 -w '%{http_code} %{content_type}' "$u" || echo "error")
  log "AUDIO $code  $u"
done
get "https://everyayah.com/data/Minshawy_Murattal_128kbps/078014.mp3" sample-murattal-078014.mp3
get "https://everyayah.com/data/Minshawy_Mujawwad_192kbps/078014.mp3" sample-mujawwad-078014.mp3

log "done"
