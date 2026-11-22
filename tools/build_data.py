#!/usr/bin/env python3
"""Builds the data files bundled with جوِّد (App/Resources/Data) from verified sources.

Usage:
  python3 tools/build_data.py --raw <rawdata dir>            # official sources fetched by the "Fetch source data" workflow
  python3 tools/build_data.py --provisional <tanzil txt-2>   # a Tanzil "Text (with aya numbers)" file, no timings

Sources (see CREDITS.md):
  * Quran text: Tanzil Uthmani text, copied verbatim (never edited here; only split into lines).
  * Surah names, ayah counts, juz starts: quran-meta (MIT), cross-checked against the Tanzil text.
  * Word timings: quran-align (CC BY 4.0) for Minshawy Murattal and Mujawwad (EveryAyah recordings).
"""
import argparse, json, os, re, sys, unicodedata, hashlib, xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'App', 'Resources', 'Data')
META = os.path.join(ROOT, 'tools', 'data', 'quran-meta-hafs.json')

# Pause marks, rub el hizb and sajdah sign: shown in the text, but not words (they are never recited).
MARKS = {0x06D6, 0x06D7, 0x06D8, 0x06D9, 0x06DA, 0x06DB, 0x06DC, 0x06DE, 0x06E9}
# Common modern spelling of two surah names (quran-meta follows the mushaf headings: سبإ، النبإ).
NAME_OVERRIDES = {34: 'سبأ', 78: 'النبأ'}
RECITERS = {
    'murattal': 'Minshawy_Murattal_128kbps',
    'mujawwad': 'Minshawy_Mujawwad_192kbps',
}


def fail(msg):
    print('ERROR:', msg)
    sys.exit(1)


def read_tanzil_txt(path, strip_letters=False):
    """Reads Tanzil "Text (with aya numbers)": `sura|aya|text`, notice lines start with '#'."""
    text, notice = {}, []
    with open(path, encoding='utf-8-sig') as f:
        for line in f:
            line = line.rstrip('\r\n')
            if not line.strip():
                continue
            if line.startswith('#'):
                notice.append(line.lstrip('#').strip())
                continue
            s, a, t = line.split('|', 2)
            if strip_letters:  # provisional source embeds rule letters a-z in the text
                t = re.sub(r'[a-z]', '', t)
            key = (int(s), int(a))
            if key in text:
                fail(f'duplicate ayah {key}')
            text[key] = t
    return text, [n for n in notice if n]


def is_mark_token(tok):
    return len(tok) > 0 and all(ord(c) in MARKS for c in tok)


def words_of(t):
    return [tok for tok in t.split(' ') if tok and not is_mark_token(tok)]


