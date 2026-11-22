#!/usr/bin/env python3
"""Builds the data files bundled with جوِّد (App/Resources/Data) from the official sources.

Usage:
  git clone --depth 1 -b rawdata https://github.com/Ainz-sys/jawwid raw   # made by the "Fetch source data" workflow
  python3 tools/build_data.py --raw raw

Sources (see CREDITS.md):
  * Quran text: Tanzil Uthmani text 1.1, verbatim. The ayah text and the basmala of each surah come from Tanzil's XML
    (where the basmala is a separate attribute), cross-checked letter for letter against Tanzil's text file.
  * Surah names, ayah counts, juz starts: quran-meta (MIT), cross-checked against Tanzil's metadata.
  * Word timings: quran-align (CC BY 4.0) for Minshawy Murattal and Mujawwad (EveryAyah recordings).
"""
import argparse, hashlib, json, os, re, sys, unicodedata
import xml.etree.ElementTree as ET

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'App', 'Resources', 'Data')
META = os.path.join(ROOT, 'tools', 'data', 'quran-meta-hafs.json')

# Pause marks, rub el hizb and sajdah sign: shown in the text but not words (they are never recited).
MARKS = {0x06D6, 0x06D7, 0x06D8, 0x06D9, 0x06DA, 0x06DB, 0x06DC, 0x06DE, 0x06E9}
# Common modern spelling of two surah names (quran-meta follows the mushaf headings سبإ، النبإ).
NAME_OVERRIDES = {34: 'سبأ', 78: 'النبأ'}
RECITERS = {
    'murattal': 'Minshawy_Murattal_128kbps',
    'mujawwad': 'Minshawy_Mujawwad_192kbps',
}


def fail(msg):
    print('ERROR:', msg)
    sys.exit(1)


def is_mark_token(tok):
    return len(tok) > 0 and all(ord(c) in MARKS for c in tok)


def words_of(t):
    return [tok for tok in t.split(' ') if tok and not is_mark_token(tok)]


def read_txt(path):
    """Tanzil "Text (with aya numbers)": `sura|aya|text`; the copyright block lines start with '#'."""
    text, notice = {}, []
    with open(path, encoding='utf-8-sig') as f:
        for line in f:
            line = line.rstrip('\r\n')
            if not line.strip():
                continue
            if line.startswith('#'):
                notice.append(line[1:].rstrip())
                continue
            s, a, t = line.split('|', 2)
            text[(int(s), int(a))] = t
    # keep the notice as printed, without the frame lines of '=' and the leading/trailing blank lines
    notice = [n.strip() for n in notice]
    notice = [n for n in notice if n and not set(n) <= {'='}]
    return text, notice


def read_xml(path):
    text, bismillah = {}, {}
    root = ET.parse(path).getroot()
    for sura in root.iter('sura'):
        s = int(sura.get('index'))
        for aya in sura.iter('aya'):
            a = int(aya.get('index'))
            text[(s, a)] = aya.get('text')
            if aya.get('bismillah'):
                bismillah[s] = aya.get('bismillah')
    return text, bismillah


