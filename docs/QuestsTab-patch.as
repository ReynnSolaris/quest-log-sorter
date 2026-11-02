// ---------------------------------------------------------------------------
// QuestsTab edits, for Pipboy_DataPage.swf
//
// This is NOT a drop-in replacement class. It shows the three edits to make in
// JPEXS against the real QuestsTab, with the surrounding vanilla code included
// so you can find your place. Everything marked [QLS] is new; everything else
// is what is already there.
//
// All vanilla code below was read out of the shipped bytecode, not guessed.
// ---------------------------------------------------------------------------


// === EDIT 1: the constructor ==============================================
//
// The vanilla constructor ends like this (last four statements):
//
//     this._Quest_VaultBoy_LoadPending = true;
//     this._DescText = "";
//     this.__setProp_ObjectivesList_mc_QuestsTab_Objectives_0();
//     this.__setProp_QuestsList_mc_QuestsTab_Quests_0();
//
// Do NOT attach here. The lists exist but have not been laid out yet, so
// their bounds are wrong. Use redrawUIComponent instead - see EDIT 2.


// === EDIT 2: redrawUIComponent ============================================
//
// Vanilla starts with `super.redrawUIComponent();` then rescales the Vault Boy
// movie into VaultBoyHolder_mc. Append the attach at the end of the method,
// after the Vault Boy work, so the lists have been sized.

override protected function redrawUIComponent() : void
{
    super.redrawUIComponent();

    // ... vanilla Vault Boy scaling / VaultBoyHolder_mc.addChild(...) ...

    // [QLS] ------------------------------------------------------------
    // Attach once, then just refresh. The union of the two lists is the
    // space our tree takes over; Description_tf and VaultBoyHolder_mc are
    // left alone, so the summary pane keeps working.
    //
    // Plain numbers rather than a Rectangle: fewer imports for JPEXS to
    // resolve, and one less thing to go wrong in its AS3 compiler.
    var qlsTop:Number = Math.min(this.QuestsList_mc.y, this.ObjectivesList_mc.y);
    QLSShim.attach(
        this,
        root,
        Math.min(this.QuestsList_mc.x, this.ObjectivesList_mc.x),
        qlsTop,
        Math.max(this.QuestsList_mc.width, this.ObjectivesList_mc.width),
        (this.ObjectivesList_mc.y + this.ObjectivesList_mc.height) - qlsTop);

    this.QuestsList_mc.visible = false;
    this.ObjectivesList_mc.visible = false;
    // [/QLS] -----------------------------------------------------------
}

// Needs, at the top of the file:
//     import qls.QLSShim;
//
// If JPEXS refuses the import, use the fully qualified name inline instead:
//     qls.QLSShim.attach(this, root, ...);


// === EDIT 3: refresh when data changes ====================================
//
// The game pushes new quest data through onPipboyChangeEvent. Vanilla repaints
// the lists there; we need the tree to re-read too, otherwise it goes stale
// after a quest updates while the Pip-Boy is open.

override public function onPipboyChangeEvent(event:PipboyChangeEvent) : void
{
    // ... vanilla body ...

    QLSShim.refresh();   // [QLS]
}


// ---------------------------------------------------------------------------
// JPEXS gotchas, learned the hard way
//
// JPEXS's AS3 compiler is a subset of ASC. Two things reject code that mxmlc
// accepts without comment:
//
//   1. Dotted access on an untyped object gets resolved at COMPILE time, even
//      though Object is dynamic. If the member name collides with anything
//      package-internal in the SWF you get:
//
//          Property init has package internal access in Object on line N
//
//      `init` collides. Use brackets - obj["init"](...) - which skips name
//      resolution and behaves identically at runtime. QLSShim.as does this
//      throughout; do the same in anything you add.
//
//   2. Closures, `for each`, getters and default parameters are all risky.
//      Plain while-loops and explicit arguments compile reliably.
//
// Workflow: Add script -> qls.QLSShim -> Existing DoABC tag. Select the stub,
// click Edit under the source pane, accept the experimental warning, paste,
// Save. Then edit QuestsTab. Then File -> Save as for the SWF itself - script
// saves alone do not write the file.
// ---------------------------------------------------------------------------


// ---------------------------------------------------------------------------
// REFERENCE: the vanilla engine calls, decompiled
//
// These are why QLSShim looks the way it does. The two actions are NOT
// symmetrical, which is the thing that catches people out.
// ---------------------------------------------------------------------------

// --- onQuestPress (vanilla) ---
// SetQuestActive is handed the ENTRY OBJECT, not a formID.
//
//     if (this._ObjectivesListActive) {
//         this.onObjectivePress();
//     } else if (this.QuestsList_mc.selectedEntry.enabled) {
//         if (this.QuestsList_mc.selectedEntry.formID == 0) {
//             this.onRightThumbstickInput(2);
//         } else {
//             BGSExternalInterface.call(this.codeObj, "SetQuestActive",
//                 this.QuestsList_mc.selectedEntry);
//             BGSExternalInterface.call(this.codeObj, "PlaySound",
//                 this.QuestsList_mc.selectedEntry.active
//                     ? "UIPipBoyQuestInactive" : "UIPipBoyQuestActive");
//         }
//     }
//
// Note `formID == 0` means a category header, not a quest - it routes to the
// thumbstick handler instead. Our tree has real section rows, so we never
// hit that case, but it confirms 0 is not a valid quest formID.

// --- onShowOnMap (vanilla) ---
// ShowQuestOnMap is handed the FORMID.
//
//     if (this.QuestsList_mc.selectedIndex != -1) {
//         if ((this._ObjectivesListActive && !this.ObjectivesList_mc.selectedEntry.active)
//          || (!this._ObjectivesListActive && !this.QuestsList_mc.selectedEntry.active)) {
//             this.onQuestPress();          // track it first
//         }
//         if (this.QuestsList_mc.selectedEntry.formID == 0
//          && this.ObjectivesList_mc.selectedIndex != -1) {
//             BGSExternalInterface.call(this.codeObj, "ShowQuestOnMap",
//                 this.ObjectivesList_mc.selectedEntry.formID);
//         } else {
//             BGSExternalInterface.call(this.codeObj, "ShowQuestOnMap",
//                 this.QuestsList_mc.selectedEntry.formID);
//         }
//     }
//
// Show-on-map tracks the quest first if it is not already active. QLSShim
// does not replicate that - press Enter then M, or add the extra call.

// --- onToggleActivate (vanilla) ---
// Empty. `returnvoid` and nothing else. The $ToggleActive button hint is wired
// to it in the constructor, but the actual work happens in onQuestPress via
// ProcessUserEvent. Don't hook onToggleActivate expecting it to do anything.

// --- codeObj ---
// A getter on PipboySubMenu returning PipboySubMenu::BGSCodeObj. QuestsTab
// inherits it. That is the first argument to every BGSExternalInterface.call.
