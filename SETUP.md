# Setup guide

Zero to a working install. Budget an afternoon the first time — most of it is
one-time toolchain setup, and step 7 is the only part that needs patience.

Read this straight through once before starting. Step 7 is manual work against
a file you have to extract yourself, and knowing that up front changes how you
approach the rest.

---

## 0. What you need

| Tool | Why | Where |
|---|---|---|
| XMake 3.0.0+ | build system | xmake.io |
| Visual Studio 2022 Build Tools (C++ workload) or Clang-CL | C++23 compiler | microsoft.com |
| CommonLibF4 (libxse fork) | F4SE reverse-engineered API | github.com/libxse/commonlibf4 |
| Apache Flex SDK 4.16 | compiles the AS3 panel | apache.org — needs a JDK on PATH |
| JPEXS Free Flash Decompiler | edits `Pipboy_DataPage.swf` | github.com/jindrapetrik/jpexs-decompiler |
| B.A.E. or Archive2 | extracts `Pipboy_DataPage.swf` from the game archives | Nexus / Creation Kit |
| FO4Edit (xEdit) | generates grouping rules | Nexus |
| F4SE + Address Library for F4SE Plugins | required at runtime | f4se.silverlock.org / Nexus |

**No CMake and no vcpkg.** The libxse fork of CommonLibF4 is XMake-only — it
ships an `xmake.lua` and no CMake config, so `find_package(CommonLibF4)` fails
regardless of what you set `CMAKE_PREFIX_PATH` to. XMake also handles package
fetching, so vcpkg isn't in the picture either.

---

## 1. Lay out the source

Unzip anywhere outside your game folder. You should have:

```
QuestLogSorter/
├── xmake.lua             build config
├── README.md
├── SETUP.md              this file
├── NOTICE.md             GPL obligations — read before publishing
├── src/                  F4SE plugin (C++23)
│   ├── PCH.h
│   ├── Plugin.cpp        entry point, logging, paths
│   ├── Quests.h/.cpp     walks TESQuest forms
│   ├── Grouping.h/.cpp   groups.json → section/questline tree
│   ├── Bridge.h/.cpp     native functions exposed to AS3
│   └── Actions.cpp       set active quest
├── lib/                  CommonLibF4 submodule lands here
├── swf/
│   ├── build.ps1
│   └── src/
│       ├── Main.as       document class
│       └── qls/
│           ├── QuestLogPanel.as   the tree
│           ├── RowView.as         one pooled row
│           ├── Style.as           colours, metrics, font
│           └── QLSShim.as         paste-into-PipboyMenu glue
├── data/                 mirrors the player's Data folder
├── tools/QLS_GenerateGroups.pas
└── docs/DataPage-injection.md
```

`data/` mirrors what ends up in the player's `Data` folder. Build artifacts
land in it, then `xmake install` or a zip turns it into an installable mod.

---

## 2. Get CommonLibF4

```
cd QuestLogSorter
git init
git submodule add https://github.com/libxse/commonlibf4 lib/commonlibf4
git submodule update --init --recursive
```

Two details that will bite you if you improvise:

- **The path is `lib/commonlibf4`.** `xmake.lua` does
  `includes("lib/commonlibf4")`. On Windows the case won't matter, but the
  `lib/` vs `extern/` part will.
- **`--recursive` is not optional.** CommonLibF4 pulls in `commonlib-shared`
  as its own submodule, and that's where the `commonlibf4.plugin` build rule
  is defined. Skip it and xmake reports an unknown rule rather than a missing
  directory, which is a confusing way to find out.

Not using git? Download both repos as zips and place `commonlib-shared` inside
`lib/commonlibf4/lib/`. The submodule route is much less fiddly.

---

## 3. Build the plugin

```
xmake build
```

First run prompts to download `nlohmann_json` — say yes. Output goes to
`build/windows/`.

To deploy on install, set one of these environment variables (the plugin rule
reads them):

- `XSE_FO4_MODS_PATH` — your mod manager's mods folder
- `XSE_FO4_GAME_PATH` — your Fallout 4 install folder

then `xmake install`.

For a Visual Studio solution: `xmake project -k vsxmake`. For clangd:
`xmake project -k compile_commands`.

### Expect the first build to fail

The code targets the API as documented, but CommonLibF4 is a moving
reverse-engineering effort. In rough order of likelihood:

Already fixed in this source (listed so you recognise them if you refactor):

