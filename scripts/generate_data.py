#!/usr/bin/env python3
"""
Generate per-language, per-category PO files from Unicode emoji-list.txt + CLDR.

Usage:
  python3 scripts/generate_emoji_po.py [lang ...]
  Defaults to: en ja

Fetches: Unicode emoji-test.txt (EMOJI_LIST_URL)
Fetches: CLDR annotation XML for each requested language
Writes: picker/data/locale/{lang}/categories.po
        picker/data/locale/{lang}/{category_id}.po
        picker/data/locale/{lang}/kaomoji.po  (msgstr empty; restore backup for real content)
"""

import glob
import io
import json
import os
import re
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCALE_DIR = os.path.join(ROOT, "picker", "data", "locale")

EMOJI_VERSION = "latest"
EMOJI_LIST_URL = f"https://unicode.org/Public/emoji/{EMOJI_VERSION}/emoji-test.txt"

CLDR_VERSION = "48.2"
CLDR_ZIP_URL = f"https://unicode.org/Public/cldr/{CLDR_VERSION}/cldr-common-{CLDR_VERSION}.zip"

CATEGORY_IDS = [
    "smileys", "people", "animals", "food",
    "travel", "activities", "objects", "symbols", "flags",
]

SKIP_GROUPS = {"Component"}

SUPPORTED_LANGS = ["en", "ja"]

KAOMOJI = [
    "(^▽^)",
    "ヽ(^o^)丿",
    "\\(≧▽≦)/",
    "(＾▽＾)",
    "(ﾉ´∀｀)ﾉ",
    "(*´▽`*)",
    "ヾ(*´∀`*)ﾉ",
    "(o^▽^o)",
    "(T_T)",
    "(;_;)",
    "(っ◞‸◟c)",
    "( ; ω ; )",
    "(´；ω；`)",
    "ヽ(;▽;)ノ",
    "(╯°□°）╯︵ ┻━┻",
    "┻━┻ ︵ヽ(`Д´)ﾉ︵ ┻━┻",
    "٩(ఠ益ఠ)۶",
    "(╬ Ò ‸ Ó)",
    "(*`益´*)",
    "(〃>_<;〃)",
    "(*ノωノ)",
    "(*/ω\\*)",
    "(*^_^*)",
    "(°ロ°)",
    "(・・?)",
    "Σ(°△°|||)",
    "(⊙_⊙)",
    "(@_@)",
    "(♡˙︶˙♡)",
    "(´ ▽`).。ｏ♡",
    "(ノ*>∀<)ノ♡",
    "♡( ◡‿◡ )",
    "(づ￣ ³￣)づ",
    "(づ。◕‿‿◕。)づ",
    "¯\\_(ツ)_/¯",
    "(・_・;)",
    "(•_•) ( •_•)>⌐■-■ (⌐■_■)",
    "( ͡° ͜ʖ ͡°)",
    "(￣ー￣)",
    "(｀・ω・´)",
    "(=^ω^=)",
    "(^･ω･^)",
    "( ̄(oo) ̄)",
    "( ・(ｴ)・ )",
    "ฅ(＾・ω・＾ฅ)",
    "(U ᵕ U❁)",
    "(﹃ .)",
    "(u_u)",
    "(-_-)zzZ",
    "(。-ω-)zzZ",
    "(ノ°▽°)ノ⌒♪",
    "ヾ(•ω•`)o",
    "(^_^)/~",
    "m(_ _)m",
    "(・∀・)",
    "(´∀｀)",
    "(´-ω-｀)",
    "(`・ω・´)ゞ",
    "(ΦωΦ)",
    "w(°o°)w",
    "(；一_一)",
    "(¬_¬)",
    "(○｀д´)ノシ",
    "φ(•ᴗ•○)",
    "(ﾉ*°▽°)ﾉ",
    "ヽ(´▽｀)/",
    "(*>ω<*)",
]

def _group_to_id(group: str) -> str:
    return group.split()[0].lower()

def parse_emoji_list(text: str) -> list[dict]:
    """Parse emoji-list.txt into ordered list of {emoji, name_en, group}."""
    entries = []
    current_group = ""
    for line in text.splitlines():
        if line.startswith("# group: "):
            current_group = line[9:].strip()
        elif line and not line.startswith("#"):
            m = re.match(r"^[0-9A-F ]+;\s+fully-qualified\s+#\s+(\S+)\s+E[\d.]+\s+(.+)$", line)
            if m:
                entries.append({"emoji": m.group(1), "name_en": m.group(2).strip(), "group": current_group})
    return entries


def parse_cldr(xml_text: str) -> tuple[dict[str, str], dict[str, list[str]]]:
    """Return (tts_names, keywords) dicts keyed by emoji character."""
    tts: dict[str, str] = {}
    kws: dict[str, list[str]] = {}
    for ann in ET.fromstring(xml_text).iter("annotation"):
        cp = ann.get("cp", "")
        if not cp:
            continue
        text = (ann.text or "").strip()
        if ann.get("type") == "tts":
            tts[cp] = text
        else:
            kws[cp] = [k.strip() for k in text.split("|") if k.strip()]
    return tts, kws


