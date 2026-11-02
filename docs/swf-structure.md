# How the Pip-Boy is actually put together

Findings from decompiling the shipped `PipboyMenu.swf` (SWF 15, ~41 KB
compressed, 48 AS3 classes, one `DoABC` block). Recorded here so nobody has to
rediscover it.

## PipboyMenu.swf is chrome, not content

It contains no quest page. Its classes are the frame around the pages:

```
PipboyMenu            extends Shared::IMenu
PipboyPage            extends PipboySubMenu extends Shared.AS3::BSUIComponent
Pipboy_Header         page/tab bar
Pipboy_BottomBar      HP / AP / level / limb condition
Pipboy_Meter          the meter widget
Pipboy_DataObj        the data model the game pushes into
Shared.AS3::BSScrollingList / BSScrollingListEntry
Shared.AS3::ListFilterer
Shared::BGSExternalInterface
Shared.AS3.COMPANIONAPP::PipboyLoader   extends flash.display::Loader
```

Exported library symbols are just `PipboyMenu`, `Pipboy_BottomBar`,
`Pipboy_Header`, `Pipboy_Meter`, `BB_DMGDRWidget`, the button hints, and
`MapPlaceholder`.

## The pages are separate SWFs

`PipboyLoader` pulls these in at runtime:

```
Pipboy_StatsPage.swf
Pipboy_InvPage.swf
Pipboy_DataPage.swf     <- DATA, which owns QUESTS
Pipboy_MapPage.swf
Pipboy_RadioPage.swf
```

**So the injection target is `Pipboy_DataPage.swf`, not `PipboyMenu.swf`.**

This is better than it sounds. `PipboyMenu.swf` is the file every Pip-Boy
cosmetic mod replaces; `Pipboy_DataPage.swf` is far less contested, so the
conflict surface is much smaller.

## What the shell tells us about the quest page

`PipboyMenu.swf` defines the linkage-ID constants the pages use, so the quest
UI's building blocks are named here even though the page itself is elsewhere:

| Constant | Symbol |
|---|---|
| `QUEST_ENTRY_LINKAGE_ID` | `QuestsListEntry` |
| `QUEST_RENDERER_LINKAGE_ID` | `QuestsItemRendererMc` |
| `QUEST_OBJECTIVES_ENTRY_LINKAGE_ID` | `ObjectivesListEntry` |
| `QUEST_OBJECTIVES_RENDERER_LINKAGE_ID` | `QuestsObjectivesItemRendererMc` |

So the vanilla page is two `BSScrollingList`s — a quest list and an objectives
list — not one combined control. That's why the stock UI can't show objectives
inline under each quest, and it's the thing our tree changes.

## The data model

`Pipboy_DataObj` has a `QuestsList` property (backed by `_QuestsList`),
alongside `SPECIALList`, `PerksList`, `WorkshopsList`, `WorldMapMarkers` and
friends. The game pushes quest data straight into it from C++.

Worth knowing: **the quest data already exists in AS3**, at
`root.DataObj.QuestsList`. Inspect its entries while you're in
`Pipboy_DataPage.swf` — if they carry a FormID, you have a second, independent
source of quest state, and cross-checking it against what our plugin reports is
the fastest way to confirm the flag-bit constants in `Quests.cpp`.

It is *not* a replacement for the plugin: it has no source plugin, no EditorID,
and no way to group by questline. But it is a useful oracle.

## Useful plumbing already present

- `Shared.AS3::ListFilterer` — a filter with `EntryMatchesFilter`,
  `GetNextFilterMatch`, `IsFilterEmpty`. The inventory page uses it via
  `InvFilter`. If you'd rather not keep our own search implementation, this is
  the vanilla equivalent.
- `Shared.AS3::BSScrollingList` dispatches `selectionChange`, `itemPress`,
  `listPress`, `listItemsCreated`.
- `Pipboy_Header` dispatches `PageClicked` and `TabClicked`, and `PipboyMenu`
  has `onNewPage` / `onNewTab` handlers. **That is the hook for "show on map"** —
  wire `QLS_showMap` to the same path `PageClicked` takes.
- `Shared::BGSExternalInterface` is the C++ bridge. The call name that sets the
  active quest will be in `Pipboy_DataPage.swf`, invoked through this class.

## Reproducing this

No special tooling needed — the SWF is zlib-compressed after an 8-byte header:

```python
import zlib
raw = open('PipboyMenu.swf','rb').read()
body = zlib.decompress(raw[8:])     # 'CWS' = compressed
```

Then walk the tag list for `DoABC` (82) and `SymbolClass` (76), and read the
ABC constant pool's string table. JPEXS does all this with a GUI, but a
50-line parser is enough to answer "which class is this in".