def read_tanzil_meta(path):
    src = open(path, encoding='utf-8').read()
    def block(name):
        m = re.search(r'QuranData\.' + name + r'\s*=\s*\[(.*?)\];', src, re.S)
        return m.group(1) if m else ''
    suras = re.findall(r"\[\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*'([^']*)'", block('Sura'))
    juz = re.findall(r'\[\s*(\d+),\s*(\d+)\s*\]', block('Juz'))
    # the juz list ends with a [115, 1] end marker
    return [(int(a), int(b), n) for a, b, _, _, n in suras], [(int(s), int(a)) for s, a in juz if int(s) <= 114]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--raw', required=True, help='rawdata directory from the "Fetch source data" workflow')
    args = ap.parse_args()
    raw = args.raw

    meta = json.load(open(META, encoding='utf-8'))
    xml_text, bismillah = read_xml(os.path.join(raw, 'tanzil-uthmani.xml'))
    txt_text, notice = read_txt(os.path.join(raw, 'tanzil-uthmani-marks.txt'))
    if not any('Version 1.1' in n for n in notice):
        fail('expected Tanzil text version 1.1')
    if len(xml_text) != 6236 or len(txt_text) != 6236:
        fail(f'expected 6236 ayat, got xml {len(xml_text)} txt {len(txt_text)}')

    # ---- XML and text file agree letter for letter (the text file prefixes ayah 1 with the basmala)
    for key, t in txt_text.items():
        s, a = key
        expected = xml_text[key]
        if a == 1 and s in bismillah:
            expected = bismillah[s] + ' ' + expected
        if t != expected:
            fail(f'{s}:{a} differs between Tanzil XML and text file')
    if set(bismillah) != set(range(2, 115)) - {9}:
        fail(f'unexpected basmala set: {sorted(set(range(1, 115)) - set(bismillah))} without one')

    # ---- structure: quran-meta, cross-checked with Tanzil's own metadata
    tz_suras, tz_juz = read_tanzil_meta(os.path.join(raw, 'tanzil-quran-data.js'))
    if len(tz_suras) != 114 or len(tz_juz) != 30:
        fail('could not read Tanzil metadata')
    surahs, ordered, g = [], [], 0
    for i, row in enumerate(meta['surah'], start=1):
        start, count, _order, _rukus, _name_tashkeel, meccan = row
        if start != g + 1 or tz_suras[i - 1][0] != g or tz_suras[i - 1][1] != count:
            fail(f'surah {i}: structure differs between quran-meta and Tanzil')
        for a in range(1, count + 1):
            if (i, a) not in xml_text:
                fail(f'missing ayah {i}:{a}')
            ordered.append(xml_text[(i, a)])
        g += count
        surahs.append({'name': NAME_OVERRIDES.get(i, meta['names'][i - 1]), 'ayahs': count, 'meccan': bool(meccan)})
    first = []
    acc = 0
    for s in surahs:
        first.append(acc)
        acc += s['ayahs']
    juz = [x - 1 for x in meta['juz'][1:31]]
    tz_juz_global = [first[s - 1] + a - 1 for s, a in tz_juz]
    if juz != tz_juz_global:
        fail('juz starts differ between quran-meta and Tanzil')
    names_diff = [(i + 1, surahs[i]['name'], tz_suras[i][2]) for i in range(114) if surahs[i]['name'] != tz_suras[i][2]]
    print('surah names that differ from Tanzil metadata (spelling only):', names_diff)

    # ---- characters
    allowed = {'Lo', 'Mn', 'Lm', 'Zs', 'So', 'Cf', 'Me'}
    for idx, t in enumerate(ordered + list(bismillah.values())):
        if '  ' in t or t != t.strip():
            fail(f'whitespace problem at {idx}')
        for c in t:
            if unicodedata.category(c) not in allowed:
                fail(f'unexpected character U+{ord(c):04X} at {idx}')

    default_b = bismillah[2]
    if default_b != xml_text[(1, 1)]:
        fail('the basmala of al-Baqarah should match al-Fatiha 1')
    variants = {str(s): b for s, b in bismillah.items() if b != default_b}
    print('basmala variants:', variants)

    quran = {
        'source': 'Tanzil Quran Text (Uthmani, Version 1.1) — https://tanzil.net',
        'notice': notice,
        'meta': 'Surah names, ayah counts and juz starts: quran-meta (MIT) — https://github.com/quran-center/quran-meta',
        'surahs': surahs,
        'juz': juz,
        'bismillah': dict({'default': default_b}, **variants),
        'text': ordered,
    }
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, 'quran.json'), 'w', encoding='utf-8') as f:
        json.dump(quran, f, ensure_ascii=False, separators=(',', ':'))
    print('quran.json:', len(ordered), 'ayat,', sum(len(words_of(t)) for t in ordered), 'words,',
          sum(1 for t in ordered for tok in t.split(' ') if is_mark_token(tok)), 'mark tokens')

    # ---- word timings (indices count the words of the ayah without the basmala and without marks)
    for key, folder in RECITERS.items():
        data = json.load(open(os.path.join(raw, 'quran-align', folder + '.json'), encoding='utf-8'))
        ayat = [[] for _ in range(6236)]
        dropped = 0
        seen = set()
        covered = total = 0
        for entry in data:
            s, a = entry['surah'], entry['ayah']
            gi = first[s - 1] + a - 1
            seen.add(gi)
            n = len(words_of(ordered[gi]))
            total += n
            flat, last_end, cov = [], -1, set()
            for seg in entry.get('segments', []):
                ws, we, t0, t1 = (int(x) for x in seg[:4])
                if not (0 <= ws < we <= n) or t1 < t0 or t0 < last_end:
                    dropped += 1
                    continue
                last_end = t1
                cov.update(range(ws, we))
                flat += [ws, we, t0, t1]
            covered += len(cov)
            ayat[gi] = flat
        out = {'reciter': folder, 'source': 'quran-align (CC BY 4.0) — https://github.com/cpfair/quran-align', 'ayat': ayat}
        with open(os.path.join(OUT, f'timings-{key}.json'), 'w', encoding='utf-8') as f:
            json.dump(out, f, separators=(',', ':'))
        print(f'timings-{key}.json: {len(seen)} ayat, {sum(1 for x in ayat if not x)} without timings, '
              f'{dropped} segments dropped, words covered {covered / total:.2%}')

    for name in sorted(os.listdir(OUT)):
        p = os.path.join(OUT, name)
        print(f'  {name}: {os.path.getsize(p) / 1e6:.2f} MB  sha256 {hashlib.sha256(open(p, "rb").read()).hexdigest()[:16]}')


if __name__ == '__main__':
    main()
