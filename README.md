<p align="center"><img src="media/curseforge-icon.png" alt="Legacy Navigator" width="128"></p>

# Legacy Navigator

Legacy Navigator plans your next Legacy points in WoW Forever. It shows the best next steps for the current character and your alts, tracks a goal on screen, and docks a panel next to Blizzard's Legacy window.

## Features

- Recommendations with the remaining requirements for each step, for the current character and for your alts.
- Goal types: points, renown, challenge and perk.
- Pin a step and follow it in the tracker, with a progress bar and "Here" opportunities for what you can do where you are right now.
- Middle-click any challenge, perk or row to set it as your goal; left-click a row to jump to that challenge in the Legacy window.
- Docked panel with the tabs Plan, Characters and Settings.
- Opens the Legacy window even before you have earned your first point.
- EllesmereUI skin support.
- Minimap button and a keybinding.
- Languages: enUS and deDE.

## Usage

Everything is available from the panel and the minimap button. Slash commands (`/lnav` or `/legacynav`):

| Command | Effect |
| --- | --- |
| `/lnav` | Toggle the Legacy window (the panel follows it) |
| `/lnav plan` | Print the current plan to chat |
| `/lnav goal points N` | Goal: N more spendable points |
| `/lnav goal renown N` | Goal: renown level N |
| `/lnav goal challenge ID` | Goal: a challenge, by achievement ID |
| `/lnav goal node ID [ranks]` | Goal: a perk node, optionally a number of ranks |
| `/lnav goal clear` | Clear the goal |
| `/lnav set pvp\|dungeon\|raid\|switch on\|off` | Toggle an activity filter or the switch setting |
| `/lnav tracker on\|off` | Show or hide the tracker |
| `/lnav tracker alpha N` | Tracker background opacity, 0-100 |
| `/lnav unlock` / `/lnav lock` | Unlock the tracker to drag it / lock it again |
| `/lnav reset` | Reset tracker and panel positions |
| `/lnav status` | Show data status (`/lnav status log` lists incomplete scans) |
| `/lnav legacy` | Open the Legacy window |
| `/lnav refresh` | Rescan the current character |
| `/lnav diag` | Diagnostics for bug reports |

## Installation

- Once released: install from CurseForge or Wago with your addon manager.
- Manually: clone this repository into `Interface/AddOns/LegacyNavigator` and run `tools/fetch-libs.sh` to fetch the libraries. It needs `git` and `svn` (for LibDBIcon).

## Notes & limitations

- Read-only: the addon never spends points or changes your talents.
- Recommendations are based on data from characters you have logged in. Known characters only.
- Perk requirements marked "unchecked" are minimum estimates.

## Development

- Tests use plain Lua 5.1: `for f in tests/*_spec.lua; do lua "$f"; done`
- Libraries are declared as externals in `.pkgmeta`; `tools/fetch-libs.sh` fetches the same sources for local use.

## Credits

- [Ace3](https://www.wowace.com/projects/ace3) (license in `LICENSES/Ace3.txt`)
- LibDataBroker-1.1
- LibDBIcon-1.0

Libraries are fetched from their upstream sources and keep their upstream licenses.

## License

License: to be decided.
