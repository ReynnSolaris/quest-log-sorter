# Injecting the panel into Pipboy_DataPage.swf

Everything below was read out of the shipped `Pipboy_DataPage.swf` (SWF 15,
~50 KB, 60 AS3 classes), so the names are real, not guesses.

## The target

```
Pipboy_DataPage  extends PipboyPage
  QuestsTab      extends PipboyTab   <- this one
  StatsTab       extends PipboyTab
  WorkshopsTab   extends PipboyTab
```

`QuestsTab` is the class to modify. Its relevant members:

| Member | What it is |
|---|---|
| `QuestsList_mc` | the quest list (`QuestsList extends BSScrollingList`) |
| `ObjectivesList_mc` | the objectives list (`ObjectivesList extends BSScrollingList`) |
| `Description_tf` | quest description text field |
| `VaultBoyHolder_mc`, `Quest_VaultBoyLoader`, `Quest_DefaultBoy_mc` | the summary Vault Boy animation |
| `ShowOnMapButton`, `ShowSummaryButton`, `NavigateObjectivesButton`, `ToggleActiveButton` | button-hint entries |
| `_ObjectivesListActive`, `_ShowingSummary`, `_DefaultObjectivesListTop` | UI state |

Handlers you'll care about: `onQuestSelectionChange`, `onQuestPress`,
`onShowOnMap`, `onToggleActivate`, `refreshObjectiveList`,
`updateQuestDescription`, `redrawUIComponent`.

## The engine calls (this is the important part)

`QuestsTab` talks to the game through `Shared::BGSExternalInterface.call(...)`.
Read out of the bytecode, not guessed:

```as3
// onQuestPress - takes the ENTRY OBJECT
BGSExternalInterface.call(codeObj, "SetQuestActive", QuestsList_mc.selectedEntry);
BGSExternalInterface.call(codeObj, "PlaySound", "UIPipBoyQuestActive");

// onShowOnMap - takes the FORMID
BGSExternalInterface.call(codeObj, "ShowQuestOnMap", QuestsList_mc.selectedEntry.formID);
```

Three things that will catch you out:

1. **Three arguments, `codeObj` first.** It's a getter on `PipboySubMenu`
   returning `BGSCodeObj`, inherited by `QuestsTab`.
2. **The two calls are not symmetrical.** `SetQuestActive` wants the whole list
   entry; `ShowQuestOnMap` wants a bare numeric formID. Passing a formID to
   `SetQuestActive` does nothing at all.
3. **`onToggleActivate` is empty** — `returnvoid` and nothing else. The
   `$ToggleActive` button hint points at it, but the real work happens in
   `onQuestPress` via `ProcessUserEvent`. Don't hook it.

`QLSShim` handles all of this: it takes the tab so it can reach `codeObj`, and
maps a formID back to the entry object via `QuestsList_mc.entryList`.

Also worth knowing: `formID == 0` marks a category header row in the vanilla
list, routed to `onRightThumbstickInput(2)` instead of being tracked. Our tree
has real section rows so it never comes up, but it confirms 0 is never a valid
quest.

`docs/QuestsTab-patch.as` has the three edits with vanilla context around them.

## The data model

`Pipboy_DataObj.QuestsList` is already populated in AS3, and entries carry
`formID`. Other fields present in this SWF's string table and used by the quest
UI: `text`, `description`, `active`, `complete`, `enabled`, `type`, `sortval`,
`instance`, `swfFile` (the Vault Boy animation), `Alert`, `Increasing`.

Two consequences:

- **You have an oracle.** Compare `DataObj.QuestsList` entries against what the
  plugin reports for the same formID. That's the fastest way to confirm the
  quest flag bits in `Quests.cpp` — an entry's `active` and `complete` are the
  game's own answer.
- **A plugin-free version is possible** but not worth it: the vanilla data has
  no source plugin and no EditorID, so it can't group by DLC or questline. That
  grouping is the whole point of this mod.

Note `sortval` and the `sortOn` / `DESCENDING` / `NUMERIC` strings — the vanilla
list already sorts on a numeric key the game supplies.

## Steps

1. Extract `Pipboy_DataPage.swf` from `Fallout4 - Interface.ba2` with B.A.E. or
   Archive2, drop it at `Data\Interface\Pipboy_DataPage.swf`, keep a pristine
   copy for diffing. Archive invalidation must be on.
2. Open in JPEXS, find `QuestsTab` under `scripts`.
3. Add `swf/src/qls/QLSShim.as` as a new class (it compiles standalone).
4. In `QuestsTab`, after the lists are set up — `redrawUIComponent` or the
   constructor — add:

   ```as3
   QLSShim.attach(this, root, new flash.geom.Rectangle(x, y, w, h));
   ```

   Use the union of `QuestsList_mc` and `ObjectivesList_mc` bounds; our tree
   shows both together. Read the numbers off those objects rather than
   measuring on screen — the Pip-Boy renders to a texture.
5. Hide the vanilla lists:

   ```as3
   QuestsList_mc.visible = false;
   ObjectivesList_mc.visible = false;
   ```

   Hidden rather than removed: the game keeps pushing data into them, so
   nothing downstream breaks, and one boolean gets the stock UI back.
6. Wire `QLS_showMap` in the shim to call `onShowOnMap`, or directly to
   `BGSExternalInterface.call("ShowQuestOnMap", formID)`.
7. Save to `Data\Interface\Pipboy_DataPage.swf`.

## Decide what to do about the summary panel

`Description_tf` and the Vault Boy holder sit alongside the lists. Our tree
doesn't replace them, so you can leave them alone and keep the description
pane — in which case size the panel to the two lists only, not the whole tab.
That's the less invasive option and probably the better one.

## Conflicts

Mutually exclusive with anything else replacing `Pipboy_DataPage.swf`. This is
**not** the file Pip-Boy retextures and cosmetic overhauls touch — those replace
`PipboyMenu.swf` — so the conflict surface is small.

FallUI - HUD and FallUI - Inventory are unaffected.

## Failure modes

| Symptom | Cause |
|---|---|
| Panel never appears, no errors | `QLS.swf` not at `Data\Interface\QuestLogSorter\QLS.swf`, or archive invalidation off |
| `plugin bridge missing` in the log | `hostRoot` isn't the movie root carrying `f4se`. The data page is a loaded child, so its own `root` may be the page — pass the menu root |
| Text renders as blocks | `Style.FONT` doesn't match an embedded font; check the fonts node in JPEXS (`$MAIN_Font` is used by the shell) |
| Page goes black | SWF version mismatch — rebuild with `-swf-version=15 -target-player=11.2` |
| Two lists stacked | vanilla lists not hidden |
