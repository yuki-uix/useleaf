#!/usr/bin/env python3
"""Reproduce the bundled ECDICT SQLite database from a pinned, verified CSV.

The build uses Python's standard library only. Application startup never downloads
anything. CSV is a build input; only the generated SQLite file ships with the app.
"""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import sqlite3
import urllib.request

REVISION = "39cfb9672c0906b63569e0453c2e6abfb9ab182a"
EXPECTED_SHA256 = "d1ecbdf9ee2b920afb6f430ca6b6bb9f559588cf0dff86e04bd255f9390843cc"
SOURCE_URL = f"https://raw.githubusercontent.com/skywind3000/ECDICT/{REVISION}/ecdict.csv"
ROOT = Path(__file__).resolve().parents[1]


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / ".dictionary-cache/ecdict.csv")
    parser.add_argument("--output", type=Path, default=ROOT / "Sources/WordShelfCore/Resources/ecdict.sqlite")
    args = parser.parse_args()
    if not args.source.exists():
        args.source.parent.mkdir(parents=True, exist_ok=True)
        temporary = args.source.with_suffix(".download")
        print(f"Downloading pinned ECDICT {REVISION}…", flush=True)
        urllib.request.urlretrieve(SOURCE_URL, temporary)
        temporary.replace(args.source)
    digest = sha256(args.source)
    if digest != EXPECTED_SHA256:
        raise SystemExit(f"CSV checksum mismatch: expected {EXPECTED_SHA256}, got {digest}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(".building")
    temporary.unlink(missing_ok=True)
    connection = sqlite3.connect(temporary)
    connection.executescript("""
        PRAGMA page_size=4096;
        CREATE TABLE entries (
            word TEXT COLLATE NOCASE PRIMARY KEY,
            phonetic TEXT NOT NULL,
            translation TEXT NOT NULL,
            definition TEXT NOT NULL,
            bnc_rank INTEGER,
            contemporary_rank INTEGER
        ) WITHOUT ROWID;
    """)
    with args.source.open(encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        for row in reader:
            source_word = row["word"].strip()
            word = source_word.lower()
            if not word:
                continue
            # A lowercase headword ("us") takes precedence over a case-only
            # acronym collision ("US"), while acronyms remain searchable.
            insert = "INSERT OR REPLACE" if source_word == word else "INSERT OR IGNORE"
            def positive_rank(field):
                value = int(row.get(field, "") or 0)
                return value if value > 0 else None
            connection.execute(
                f"{insert} INTO entries VALUES (?, ?, ?, ?, ?, ?)",
                (word, row.get("phonetic", ""), row.get("translation", ""), row.get("definition", ""),
                 positive_rank("bnc"), positive_rank("frq")),
            )
    connection.commit()
    count = connection.execute("SELECT count(*) FROM entries").fetchone()[0]
    integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
    if integrity != "ok" or count < 700_000:
        raise SystemExit(f"Invalid dictionary: {count} entries, integrity {integrity}")
    connection.execute("VACUUM")
    connection.close()
    temporary.replace(args.output)
    metadata = {
        "name": "ECDICT",
        "repository": "https://github.com/skywind3000/ECDICT",
        "revision": REVISION,
        "license": "MIT",
        "source_url": SOURCE_URL,
        "source_sha256": digest,
        "entry_count": count,
        "frequency_fields": {"bnc_rank": "ECDICT BNC rank", "contemporary_rank": "ECDICT frq rank"},
        "database_sha256": sha256(args.output),
    }
    metadata_path = ROOT / "Sources/WordShelfCore/Resources/dictionary-metadata.json"
    metadata_path.write_text(json.dumps(metadata, indent=2) + "\n")
    print(json.dumps(metadata, indent=2))


if __name__ == "__main__":
    main()
