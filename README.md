# Pulse

A native macOS browser built on WebKit, with Arc's look and keyboard-first workflow.

## Features

- Sidebar with pinned tabs (favicon grid) and "Today" tabs, newest on top.
- Command bar (⌘T / ⌘L): open a URL, search, or jump to an open tab.
- Inset rounded web content, collapsible sidebar that peeks in from the left edge.
- Drag tabs to reorder them, or between sections to pin and unpin; resize the sidebar by its edge.
- Double-click a tab to rename it; middle-click to close it.
- Session restore; tabs load lazily when first shown.
- Find in page, downloads to ~/Downloads, and a native error page when a site can't load.

## Shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘T | New tab (command bar) |
| ⌘L | Edit current URL |
| ⌘W / ⌘⇧T | Close tab (resets pinned tabs) / reopen closed tab |
| ⌘D | Pin / unpin tab |
| ⌘S | Toggle sidebar |
| ⌘1…⌘8, ⌘9 | Select tab N / last tab |
| ⌘⌥↓ ⌘⌥↑, ⌃⇥ ⌃⇧⇥ | Next / previous tab |
| ⌘[ / ⌘] | Back / forward |
| ⌘R / ⌘⇧R | Reload / reload ignoring cache |
| ⌘⇧C | Copy URL |
| ⌘F / ⌘G / ⌘⇧G | Find on page / next / previous match |
| ⌘+ / ⌘- / ⌘0 | Zoom |
| ⌘⌥I | Web Inspector |
| ⌘-click | Open link in background tab |

## Development

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
The Xcode project is generated from `project.yml` and not committed.

```sh
xcodegen generate
open Pulse.xcodeproj
# or
xcodebuild -project Pulse.xcodeproj -scheme Pulse -destination 'platform=macOS' test
```