def download_cldr_zip() -> zipfile.ZipFile:
    print(f"Downloading CLDR {CLDR_VERSION} zip ...")
    req = urllib.request.Request(CLDR_ZIP_URL, headers={"User-Agent": "emojizasu-builder/1.0"})
    with urllib.request.urlopen(req, timeout=120) as r:
        data = r.read()
    print(f"  {len(data) // 1024 // 1024} MB downloaded")
    return zipfile.ZipFile(io.BytesIO(data))


def fetch_cldr(lang: str, zf: zipfile.ZipFile) -> tuple[dict[str, str], dict[str, list[str]]]:
    def read(zip_path: str) -> tuple[dict, dict]:
        try:
            with zf.open(zip_path) as f:
                return parse_cldr(f.read().decode("utf-8"))
        except KeyError:
            return {}, {}

    names, kws = read(f"common/annotations/{lang}.xml")
    d_names, d_kws = read(f"common/annotationsDerived/{lang}.xml")
    for k, v in d_names.items():
        names.setdefault(k, v)
    for k, v in d_kws.items():
        kws.setdefault(k, v)
    return names, kws


_NAME_ENTRY_RE = re.compile(r'\nmsgid "(.+?)\.name"')
_CAT_ENTRY_RE = re.compile(r'\nmsgid "category\.([\w.]+)"\nmsgstr "((?:[^"\\]|\\.)*)"')


