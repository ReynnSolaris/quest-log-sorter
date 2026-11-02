# Licensing notice

Read this before you publish a build.

CommonLibF4 is **GPL-3.0-or-later**, with a modding exception and a GPL linking
exception. The practical consequence, in the library's own words: if you link
your mod against CommonLibF4 and distribute the binaries, you must also
distribute the source code under the same license, along with the source for
any other libraries you link against — excluding Fallout 4 itself and F4SE,
which the exceptions carve out.

So for this project:

- `QuestLogSorter.dll` links CommonLibF4 → **the plugin source is GPL-3.0**.
  Publishing the DLL on Nexus means publishing this source too (a public repo
  link on the mod page is the normal way people satisfy this).
- `xmake.lua` declares `set_license("GPL-3.0")` to reflect that.
- The AS3 panel doesn't link CommonLibF4 and isn't derived from it. You could
  license `swf/` separately if you wanted, but keeping the whole repo under one
  license is simpler and avoids arguments.
- `PipboyMenu.swf` is a modified Bethesda asset and isn't yours to license
  either way. Redistributing it is standard practice for UI mods, but it's not
  covered by the GPL grant — it's a separate, tolerated-by-convention thing.

If you'd rather not GPL your work, the alternative is not using CommonLibF4 —
you'd write against the F4SE SDK directly, which is considerably more work and
loses the Address Library integration.

The full text is in `lib/commonlibf4/LICENSE` and `lib/commonlibf4/EXCEPTIONS`
once the submodule is cloned. The FSF's GPL FAQ is worth reading if any of this
is load-bearing for you.

I'm not a lawyer and this isn't legal advice — it's a summary of what the
library's README states, so you know the obligation exists before you're
committed to it.