| Error | Cause |
|---|---|
| `'Scaleform': symbol to the left of '::' must be a type` | Scaleform is a **top-level** namespace in this fork, not `RE::Scaleform`. The library's own `xmake.lua` exposes `include/(Scaleform/**.h)` separately from `include/(RE/**.h)`. |
| `'log_directory' is not a member of 'F4SE'` | this fork has no `F4SE::log` helper; `Plugin.cpp` resolves the folder with `SHGetKnownFolderPath` instead |
| `'info' is not a member of 'spdlog'` | `<spdlog/spdlog.h>` was missing — the sink header alone doesn't declare the free functions |
| `Register(...)` argument mismatch | signature is `Register(std::string_view name, RegisterCallback*)` — name **first**, the reverse of CommonLibSSE |
| `no operator '/' ... 'const std::string_view'` | `std::filesystem::path::operator/` doesn't resolve for `string_view` on MSVC; `PLUGIN_NAME` is now `const char*` |

Still possible, in rough order of likelihood:

| Error near | What to check |
|---|---|
| `a_obj->displayText.c_str()` in `Quests.cpp` | `BGSLocalizedString`'s accessor — the one call not verified against a header |
| duplicate `F4SEPlugin_Version` | you added one back — the plugin rule generates it |

Note `RE::FormType` doesn't exist in this fork — form types are
`RE::ENUM_FORM_ID`, e.g. `RE::ENUM_FORM_ID::kQUST`. Worth knowing before you
write anything new against form types.

### If quest status looks wrong

The three flag bits in `Quests.cpp` (`kCompleted`, `kFailed`, `kActive`) come
from the shared Bethesda quest-flag layout, not from anything in the headers,
so they're the last unverified assumption in the scanner. If completed quests
show as active or tracking looks wrong, set `kLogRawFlags = true` in the
`adapter` block, run once, and compare the logged values against a quest whose
real state you know:

```
0001CB0B flags=0x0803 type=1 stage=200 "The Molecular Level"
```

`0x0803` there is start-game-enabled + completed + active. Adjust the constants
to match what you see and rebuild.

### Quest tracking lives in AS3, not here

`Actions.cpp` is a stub on purpose. Decompiling `Pipboy_DataPage.swf` settled
how the vanilla UI tracks a quest:

```as3
Shared::BGSExternalInterface.call("SetQuestActive", <formID>);
Shared::BGSExternalInterface.call("ShowQuestOnMap", <formID>);
```

Both are reachable straight from AS3, so the panel calls them directly through
the shim's `QLS_engineCall` hook. That's the same code path the stock list
uses — no C++, nothing to break on a game update, and "show on map" works too.

The C++ `SetQuestTracked` remains only as a fallback for anyone whose
CommonLibF4 exposes `RE::TESQuest::SetActive`:

```lua
add_defines("QLS_HAS_NATIVE_SETACTIVE")
```

Once tracking works through the shim, delete it and the `setTracked` binding
in `Bridge.cpp`.

