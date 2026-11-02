# What changed in QuestsTab

`QuestsTab.patched.as` is the full class, ready to paste over the decompiled
original in JPEXS. Five changes, all additive — no vanilla line was altered.

| # | Location | Change |
|---|---|---|
| 1 | imports | `import qls.QLSShim;` |
| 2 | member vars | `private var _QLSAttached:Boolean = false;` |
| 3 | end of `redrawUIComponent` | `this.QLSUpdate();` |
| 4 | new method | `QLSUpdate()` — attaches once, hides and deafens the vanilla lists |
| 5 | end of `onPipboyChangeEvent` | `QLSShim.refresh();` |

## Why `redrawUIComponent` and not the constructor

The constructor's last two statements are the `__setProp_*` calls that
configure the lists. At that point `QuestsList_mc.x/y/width/height` are not
final, so bounds measured there are wrong. `redrawUIComponent` runs after
layout, which is why `QLSUpdate` lives there.

It also runs often, so `_QLSAttached` guards the load — otherwise every redraw
would trigger a fresh quest scan.

## Why the visibility line is where it is

Vanilla already assigns `ObjectivesList_mc.visible` inside
`redrawUIComponent`:

```as3
this.ObjectivesList_mc.visible = this.ObjectivesList_mc.entryList.length > 0;
```

`QLSUpdate()` runs *after* that, so our `false` wins. Reverse the order and the
vanilla list reappears whenever a quest has objectives.

## disableInput

`QLSUpdate` also sets `disableInput = true` on both lists. Hiding them isn't
enough on its own — `onPipboyChangeEvent` does `stage.focus =
this.QuestsList_mc`, so an invisible list would still eat arrow keys and fight
the tree for navigation. Every keypress would also fire
`onQuestSelectionChange`, reloading a Vault Boy animation nobody can see.

## What still works

The description pane, the Vault Boy animation, and the button hint bar are all
untouched. `SetQuestActive` / `ShowQuestOnMap` still run through the vanilla
methods when the shim calls them, so tracking sounds and map markers behave
exactly as stock.

## Known limitation

`Description_tf` and the Vault Boy follow `QuestsList_mc.selectedEntry`, which
no longer moves — the vanilla list's selection is frozen wherever
`onPipboyChangeEvent` left it. So the summary pane won't track what's
highlighted in the tree.

Fixing it means having the panel drive the vanilla selection: add a
`selectQuest(formID)` to `QLSShim` that sets `QuestsList_mc.selectedIndex` to
the matching `entryList` index, and call it from the panel's selection change.
Vanilla's own `onQuestSelectionChange` then updates the description and
animation for free. Worth doing once the tree itself is confirmed working —
not before, since it adds a second thing to debug.

## Crash on opening DATA — what caused it

The first version assigned hook functions onto the movie root:

```as3
hostRoot["QLS_setQuestActive"] = QLSShim.setQuestActive;
```

A movie root is an instance of a compiled document class, and AS3 classes are
**sealed** unless explicitly declared `dynamic`. Assigning an undeclared
property to a sealed instance throws `ReferenceError #1056`. Under Scaleform an
uncaught AS3 error takes the game down rather than surfacing as anything you
can catch or read — so the symptom is a CTD the moment DATA opens, with nothing
in any log.

Fixed by handing the panel a plain object literal instead. Object literals are
dynamic, so adding members to them is always safe:

```as3
var bridge:Object = {};
bridge["setQuestActive"] = QLSShim.setQuestActive;
bridge["showQuestOnMap"] = QLSShim.showQuestOnMap;
_panel["init"](_host, _w, _h, bridge);
```

The rule to carry forward: **never add a property to anything you didn't
create.** Vanilla objects are sealed.

### Everything is now wrapped

`QLSUpdate()` catches around its whole body, so any failure leaves the stock
quest page rather than crashing. `disableInput` sits in its own second block,
because that property may not exist on every build's `BSScrollingList` and a
throw there must not undo the visibility changes above it.

`QLSShim.attach`, both engine calls, and the `entryList` lookup are wrapped for
the same reason.

### The panel now finds f4se by walking up

`root` inside `QuestsTab` is `Pipboy_DataPage`'s own root, not the top-level
movie where F4SE registers `f4se.plugins`. The panel walks the parent chain
looking for it rather than assuming a level. If `getTree` reports
"plugin bridge missing", that walk failed and the depth limit or the property
path is what to check.
