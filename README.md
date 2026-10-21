# Pulse

A native macOS browser built on WebKit, with Arc's look and keyboard-first workflow.

## Features

- Sidebar with pinned tabs (favicon grid) and "Today" tabs, newest on top.
- Command bar (⌘T / ⌘L): open a URL, search, or jump to an open tab.
- Inset rounded web content, collapsible sidebar that peeks in from the left edge.
- Session restore; tabs load lazily when first shown.

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
