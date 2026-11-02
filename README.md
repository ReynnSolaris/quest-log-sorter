# QuestLogSorter

A grouped, collapsible quest log for the Fallout 4 Pip-Boy. Replaces the flat
list under DATA → QUESTS with a tree:

```
MAIN GAME                                          7 active
  ▾ Main Story                                        3/11
      The Molecular Level                        TRACKING
        ▪ Build the Signal Interceptor
        ✓ Speak to Sturges
      Reunions                                       DONE
  ▸ Brotherhood of Steel                              2/9
  ▸ Minutemen                                        1/14
  ▸ Companion Quests                                  0/6
FAR HARBOR                                         2 active
  ▾ Main Story                                        2/8
  ▸ Side Quests                                      0/12
NUKA-WORLD                                         0 active
```

Sections come from the plugin a quest is defined in, so DLCs separate
automatically and mod-added quests get their own section instead of being
dumped into the base game. Questlines come from a rules file.

The vanilla page keeps quests and objectives in two separate scrolling lists,
which is why the stock UI can't show objectives under the quest they belong to.
The tree merges them.

See **SETUP.md** for the step-by-step build and install guide, and
**docs/swf-structure.md** for how the Pip-Boy is actually assembled.

## Status

Unreleased and untested in game. The plugin is written against the real
CommonLibF4 headers; two things remain unverified and both are flagged in
place:

- the quest flag bits in the `adapter` block of `src/Quests.cpp` (there's a
  one-run logging switch to confirm them)
- `BGSLocalizedString`'s accessor, the single call not checked against a header
- quest tracking now routes through the game's own
  `BGSExternalInterface.call("SetQuestActive", formID)`, which is what the
  vanilla tab uses; it needs the shim wired up (step 7)

## Layout

```
xmake.lua              build config (XMake, not CMake)
src/                   F4SE plugin (C++23, CommonLibF4)
  Quests.cpp           walks TESQuest forms; adapter block isolates engine API
  Grouping.cpp         groups.json -> section/questline tree
  Bridge.cpp           native functions exposed to AS3
  Actions.cpp          dead code once the shim is wired - see file header
swf/src/               AS3 panel (Flash 11.2 / SWF 15)
  Main.as              document class
  qls/QuestLogPanel    the tree: flatten, filter, virtualized scroll, input
  qls/RowView.as       one pooled row
  qls/QLSShim.as       paste-into-DataPage glue
data/                  what ships to the player's Data folder
tools/                 xEdit script that generates grouping rules
docs/                  injection guide and SWF analysis
```

## How the pieces talk

The plugin registers on F4SE's Scaleform interface, which puts it at
`root1.f4se.plugins.QuestLogSorter` inside every menu movie. The panel calls:

| Function | Purpose |
|---|---|
| `getTree(includeFinished)` | the whole tree as a JSON string, once, on open |
| `setTracked(formID, tracked)` | make a quest the active one |
| `setCollapsed(key, collapsed)` | remember a fold |
| `flushState()` | write folds to disk |
| `reloadRules()` | re-read `groups.json` without a restart |
| `log(message)` | AS3 into the plugin log |

`getTree` hands the tree over as one JSON string and AS3 calls `JSON.parse` on
it. That's deliberate: `Scaleform::GFx::Value` stores strings as `const char*`
without owning them, so building the tree as native objects would mean
thousands of pointers into buffers we'd have to keep alive. One string sidesteps
that, and it's one boundary crossing instead of a few thousand.

All filtering happens in AS3, so typing in the search box never reaches native
code. A 400-quest log builds one array and scrolls with a pool of ~25 rows.

## Grouping rules

`Data\F4SE\Plugins\QuestLogSorter\groups.json`. A quest's questline resolves in
this order:

1. `lines.byForm` — exact plugin + local FormID
2. `lines.byPrefix` — EditorID prefix, longest match wins
3. `lines.byType` — the QUST record's Type field
4. `fallbackLine`

Fallout 4 keeps quest EditorIDs at runtime — `TESQuest` has a real
`formEditorID` member, unlike Skyrim where they're stripped — so step 2 should
fire on its own and you get Minutemen/Brotherhood/Railroad grouping out of the
box.

`tools/QLS_GenerateGroups.pas` converts the prefix rules into a FormID table
using xEdit. That's now optional rather than required: reach for it when a mod's
quests don't follow a naming pattern, or if EditorIDs turn out to be empty at
runtime after all.

FormIDs in the rules are load-order independent — the index byte is masked off
and light plugins are handled — so reordering doesn't invalidate the file.

## Building

**Plugin**

```
git submodule add https://github.com/libxse/commonlibf4 lib/commonlibf4
git submodule update --init --recursive
xmake build
```

Needs XMake 3.0+ and MSVC or Clang-CL with C++23. XMake fetches
`nlohmann_json`; spdlog arrives through CommonLibF4.

This project uses **XMake, not CMake**. The libxse fork ships no CMake config,
so `find_package(CommonLibF4)` cannot succeed. Set `XSE_FO4_MODS_PATH` or
`XSE_FO4_GAME_PATH` and `xmake install` deploys into a test setup.

**Panel**

```
cd swf
./build.ps1
```

Needs the Apache Flex SDK on PATH. The `-target-player=11.2 -swf-version=15`
flags are not optional — a SWF 16+ file loads as a black rectangle in-game with
no error anywhere.

**Pip-Boy** — see `docs/DataPage-injection.md`.

## Installing

```
Data\
  F4SE\Plugins\QuestLogSorter.dll
  F4SE\Plugins\QuestLogSorter\groups.json
  Interface\QuestLogSorter\QLS.swf
  Interface\Pipboy_DataPage.swf     <- your injected copy
```

Archive invalidation must be on. Runtime state (folds) goes to
`Documents\My Games\Fallout4\F4SE\QuestLogSorter\`, not Data, so it works under
MO2's VFS.

## Compatibility

- **FallUI - HUD** and **FallUI - Inventory**: no overlap. They replace
  `HUDMenu.swf` and the inventory menus. Load order between them doesn't matter.
- Anything else replacing `Pipboy_DataPage.swf`: mutually exclusive. Note this
  is *not* the file Pip-Boy retextures and cosmetic overhauls touch — those go
  for `PipboyMenu.swf` — so the conflict surface is small.
- Save-safe. No ESP, no scripts attached to anything, no baked FormIDs in the
  save. Uninstall by deleting the files.
- Requires F4SE and Address Library for F4SE Plugins.

## Controls

| Key | Action |
|---|---|
| ↑ ↓ / PgUp PgDn | move |
| ← → | fold / unfold |
| Space or click | toggle the row under the cursor |
| Enter or double-click | track / untrack the quest |
| M | track and jump to the map |
| Esc | clear the search box |

Groups where every quest is finished start collapsed; the player's fold choices
override that and persist.

## Things worth doing next

- Delete `SetQuestTracked` and its `setTracked` binding once tracking is
  confirmed working through `BGSExternalInterface` — the C++ path is dead code.
- Consider reusing `Shared.AS3::ListFilterer` instead of our own search — the
  vanilla inventory page already uses it, so behaviour would match.
- MCM page for `showFinished`, sort order and font size. MCM is already a FallUI
  dependency, so it's free to reach for.
- Per-questline icons from FallUI's Icon Library (ask m8r98a4f2 first — their
  permissions require it).

## License

GPL-3.0, inherited from CommonLibF4. Distributing the DLL obliges you to
distribute this source. See `NOTICE.md`.
