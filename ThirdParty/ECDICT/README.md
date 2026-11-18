# Bundled ECDICT data

WordShelf includes the English–Chinese dictionary data from
[skywind3000/ECDICT](https://github.com/skywind3000/ECDICT), pinned to commit
`39cfb9672c0906b63569e0453c2e6abfb9ab182a`.

- Upstream file: `ecdict.csv`.
- License: [MIT](LICENSE), copyright © 2025 Linwei, as published at that revision.
- Source SHA-256: `d1ecbdf9ee2b920afb6f430ca6b6bb9f559588cf0dff86e04bd255f9390843cc`.
- The app bundles an SQLite database containing word, phonetic, Chinese translation,
  English definition, and nullable BNC / contemporary-corpus (`frq`) rank fields.
  Missing/zero ranks remain unknown. Only exact-entry ranks are used: component
  word ranks are never presented as a phrase or sentence's frequency.
  Case-equivalent keys are merged, preferring an
  upstream lowercase headword over an acronym spelling. CSV newline
  markers are decoded only when displaying a definition.
- The original license and source metadata are also bundled inside the application's
  resources. No dictionary request is sent to a remote server.

To reproduce the dictionary using Python 3's standard library:

```sh
python3 scripts/prepare_dictionary.py
```

The script downloads the pinned source to `.dictionary-cache/` if necessary,
verifies its SHA-256 checksum, builds and checks the database, and records the
entry count and database digest in `dictionary-metadata.json`.

This bundled dictionary is separate from the user's `words.json` collection. The
collection stores only an array of English original strings, with no definitions,
timestamps, context, or source information. Learning profiles, purpose feedback and
review progress are kept in a separate local `learning.json` file.
