# UX tooling (Jev)

Design-time judgments from Jev, TypeSafe's System One model, used to audit and score the app's copy and screens against `docs/12-ux-direction.md`. Nothing here runs inside the app; the key lives only in the owner's environment as `TYPESAFE_API_KEY` (docs/12 §8).

```powershell
cd C:\Drivalry
node tools/ux/extract_strings.mjs > tools/ux/out/strings.json   # every user-facing string in app/lib
node tools/ux/jev_copy_audit.mjs                                 # per string: main problem + voice score
node tools/ux/jev_screen_audit.mjs tools/ux/screens_before.json  # per screen: five 0–3 scores
node tools/ux/jev_screen_audit.mjs tools/ux/screens_after.json
```

| File | What |
| --- | --- |
| `extract_strings.mjs` | Collects quoted literals of two or more words from `app/lib`, joining Dart's adjacent-literal line breaks |
| `jev_copy_audit.mjs` | For each distinct string: a Choice (fine / technical / too_long / unclear / tone) and a Score 0–3 for voice. Cached by text in `out/copy_cache.json`, so re-runs only judge changed strings. Report: `out/copy_audit.md` |
| `jev_screen_audit.mjs` | For each screen description: Scores for hierarchy, cognitive load, Waze feel, Kith feel and one-second glanceability. Report: `out/<input>_scores.md` |
| `screens_before.json` | Eleven screen states as they were before the pass (from `docs/12-ux-audit.md`) |
| `screens_after.json` | The same eleven after the pass; written as each screen lands |

Targets (docs/12 §6 and §8): zero strings flagged `technical`, fewer than ten flagged anything, average voice above 2.0; screen mean above 2.2 with Kith and driving dimensions at or above 2.0 on the screens they apply to.

`out/` is committed so the before and after numbers stay with the history; `copy_cache.json` is the only large file and can be deleted to force a full re-judge.
