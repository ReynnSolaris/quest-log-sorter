# Bisecting a crash on opening DATA

An uncaught AS3 error inside Scaleform takes the game down instead of surfacing
anywhere, so a crash with an empty log means "something threw", not "something
is broken in a specific way". These steps narrow it in two launches.

## What has already been ruled out

Verified by decompiling the patched `Pipboy_DataPage.swf` and reading its
bytecode:

- `qls::QLSShim` is present and correctly compiled
- `QuestsTab::QLSUpdate` has the `root` null-check and its try/catch
- `onLoaded` builds the bridge object with bracket assignment as intended
- the plugin loads: `f4se.log` shows *loaded correctly (handle 1)*

So the injection is sound. The crash is in what happens after `attach`.

## Test 1 — is it the Loader, or what the Loader loads?

In `QLSShim`, break the path:

```as3
private static const SWF_PATH:String = "QuestLogSorter/NOPE.swf";
```

Re-save the SWF, open DATA.

- **No crash** (empty quest area, `onLoadError` fires) → the crash is inside
  `QLS.swf`. Go to test 2.
- **Still crashes** → the crash is in the `Loader` call itself, before our
  content runs. The fix is `LoaderContext` — see below.

## Test 2 — which part of the panel?

If test 1 cleared the Loader, restore the path and stub out the panel: in
`Main.as`, make `init()` a no-op that does nothing but store its arguments,
and rebuild `QLS.swf`.

- **No crash** → the crash is in `QuestLogPanel` — drawing, text, or the
  native call. Re-enable `setSize` first, then `refresh`, to split it further.
- **Still crashes** → it is the act of adding the loaded content to the display
  list, which points at a SWF-version or embedding mismatch.

## Known Scaleform hazards, now avoided

Both of these were in the first build and are fixed:

**Bare `Loader.load()`.** Vanilla never does this. `QuestsTab.updateQuestAnimation`
always passes `new LoaderContext(false, ApplicationDomain.currentDomain)`.
Scaleform's loader appears to need it, and failing without it faults in native
code rather than raising a catchable `IOError`.

**`scrollRect`.** Scaleform's AS3 support for it is unreliable. The panel now
clips with a `Shape` mask, which is core Flash and always supported.

**`antiAliasType = "advanced"`.** Removed; another Scaleform unknown for no
real benefit.

## If the log is missing entirely

`InitLog` now falls back to the game root when Documents cannot be resolved,
and flushes on every line so a crash cannot swallow buffered output. If
`QuestLogSorter.log` is in neither `Documents\My Games\Fallout4\F4SE\` nor the
game folder, the DLL is not the one that loaded — check for a stale copy.

The first line records where the log ended up:

```
log opened at C:\...\QuestLogSorter.log
```