def read_bismillah(xml_path):
    out = {}
    root = ET.parse(xml_path).getroot()
    for sura in root.iter('sura'):
        n = int(sura.get('index'))
        aya1 = sura.find('aya')
        b = aya1.get('bismillah') if aya1 is not None else None
        if b:
            out[n] = b
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--raw', help='rawdata directory from the "Fetch source data" workflow')
    ap.add_argument('--provisional', help='Tanzil txt-2 file to use without timings')
    ap.add_argument('--strip-letters', action='store_true', help='remove embedded a-z rule letters (provisional source only)')
    args = ap.parse_args()

    meta = json.load(open(META, encoding='utf-8'))
    if len(meta['surah']) != 114 or len(meta['names']) != 114:
        fail('meta must list 114 surahs')

    xml_path = None
    align = {}
    if args.raw:
        txt = os.path.join(args.raw, 'tanzil-uthmani-marks.txt')
        xml_path = os.path.join(args.raw, 'tanzil-uthmani.xml')
        for key, folder in RECITERS.items():
            p = os.path.join(args.raw, 'quran-align', folder + '.json')
            if os.path.exists(p):
                align[key] = p
            else:
                fail(f'missing timing file {p}')
        text, notice = read_tanzil_txt(txt)
        source = 'Tanzil Quran Text (Uthmani, Version 1.1) — tanzil.net'
    elif args.provisional:
        text, notice = read_tanzil_txt(args.provisional, args.strip_letters)
        source = 'Tanzil Quran Text (Uthmani) — tanzil.net — provisional copy'
    else:
        fail('pass --raw or --provisional')

    # ---- structure checks against quran-meta
    if len(text) != 6236:
        fail(f'expected 6236 ayat, got {len(text)}')
    surahs, ordered, g = [], [], 0
    for i, row in enumerate(meta['surah'], start=1):
        start, count, _order, _rukus, _name_tashkeel, meccan = row
        if start != g + 1:
            fail(f'surah {i}: start {start} != {g + 1}')
        for a in range(1, count + 1):
            if (i, a) not in text:
                fail(f'missing ayah {i}:{a}')
            ordered.append(text[(i, a)])
        if (i, count + 1) in text:
            fail(f'surah {i} has more than {count} ayat')
        g += count
        surahs.append({'name': NAME_OVERRIDES.get(i, meta['names'][i - 1]), 'ayahs': count, 'meccan': bool(meccan)})
    juz = [x - 1 for x in meta['juz'][1:31]]  # 0-based global index of each juz start
    if len(juz) != 30 or juz[0] != 0:
        fail('bad juz list')

    # ---- text sanity: no stray characters, no double spaces
    allowed_cats = {'Lo', 'Mn', 'Lm', 'Zs', 'So', 'Cf', 'Me'}
    for idx, t in enumerate(ordered):
        if '  ' in t or t != t.strip():
            fail(f'whitespace problem at global {idx}')
        for c in t:
            if unicodedata.category(c) not in allowed_cats:
                fail(f'unexpected character U+{ord(c):04X} ({unicodedata.name(c, "?")}) at global {idx}')

    bismillah = {'default': text[(1, 1)]}
    if xml_path and os.path.exists(xml_path):
        bis = read_bismillah(xml_path)
        for n, b in bis.items():
            if b != bismillah['default']:
                bismillah[str(n)] = b
        print('bismillah variants:', {k: v for k, v in bismillah.items() if k != 'default'})

    quran = {
        'source': source,
        'notice': notice,
        'meta': 'Surah names, ayah counts and juz starts: quran-meta (MIT) — github.com/quran-center/quran-meta',
        'surahs': surahs,
        'juz': juz,
        'bismillah': bismillah,
        'text': ordered,
    }
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, 'quran.json'), 'w', encoding='utf-8') as f:
        json.dump(quran, f, ensure_ascii=False, separators=(',', ':'))
    print('quran.json:', len(ordered), 'ayat,', sum(len(words_of(t)) for t in ordered), 'words,',
          sum(1 for t in ordered for tok in t.split(' ') if is_mark_token(tok)), 'mark tokens')

    # ---- word timings
    starts = []
    g = 0
    for s in surahs:
        starts.append(g)
        g += s['ayahs']
    for key, path in align.items():
        data = json.load(open(path, encoding='utf-8'))
        ayat = [[] for _ in range(6236)]
        problems = 0
        seen = set()
        for entry in data:
            s, a = entry['surah'], entry['ayah']
            gi = starts[s - 1] + a - 1
            seen.add(gi)
            n = len(words_of(ordered[gi]))
            flat = []
            last_end = -1
            for seg in entry['segments']:
                ws, we, t0, t1 = (int(x) for x in seg[:4])
                if not (0 <= ws < we <= n) or t1 < t0:
                    problems += 1
                    continue
                if t0 < last_end:  # keep segments in time order
                    problems += 1
                    continue
                last_end = t1
                flat += [ws, we, t0, t1]
            ayat[gi] = flat
        missing = 6236 - len(seen)
        out = {'reciter': RECITERS[key],
               'source': 'quran-align (CC BY 4.0) — github.com/cpfair/quran-align',
               'ayat': ayat}
        with open(os.path.join(OUT, f'timings-{key}.json'), 'w', encoding='utf-8') as f:
            json.dump(out, f, separators=(',', ':'))
        print(f'timings-{key}.json: {len(seen)} ayat, {missing} missing, {problems} dropped segments')

    for name in sorted(os.listdir(OUT)):
        p = os.path.join(OUT, name)
        print(f'  {name}: {os.path.getsize(p) / 1e6:.2f} MB sha256 {hashlib.sha256(open(p, "rb").read()).hexdigest()[:16]}')


if __name__ == '__main__':
    main()
