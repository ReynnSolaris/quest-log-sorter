# Injecting the panel into PipboyMenu.swf

This is the only manual step in the project, and the only part that can break
on a game update. Everything else is source you compile.

The plugin and `QLS.swf` don't care where they're mounted. The shim is what
knows about Bethesda's class names, so if a patch reshuffles the Pip-Boy, this
document is what you redo — not the C++ or the panel.

## Why it has to be done by hand

`PipboyMenu.swf` is Bethesda's compiled Flash. There's no supported extension
point, so a mod that wants to live inside the Pip-Boy either replaces that file
or injects into it. Nothing in the AS3 can be generated blind: you have to open
the real file and find the real class.

**Conflict warning:** any other mod that also replaces `PipboyMenu.swf` is
mutually exclusive with this one. FallUI - HUD (`HUDMenu.swf`) and FallUI -
Inventory (`ContainerMenu.swf`, `BarterMenu.swf`, `ExamineMenu.swf`) do **not**
touch it, so those are fine. Pip-Boy tab mods, holotape/radio UI replacers and
some map overhauls are not.

## 1. Get the original file

`PipboyMenu.swf` lives inside `Fallout4 - Interface.ba2`, not loose on disk.

- Extract with **B.A.E.** or Bethesda's **Archive2**.
- Copy it to `Data\Interface\PipboyMenu.swf`.
- Make sure archive invalidation is on, or the loose file is ignored.

Keep an untouched copy. You will want to diff against it.

## 2. Find the quest page class

Open the SWF in **JPEXS Free Flash Decompiler** and look under `scripts`.

There is no reliable public name to give you here — it has changed across
builds and I'd rather you find the real one than trust a guess. Identify it by
markers instead:

- Search all scripts for the string used by the QUESTS tab label or the
  localisation key next to it.
- Look for the class that owns the scrolling list on DATA → QUESTS: it will
  reference a Bethesda list component and have handlers for selection change
  and for setting the active quest.
- The set-active handler will call `ExternalInterface.call(...)` with a fixed
  string. **Write that string down** — it's how the vanilla list tells the game
  engine to track a quest, and it's a zero-C++ alternative to the plugin's
  `setTracked` if you'd rather go that way.

## 3. Add the shim

In JPEXS, add `qls/QLSShim.as` from `swf/src/qls/` as a new class
(`Add class` in the scripts tree, then paste). It compiles standalone — it has
no dependency on the rest of the panel source.

## 4. Call it

In the quest page class's constructor or init method, add:

```as3
QLSShim.attach(this, root, new flash.geom.Rectangle(x, y, w, h));
```

where the rectangle is where the vanilla quest list sits. Read those numbers
off the vanilla list's own `x`, `y`, `width`, `height` rather than eyeballing
them — the Pip-Boy renders to a texture, so anything you guess by looking at
your screen will be wrong.

Then hide the vanilla list so you don't get two lists stacked:

```as3
vanillaQuestList.visible = false;
```

Leaving it present-but-hidden is deliberate. The game still pushes data into
it, so nothing downstream breaks, and if the panel fails to load you can flip
one boolean to get the stock UI back.

## 5. Wire up "show on map"

Inside `QLSShim.attach`, the `QLS_showMap` hook is a deliberate no-op. Fill it
in with whatever `PipboyMenu` uses to switch pages — usually a page-index
setter on the tab bar you'll find near the class from step 2.

Until you do, pressing `M` still sets the quest as tracked (so the marker
appears); the player just switches to MAP themselves.

## 6. Save and test

Save the SWF from JPEXS to `Data\Interface\PipboyMenu.swf`, launch, and check
`Documents\My Games\Fallout4\F4SE\QuestLogSorter.log`. You want to see:

```
scaleform bound for movie 0x...
scanned N quests from M forms
```

If the first line is missing, F4SE isn't loading the DLL. If the second is
missing, the panel loaded but never called `getTree` — likely the shim didn't
find `f4se` on the root it was handed.

## Failure modes worth knowing

| Symptom | Cause |
|---|---|
| Panel never appears, no log errors | `QLS.swf` not at `Data\Interface\QuestLogSorter\QLS.swf`, or archive invalidation is off |
| Panel appears, empty, `plugin bridge missing` in log | `hostRoot` passed to `attach` isn't the movie root that has `f4se` on it |
| Text renders as blocks or nothing | `Style.FONT` doesn't match a font `PipboyMenu.swf` embeds — check the fonts node in JPEXS |
| Panel loads then the Pip-Boy goes black | SWF version mismatch — rebuild with `-swf-version=15 -target-player=11.2` |
| Quests appear but tracking does nothing | `Quest.SetActive` dispatch failing; see `Actions.cpp` and the log |
