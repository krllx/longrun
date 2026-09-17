---
name: translate-docs
description: Translate this repo's README or course site into zh-CN, ja or ko, or review an incoming translation PR, following the project's translation canon. Use when the user says "переведи README", "translate the course", "сделай японскую версию", "review the zh-CN PR", names a locale (zh-CN, ja, ko), or asks to update a translation after the English page changed. Do not use for translating chat replies or code comments - this is only for the published README and course pages.
argument-hint: "README ja | course zh-CN | review ko | sync ja"
---

# Translating longrun's README and course

The rules live in one place: **[docs/TRANSLATION.md](../../../docs/TRANSLATION.md)**.
Read it before touching a file. Do not restate its glossary here or invent terms - if a
term is missing, add a row to that table in the same PR.

## Order of work

1. **Read the canon.** `docs/TRANSLATION.md` sections 2 (never translated), 3 (glossary)
   and the section for the target language.
2. **Read the English source in full** before writing anything.
3. **Translate the whole file in one pass.** Not chunk by chunk - register and
   terminology drift between chunks and that is the hardest thing to repair later.
   Copy code blocks, commands, links, anchors and badge URLs byte for byte.
4. **Review pass A - native reader.** Spawn a fresh agent that sees *only the
   translation*, never the English, and reads it as a developer who speaks that
   language. Ask it for the checklist tells in section 9.
5. **Review pass B - against the source.** A second fresh agent diffs translation
   against English for missing sections, changed commands, broken anchors, changed
   numbers.
6. **Mechanical check.** Anchors resolve, relative links resolve from the file's own
   directory, `lang` attribute matches the folder, the language bar lists every locale.

Passes A and B are separate agents on purpose: an agent that has just read the English
reads the translation through it and stops hearing that it sounds like English.

## Scope guard

Translate only what section 1 lists: `README.*` and `course/`. `docs/REFERENCE.md`,
`docs/ORCHESTRATOR.md` and everything under `skill/` stay English (plus Russian for the
two reference docs). The skill's own strings must match the CLI one to one.

Terminal output inside course scenarios is real CLI output and is never translated -
only the titles, captions, `who` lines and node labels around it.

## A course locale is three edits

1. `course/<locale>/index.html` - prose translated, `<html lang>` and `<title>` set, and
   the inline `window.LR_I18N` block (the player's own chrome) translated with the same
   keys as English.
2. `course/<locale>.js` - override file built exactly like `en.js`, same keys.
3. One line in the `LOCALES` list at the top of `course/app.js`.

Do not hand-edit the language bar in any HTML: it is rendered from `LOCALES`. CJK locales
also need a font stack line in `style.css` - Geist has no kana or Han glyphs.

Then `bash tests/course.sh`. It is the only thing standing between a forgotten key and a
Russian sentence on a Japanese page, because the base data is Russian and a missing key
falls back to it.

## After the English page changes

A release that edits `README.md` leaves four translations stale. Do not silently
re-translate the whole file: diff the English against the last translated revision, port
only the changed passages, and keep the rest as it is. A human-corrected sentence that
someone sent in a PR must survive the next sync.
