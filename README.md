# Forever Loot Rolls

An extended loot roll window for **World of Warcraft: Forever**.

As soon as your group has to roll on an item, the window opens and shows live who picked **Need**, **Greed** or **Pass**, who is still choosing, every roll and who won. When all rolls are done it closes again by itself.

---

## Features

- Opens by itself when a roll starts – optionally only in dungeons and raids
- Plain and small: per item its name and a thin time bar, below it every player with the icon of their choice and their roll – no other text
- Hover an item for its tooltip; click it to fold it in or out
- Winner on top, then Need, Greed, Disenchant and Pass, highest roll first
- Players who have not chosen yet are shown as "waiting"
- Big Need / Greed / Pass buttons right under the item while you still have to roll (can be turned off)
- Closes a few seconds after the last roll is done; stays open while your mouse is over it
- Finished rolls stay in the list per character (also after `/reload`); the Clear button empties it
- The list starts fresh with every new dungeon or raid run: a different dungeon, or a new copy of the same one after a reset, told apart by the instance ID in its creatures' GUIDs (a corpse run or /reload keeps it; can be turned off)
- **Loot history** (note button, top left): every item ever rolled on, newest first, grouped by dungeon run (each copy of a dungeon is its own group, even the same dungeon twice in a row) or zone visit, with time, winner and roll. Kept when you clear the list or change dungeons. Filters: "only my wins" and item quality (e.g. from rare, to hide green items).
- Shift-click an item to link it in chat, Ctrl-click to try it on
- English and German (follows your game language); the chat messages are read in every game language

## Look

The windows use WoW Forever's own interface parts, the same as the character and reputation window: the metal window frame with title bar, the character pane background, category plates with fold-in arrows, striped rows, the reputation bar for the time left and Blizzard's slim scroll bar. If a client lacks any of these, the windows fall back to a classic look.

## Commands

| Command | |
|---|---|
| `/lootrolls` or `/flr` | Show or hide the window |
| `/lootrolls test` | Made-up demo rolls to try the window (only you see them) |
| `/lootrolls history` | Show or hide the loot history |
| `/lootrolls clear` | Remove finished rolls |
| `/lootrolls options` | Open the settings |

## Settings

Options → AddOns → Forever Loot Rolls, or the gear in the window:

- When finished items fold in: right away, a few seconds after everyone has rolled (default), when the next roll starts, or never
- Two sections, set separately: **Dungeons and raids** (open when entering – off by default, open when a roll starts, close when everyone has rolled + seconds) and **Open world** (open when a roll starts, close when everyone has rolled + seconds)
- Close with Escape
- Need / Greed / Pass buttons in the window
- Clear the list on a new dungeon run
- Background opacity (default 100 %)
- Window width and maximum window height (longer lists scroll)
- How many rolls the list keeps
- How many items the loot history keeps (default 1000, up to 5000)

## Loot history size

The loot history is saved per character in `WTF/Account/<account>/<realm>/<character>/SavedVariables/ForeverLootRolls.lua`. It is limited by the number of items (setting "Items in the loot history", default 1000, up to 5000); when the limit is reached, the oldest items are removed first. One item takes roughly 0.3–0.5 KB, so 1000 items are about 0.5 MB – no problem for the game. There is no age limit. "Delete history" in the history window empties it completely.

## How it works

Choices, rolls and winners come from the game's loot chat messages (the same lines you see in the chat), using the game's own text for your language. The item, time left and whether you may roll Need come from the roll itself.

## Development

Tests run without a WoW client:

```sh
lua5.1 tests/rolls_test.lua .
lua5.1 tests/archive_test.lua .
lua5.1 tests/ui_smoke_test.lua .
```

Releases: push a tag like `v0.1.0`. GitHub Actions runs the tests, builds the zip with the BigWigs packager and uploads it to CurseForge (needs `## X-Curse-Project-ID` in the `.toc` and the `CF_API_KEY` secret). Every release needs a section for its version in `CHANGELOG.md`.

## License

MIT – see [LICENSE](LICENSE).