`xmake.lua` declares `mode.debug` and `mode.releasedbg`. With no mode
configured xmake defaults to `release`, so your output lands in
`build\windows\x64\release\` — that's fine and it links. If you ever do hit
link errors that look like missing symbols, a mode mismatch against
CommonLibF4's own build is the first suspect; `xmake f -m releasedbg` settles
it.

`tools/package.ps1` searches all of `build\` and doesn't care which mode you
used.

---

## 4. Build the panel

Install the Flex SDK, put its `bin/` on PATH, confirm `mxmlc -version` works.

```
cd swf
.\build.ps1
```

Output: `data/Interface/QuestLogSorter/QLS.swf`.

The `-target-player=11.2 -swf-version=15` flags in `build.ps1` are not
negotiable. Fallout 4's Scaleform runtime is Flash 11.2 / SWF 15; a SWF 16+
file loads as a black rectangle with no error message anywhere, which is a
miserable thing to debug.

**Read the compiler output, don't trust the summary line.** Some Flex SDK
builds print AS3 errors and still exit 0, leaving the previous `QLS.swf` in
place — so a failed build looks like a successful one until the game loads a
SWF several edits out of date. `build.ps1` deletes the output first and checks
that a file actually appeared, but if you ever see errors scroll past, treat
the build as failed regardless of what the last line says.

---

## 5. Generate grouping rules

Sections (Main Game / Far Harbor / a mod) come from the plugin a quest is
defined in. Questlines (Minutemen / Brotherhood / Companions) come from
EditorID prefixes in `groups.json`.

Good news: unlike Skyrim, Fallout 4 keeps EditorIDs at runtime for quests —
`TESQuest` carries `formEditorID` as a real member — so the shipped prefix
rules fire directly and cover the base game and DLC with no extra work.

**This step is therefore optional.** Run it when a quest lands in the wrong
group: mod-added quests with unusual naming, or base-game quests whose EditorID
doesn't match any prefix. It emits a FormID-keyed `byForm` table that takes
precedence over the prefix rules.

1. Open FO4Edit with your full load order.
2. Copy `tools/QLS_GenerateGroups.pas` into FO4Edit's `Edit Scripts` folder.
3. Right-click any plugin → **Apply Script** → `QLS_GenerateGroups`.
4. It writes `Data\F4SE\Plugins\QuestLogSorter\groups.generated.json`.
5. Copy the `"byForm"` block from it into `groups.json` under `"lines"`,
   replacing the empty `byForm` there.

Keep the hand-written `sections`, `order` and `byPrefix` — the generated file
only supplies `byForm`.

Re-run whenever you add a quest mod. Skipping it isn't fatal: quests fall
through to type-based grouping and land in broader buckets.

FormIDs written out are load-order independent (index byte masked off, light
plugins handled), so reordering your load order doesn't invalidate the file.

---

## 6. Do this before touching JPEXS

Run steps 3–5 first and confirm the DLL loads. Launch through
`f4se_loader.exe` and check
`Documents\My Games\Fallout4\F4SE\QuestLogSorter.log` for:

```
QuestLogSorter loading (runtime 1.10.163.0)
scaleform bound for movie 0x...
loaded 7 sections, 214 form rules, 25 prefix rules
QuestLogSorter loaded
```

You'll see `scaleform bound` even with no panel installed, because F4SE binds
to every menu movie. That's the point: it proves the native half works before
you spend an hour in a decompiler. Debugging both halves at once is how people
give up on this.

---

## 7. Inject into Pipboy_DataPage.swf

**The target is `Pipboy_DataPage.swf`, not `PipboyMenu.swf`.** `PipboyMenu.swf`
is only the chrome — header, bottom bar, meters, page loader — and contains no
quest page at all. The five pages are separate SWFs it loads at runtime. See
`docs/swf-structure.md`.

Full walkthrough in `docs/DataPage-injection.md`. Short version:

1. Extract `Pipboy_DataPage.swf` from `Fallout4 - Interface.ba2` with B.A.E.
2. Keep an untouched copy for diffing.
3. Open in JPEXS, find the class extending `PipboyPage` that references
   `QUEST_ENTRY_LINKAGE_ID` / `QuestsItemRendererMc`.
4. Add `swf/src/qls/QLSShim.as` as a new class (it compiles standalone).
5. Call `QLSShim.attach(this, root, bounds)` in the page's init, using the
   union of the two vanilla lists' bounds, then set both lists' `visible` to
   false.
6. Save to `Data\Interface\Pipboy_DataPage.swf`.

Note the vanilla page uses **two** `BSScrollingList`s — one for quests, one for
objectives. That split is why the stock UI can't nest objectives under quests.

Three things to write down while you're in there:

- the `ExternalInterface.call(...)` string the page uses to set the active
  quest — that finishes `Actions.cpp` with no C++ at all
- the bounds of both lists
- the field names on a `DataObj.QuestsList` entry. The vanilla quest data is
  already in AS3, so if entries carry a FormID you have an independent way to
  check the plugin's output

**Conflict:** anything else replacing `Pipboy_DataPage.swf`. This is *not* the
file Pip-Boy cosmetic mods touch — those replace `PipboyMenu.swf` — so the
conflict surface is much smaller than expected. FallUI - HUD and FallUI -
Inventory are unaffected.

## 8. Install

Final layout in `Data` (or an MO2 mod folder):

```
Data/
├── F4SE/Plugins/
│   ├── QuestLogSorter.dll                 step 3
│   └── QuestLogSorter/groups.json         step 5
├── Interface/
│   ├── QuestLogSorter/QLS.swf             step 4
│   └── Pipboy_DataPage.swf                step 7
```

Archive invalidation must be on, or loose `Interface` files are ignored
entirely and you get vanilla behaviour with no error.

Runtime state (which groups you folded) goes to
`Documents\My Games\Fallout4\F4SE\QuestLogSorter\`, deliberately not `Data`,
so it works under MO2's virtual filesystem.

---

## 9. Troubleshooting

| Symptom | Cause |
|---|---|
| `find_package(CommonLibF4)` error | you're on old CMake files — this project is xmake now |
| `unknown rule: commonlibf4.plugin` | submodules not cloned recursively; `commonlib-shared` is missing |
| `unknown target(commonlib-shared)` | same cause — CommonLibF4's own submodule is an empty folder. A GitHub ZIP download does this silently. |
| No log at all | F4SE isn't loading the DLL — check F4SE matches your game version, read `f4se.log` |
| Log stops after `loading` | registration failed; check the return values in `Plugin.cpp` |
| `0 sections` | `groups.json` not found — it resolves relative to the game root; check MO2 mapping |
| Panel never appears, no errors | `QLS.swf` not at `Data\Interface\QuestLogSorter\QLS.swf`, or archive invalidation is off |
| Panel appears but empty | `plugin bridge missing` in the log → wrong `hostRoot` passed to `attach` |
| Text renders as blocks | `Style.FONT` doesn't match an embedded font — `$MAIN_Font` appears in `PipboyMenu.swf`; check what the data page embeds |
| Pip-Boy goes black on open | SWF version mismatch; rebuild with the flags in `build.ps1` |
| Tracking does nothing | shim's `QLS_engineCall` not wired, or the argument shape differs — check `QuestsTab.onToggleActivate` in JPEXS |
| Everything lands in "Other" | `byForm` rules missing — step 5 skipped, or pasted into the wrong place |
| Two quest lists stacked | vanilla list not hidden in step 7 |

---

## 10. Dev loop

Once it works, iterating is fast — the slow parts don't repeat.

- **C++ change** → `xmake build`, restart the game.
- **AS3 change** → `.\build.ps1`, restart the game. No JPEXS needed: the shim
  loads `QLS.swf` at runtime, so the panel is a normal file swap.
- **grouping change** → edit `groups.json`, call `reloadRules()` or reopen the
  Pip-Boy.
- **PipboyMenu change** → JPEXS again. Which is why the shim is deliberately
  thin: you should almost never need to go back in there.

Keep `QuestLogSorter.log` open in a tailing editor. Every failure path writes
to it, and `qls.log()` is exposed to AS3 so the panel can too.

---

## 11. Packaging for release

```
.\tools\package.ps1
.\tools\package.ps1 -Version 1.1.0 -IncludeDataPage
```

Produces `dist\QuestLogSorter-<version>.zip`, ready for Vortex, MO2 or manual
install, and prints the file list so you can eyeball it before uploading.

### Why not `xmake install`

`xmake install` is for dropping a build into your own test setup, not for
making a distributable. Use it with an env var set:

```
setx XSE_FO4_MODS_PATH "D:\Vortex Mods\fallout4"
setx XSE_FO4_GAME_PATH "D:\Steam\steamapps\common\Fallout 4"
```

Open a new terminal afterwards — `setx` doesn't affect the current one. Without
either variable xmake falls back to a generic default and prints

```
warning: please use `xmake install -o installdir` ...
```

which means it installed somewhere harmless and useless. `xmake install -o
<dir>` works too.

### The archive layout Vortex expects

Vortex installs a Fallout 4 mod by copying the archive's contents into `Data`,
so the archive is rooted at Data's **contents**:

```
QuestLogSorter-1.0.0.zip
├── F4SE/Plugins/QuestLogSorter.dll
├── F4SE/Plugins/QuestLogSorter/groups.json
├── Interface/QuestLogSorter/QLS.swf
├── Interface/Pipboy_DataPage.swf     (only with -IncludeDataPage)
└── README.txt
```

No wrapping `Data\` folder. Include one and Vortex either flags the archive as
unrecognised or deploys everything a directory too deep — which presents as
"the mod does nothing", with no error anywhere.

### Vortex specifics

- **F4SE cannot be installed by Vortex.** It goes in the game root manually,
  and the game must be launched via `f4se_loader.exe`. Vortex can be pointed at
  that loader as the run target.
- **Enable archive invalidation** in Vortex (Fallout 4's mod page has the
  toggle). Without it every loose file under `Interface\` is ignored.
- **This mod will not appear in the Plugins tab.** There's no ESP, so there's
  nothing to sort. That's expected, not a failed install.
- **Deployment method matters for the DLL.** Hardlink deployment is fine.
  Symlink deployment has historically confused F4SE plugin loading for some
  people; if the DLL doesn't load under Vortex but works when copied manually,
  that's the first thing to change.
- `Pipboy_DataPage.swf` conflicts with any other mod that replaces it. Vortex
  will raise a file conflict and ask you to order them — there's no correct
  order, they're genuinely incompatible.

### Publishing

Requirements to list: F4SE, Address Library for F4SE Plugins.

**Read `NOTICE.md` first.** Linking CommonLibF4 puts the plugin under GPL-3.0,
so shipping the DLL obliges you to ship this source. A public repo link on the
mod page is how people normally satisfy that.

Say plainly on the description page that this replaces `Pipboy_DataPage.swf`
and conflicts with anything else that does — that's the support question you'd
otherwise answer fifty times.

### Consider shipping without the SWF at first

`-IncludeDataPage` is opt-in for a reason. `Pipboy_DataPage.swf` is a modified
Bethesda asset, it's the single largest source of conflicts, and it has to be
rebuilt against each game update. Releasing the plugin plus `QLS.swf` and
letting people patch their own copy is a smaller commitment — though obviously
far fewer people will bother.