def escape_id(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def escape_str(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def _po_header(lang: str) -> str:
    return (
        'msgid ""\nmsgstr ""\n'
        f'"Language: {lang}\\n"\n'
        '"MIME-Version: 1.0\\n"\n'
        '"Content-Type: text/plain; charset=UTF-8\\n"\n'
        '"Content-Transfer-Encoding: 8bit\\n"\n'
    )


def _parse_blocks(path: str) -> tuple[str, list[tuple[str, str]]]:
    """Return (header_text, [(key, block_text), ...]) from an existing PO file.

    Each block_text runs from the '\\n' before its msgid up to (not including)
    the '\\n' before the next .name entry, preserving multi-line msgstr verbatim.
    """
    with open(path, encoding="utf-8") as f:
        content = f.read()
    matches = list(_NAME_ENTRY_RE.finditer(content))
    if not matches:
        return content, []
    header = content[:matches[0].start()]
    blocks = []
    for i, m in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(content)
        blocks.append((m.group(1), content[m.start():end]))
    return header, blocks


def _fresh_emoji_block(emoji: str, cldr_names: dict, cldr_kws: dict) -> str:
    ch_bare = emoji.replace("️", "")
    name = cldr_names.get(emoji) or cldr_names.get(ch_bare) or ""
    kws = cldr_kws.get(emoji) or cldr_kws.get(ch_bare) or []
    if not name and not kws:
        return ""
    block = ""
    if name:
        block += f'\nmsgid "{escape_id(emoji)}.name"\nmsgstr "{escape_str(name)}"\n'
    if kws:
        block += f'\nmsgid "{escape_id(emoji)}.keywords"\nmsgstr "{escape_str(" | ".join(kws))}"\n'
    return block


def _fresh_kaomoji_block(text: str) -> str:
    return (
        f'\nmsgid "{escape_id(text)}.name"\nmsgstr ""\n'
        f'\nmsgid "{escape_id(text)}.keywords"\nmsgstr ""\n'
    )


def _parse_all_blocks(lang_dir: str) -> dict[str, str]:
    """Parse every non-categories PO file in lang_dir into a flat {key: block_text} dict."""
    result = {}
    for path in glob.glob(os.path.join(lang_dir, "*.po")):
        if os.path.basename(path) == "categories.po":
            continue
        _, blocks = _parse_blocks(path)
        for key, block_text in blocks:
            result[key] = block_text
    return result


def _merge_po(path: str, lang: str, keys: list[str], fresh_fn,
              existing: dict[str, str]) -> None:
    """Write or update a PO file.

    For each key, copies the existing block verbatim if present in `existing`
    (sourced from all category files, so moved emoji are handled correctly);
    otherwise generates a fresh block via `fresh_fn(key)`.
    """
    os.makedirs(os.path.dirname(path), exist_ok=True)
    out = _po_header(lang)
    for key in keys:
        escaped = escape_id(key)
        out += existing[escaped] if escaped in existing else fresh_fn(key)
    with open(path, "w", encoding="utf-8") as f:
        f.write(out)


def _merge_categories_po(path: str, lang: str, first_emoji: dict[str, str]) -> None:
    """Update categories.po, preserving any existing msgstr values."""
    existing: dict[str, str] = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            content = f.read()
        for m in _CAT_ENTRY_RE.finditer(content):
            existing[m.group(1)] = m.group(2)

    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(_po_header(lang))
        for cat_id in ["recent"] + CATEGORY_IDS + ["kaomoji"]:
            if cat_id == "recent":
                default_emoji = "🕐"
            elif cat_id == "kaomoji":
                default_emoji = KAOMOJI[0]
            else:
                default_emoji = first_emoji.get(cat_id, "")
            f.write(f'\nmsgid "category.{cat_id}"\nmsgstr "{existing.get(cat_id, "")}"\n')
            f.write(f'\nmsgid "category.{cat_id}.emoji"\nmsgstr "{existing.get(cat_id + ".emoji", default_emoji)}"\n')


def generate_lang(lang: str, emoji_entries: list[dict], cldr_names: dict, cldr_kws: dict) -> None:
    out_dir = os.path.join(LOCALE_DIR, lang)

    existing = _parse_all_blocks(out_dir)

    by_cat: dict[str, list[str]] = {}
    for e in emoji_entries:
        if e["group"] not in SKIP_GROUPS:
            by_cat.setdefault(_group_to_id(e["group"]), []).append(e["emoji"])

    first_emoji = {cat_id: emojis[0] for cat_id, emojis in by_cat.items() if emojis}
    _merge_categories_po(os.path.join(out_dir, "categories.po"), lang, first_emoji)

    for cat_id, emoji_list in by_cat.items():
        _merge_po(
            os.path.join(out_dir, f"{cat_id}.po"), lang, emoji_list,
            lambda ch, n=cldr_names, k=cldr_kws: _fresh_emoji_block(ch, n, k),
            existing,
        )

    _merge_po(
        os.path.join(out_dir, "kaomoji.po"), lang, KAOMOJI, _fresh_kaomoji_block, existing,
    )

    print(f"  {lang}: {len(by_cat)} category files, {sum(len(v) for v in by_cat.values())} emoji, {len(KAOMOJI)} kaomoji")


def download_emoji_list() -> str:
    print(f"Downloading emoji-test.txt for Unicode {EMOJI_VERSION} ...")
    req = urllib.request.Request(EMOJI_LIST_URL, headers={"User-Agent": "emojizasu-builder/1.0"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.read().decode("utf-8")


def _check_categories(text: str) -> None:
    groups_in_list = {line[9:].strip() for line in text.splitlines() if line.startswith("# group: ")}
    derived_ids = sorted({_group_to_id(g) for g in groups_in_list if g not in SKIP_GROUPS})
    if derived_ids != sorted(CATEGORY_IDS):
        raise SystemExit(f"Category ID mismatch — derived: {derived_ids}, expected: {sorted(CATEGORY_IDS)}")

# the manifest pre-processes the set of emojis and categories, versus computing them at runtime
def write_manifest(emoji_entries: list[dict]) -> None:
    langs = sorted(
        d for d in os.listdir(LOCALE_DIR)
        if os.path.isdir(os.path.join(LOCALE_DIR, d))
    )

    po_files = []
    for lang in langs:
        lang_dir = os.path.join(LOCALE_DIR, lang)
        bases = sorted(f[:-3] for f in os.listdir(lang_dir) if f.endswith(".po"))
        for base in bases:
            po_files.append(f"{lang}/{base}")

    categories = ["recent"] + CATEGORY_IDS + ["kaomoji"]

    emoji_chars = []
    category_items: dict[str, list] = {}
    for e in emoji_entries:
        if e["group"] in SKIP_GROUPS:
            continue
        cat = _group_to_id(e["group"])
        emoji_chars.append(e["emoji"])
        category_items.setdefault(cat, []).append(e["emoji"])
    for k in KAOMOJI:
        emoji_chars.append(k)
        category_items.setdefault("kaomoji", []).append(k)

    manifest_path = os.path.join(ROOT, "picker", "data", "manifest.json")
    manifest = {
        "languages": langs,
        "poFiles": po_files,
        "categories": categories,
        "kaomojis": {k: 1 for k in KAOMOJI},
        "items": emoji_chars,
        "itemMap": {c: 1 for c in emoji_chars},
        "categoryItems": category_items,
    }
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"Manifest: {len(langs)} languages, {len(po_files)} PO files, {len(categories)} categories, {len(emoji_chars)} items")


def main() -> None:
    emoji_list_text = download_emoji_list()
    emoji_entries = parse_emoji_list(emoji_list_text)
    print(f"Loaded {len(emoji_entries)} fully-qualified emoji from emoji-test.txt")

    _check_categories(emoji_list_text)

    cldr_zip = download_cldr_zip()

    for lang in SUPPORTED_LANGS:
        print(f"Generating {lang} ...")
        cldr_names, cldr_kws = fetch_cldr(lang, cldr_zip)
        generate_lang(lang, emoji_entries, cldr_names, cldr_kws)

    write_manifest(emoji_entries)

    print("Done.")


if __name__ == "__main__":
    main()
