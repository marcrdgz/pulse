---
name: release
description: Prepare a Pulse release - pick the next version from the commits since the last tag, draft the What's New notes (and scenes) in Pulse/Resources/ReleaseNotes.json, bump the version, verify, commit and tag locally, then build the signed, notarized DMG. Use when Marc asks to release, cut, tag or ship a version, or to write the What's New / release notes.
---

# Release Pulse

Prepares everything up to a local tag and a notarized DMG. Publishing is Marc's: **never push or
create the GitHub release**; end by printing the commands for him. Pushing `main` deploys the site,
whose release notes page reads `ReleaseNotes.json`, so the DMG must be on GitHub before `main` is
pushed, or the site announces a version nobody can download.

## 1. Preconditions

- On `main`, working tree clean (`git status --porcelain` is empty). Otherwise stop and say why.
- `make test` passes. Diagnose failures; don't release over them.

## 2. Commits in this release

- Base: the latest `v*` tag (`git describe --tags --abbrev=0 --match 'v*'`). With no tag yet, the
  commit that last changed `MARKETING_VERSION` in `project.yml`
  (`git log -1 --format=%h -S'MARKETING_VERSION' -- project.yml`).
- `git log --format='%h %s%n%b' <base>..HEAD`. Read a commit's diff only when its subject doesn't
  say what a user would notice.

## 3. Version

Current version: `MARKETING_VERSION` in `project.yml`. Recommend the next one from the commits:

| Commits contain | 1.0 and later | Before 1.0 |
|---|---|---|
| `!` or `BREAKING CHANGE` (lost data, removed feature, changed shortcut) | major | minor |
| `feat` a user can see (not `feat(site)`) | minor | minor |
| only `fix`, `perf`, user-visible `style` | patch | patch |

`chore`, `docs`, `test`, `ci`, `refactor` and anything scoped `site` don't count. Nothing
user-visible means no release: say so and stop.

Ask Marc to confirm with `AskUserQuestion`: the recommended version first, with a one-line reason
("4 features, 6 fixes since v0.2.0"), and the alternatives. Moving to 1.0.0 is always his call.
Write nothing until he has answered; the notes and the bump use the version he picks.

## 4. Notes

Prepend one entry to `Pulse/Resources/ReleaseNotes.json` (newest first; `ReleaseNotes.swift` is the
schema, and `ReleaseNotesTests` checks the file). The app's What's New and the
site's release notes page (`site/src/pages/releases.astro`) both read it, so there's nothing else to
update:

```json
{
  "version": "0.4.0",
  "date": "YYYY-MM-DD",
  "summary": "One sentence naming the release's two or three biggest things.",
  "highlights": [
    { "title": "Split View", "body": "…", "symbol": "rectangle.split.2x1", "shortcut": "⌃⇧=", "scene": "splitView" }
  ],
  "improvements": ["…"],
  "fixes": ["…"]
}
```

Writing rules:

- Write for people who use Pulse, not for developers: say what they can do or what no longer goes
  wrong. Never use commit wording, type prefixes, hashes or code names ("hibernation" becomes "tabs
  sleep").
- Group commits that are about one thing ("feat: split view" + "feat: drag into split view" +
  "fix: split view flicker" make one highlight).
- **Highlights**: 0–4 features that change how someone browses, most important first. Title Case,
  ≤ 5 words. Body ≤ 2 sentences and says how to find it (a gesture, a menu, a setting).
  `symbol` is an SF Symbol that exists. `shortcut` only when a menu item has one: copy it from
  `BrowserCommands.swift` in the menu's order (⌃⌥⇧⌘). A patch release usually has none, and then
  What's New opens after the update only for someone who skipped a release that had highlights.
- **Improvements**: smaller visible changes, one sentence each, sentence case, with a full stop.
- **Fixes**: describe what works now ("⌘W closes the tab, not the window"), not the bug.
- Leave out invisible work: refactors, tests, the site, build changes.
- Don't claim anything the code doesn't do. Check defaults, menus and shortcuts in the source.

## 5. Scenes

A highlight can show an animated drawing of Pulse instead of a symbol, like the screen on the
landing page. Give a scene to the highlights that are easier to show than to tell (gestures,
layout changes, something appearing in the UI). Static ideas keep their symbol.

- Reuse a `WhatsNewScene` case when it fits. Otherwise add a case and a view in
  `Pulse/UI/WhatsNew/WhatsNewScenes.swift`, built from its building blocks (`Looping`,
  `MiniWindow`, `MiniTabRow`, `PageLines`) and `Brand` colors, in the style of the existing scenes. Draw the UI as
  it really looks; it's a sketch, so no real text or brands beyond short labels.
- Each scene loops in 3–4 phases (≈ 3–5 s) and its last phase shows the outcome, which is what
  Reduce Motion shows.
- Once no entry in the JSON refers to a scene, delete it.

## 6. Bump and verify

- In `project.yml`: set `MARKETING_VERSION` to the new version and add 1 to
  `CURRENT_PROJECT_VERSION`.
- `make generate && make test`.
- Ask Marc to look at the result: `make run`, then Help › What's New in Pulse. Make his changes to
  the notes before going on.

## 7. Commit and tag

- One commit with the notes, any scenes and the version bump: `chore(release): vX.Y.Z`.
- An annotated tag whose message is the summary: `git tag -a vX.Y.Z -m "<summary>"`.
- Don't push.

## 8. Build the DMG

- `make dist`: archives with Developer ID, notarizes and staples `build/Pulse.dmg`. It refuses a
  dirty tree or an untagged HEAD. Notarization usually takes a few minutes.
- It needs the Developer ID Application certificate in the login keychain and the `pulse`
  notarytool profile. If either is missing, stop and tell Marc which; never work around signing.
- On failure, read `xcrun notarytool log <submission-id> --keychain-profile pulse` before retrying.

End with what changed, then the commands for Marc to run in this order:

```sh
git push origin vX.Y.Z
gh release create vX.Y.Z build/Pulse.dmg --verify-tag --title "Pulse X.Y.Z" --notes "<summary>"
git push origin main
```

Keep the asset named `Pulse.dmg`: `releases/latest/download/Pulse.dmg` is the stable link the
download page uses.
