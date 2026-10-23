# Pulse

A native macOS browser built on WebKit, with Arc's look and keyboard-first workflow.

## Features

- Spaces: separate sidebars with their own color, pinned and "Today" tabs; Favorites (favicon grid) are shared.
- Switch spaces with ⌃1…⌃9, ⌘⌥← / ⌘⌥→, the dots at the bottom of the sidebar, or a two-finger swipe.
- Command bar (⌘T / ⌘L) that behaves like Chrome's address bar: inline completion of sites you
  type or visit often, history ranked by frequency and recency, open tabs and Google suggestions.
  ⇥ or → accepts the completion, ⇧⌦ removes a suggestion from history. It also runs actions, like
  Arc's: type "pin", "move tab to work", "devtools" or "clear data" and pick it right below the top result.
- Inset rounded web content, collapsible sidebar that peeks in from the left edge.
- Drag tabs to reorder them, or between Favorites, Pinned and Today; resize the sidebar by its edge.
- Double-click a tab to rename it; middle-click to close it.
- Context menus like Chrome's: page links, images and video open in background tabs or another
  space, "Copy Image Address", searches with your engine, and Copy URL, Share and Print on the page.
  Tabs can be duplicated, closed below or closed with all others; pinned tabs can keep the current page.
  Downloads and history rows have their own menus.
- Private windows (⇧⌘N): cookies and site data live in memory and vanish with the window; no history
  or session is recorded, and favicons skip the disk cache. Ad blocking and settings are shared.
- Session restore; tabs load lazily when first shown, and tabs off screen for an hour (configurable)
  sleep to free memory, waking up with their back/forward history. Faded icons mark sleeping tabs.
- Find in page and a native error page when a site can't load.
- Links to other apps (`mailto:`, `zoommtg:`…) open in that app, asking first unless clicked; sign-in
  prompts for HTTP Basic/Digest auth and JavaScript `prompt()` dialogs.
- Closing a popup or a link opened in a new tab returns to the page that opened it.
- Hovering a link previews its URL in the page's corner; tabs show a spinner while loading, a
  red camera or microphone while a site uses them, and a speaker while they play audio: click it
  (or ⌃M) to mute the tab, which stays muted through reloads and sleep.
- VoiceOver labels for sidebar controls, and fades instead of slides with Reduce Motion on.
- Downloads like Chrome's: a bubble with progress, pause/resume, cancel and retry, and a ⌘⇧J page
  that remembers past downloads.
- First-launch onboarding that imports Chrome's history and bookmarks bar (also File › Import from
  Chrome…) and offers to make Pulse the default browser.
- Settings (⌘,): startup behavior, default browser, search engine and suggestions, download
  location prompt, per-site camera/microphone permissions.
- Ad and tracker blocking with EasyList and EasyPrivacy, compiled into WebKit content rules and
  refreshed every four days; allow ads per site from the address bar's menu.
- Extensions (Chrome and Safari WebExtensions, via WebKit): the Chrome Web Store's own button reads
  "Add to Pulse" and installs into Pulse (also "Add Extension to Pulse" in the command bar or the
  extensions menu), or File › Install Extension… with a folder, ZIP or CRX. The puzzle button in the sidebar runs their actions and popups; manage
  them in Settings › Extensions. Private windows run no extensions.
- History like Chrome's: ⌘Y page grouped by day with search and multi-select delete, a History menu
  with recently closed tabs and visits, and "Clear Browsing Data" (⌘⇧⌫).

## Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘T | New tab (command bar) |
| ⇧⌘N | New private window |
| ⌘L | Edit current URL |
| ⌘W / ⌘⇧T | Close tab (resets pinned tabs) / reopen closed tab |
| ⌘D | Pin / unpin tab in the current space |
| ⌃1…⌃9 | Switch to space N |
| ⌘⌥← / ⌘⌥→ | Previous / next space |
| ⌘S | Toggle sidebar |
| ⌘1…⌘8, ⌘9 | Select tab N / last tab |
| ⌘⌥↓ ⌘⌥↑, ⌃⇥ ⌃⇧⇥ | Next / previous tab |
| ⌘[ / ⌘] | Back / forward |
| ⌘R / ⌘⇧R | Reload / reload ignoring cache |
| ⌘⇧C | Copy URL |
| ⌃M | Mute / unmute tab |
| ⌘F / ⌘G / ⌘⇧G | Find on page / next / previous match |
| ⌘+ / ⌘- / ⌘0 | Zoom |
| ⌘⌥I | Web Inspector |
| ⌘Y / ⌘⇧⌫ | History / Clear browsing data |
| ⌘⇧J | Downloads |
| ⌘-click / middle-click | Open link in background tab (add ⇧ for a foreground tab) |

## Development

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
The Xcode project is generated from `project.yml` and not committed.

```sh
xcodegen generate
open Pulse.xcodeproj
# or
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=macOS' test
```

## Website

The landing page lives in `site/` (Astro, Node 26) and deploys to GitHub Pages from `main`.

```sh
cd site
npm install
npm run dev
```
