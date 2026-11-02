#include "Bridge.h"

#include "Quests.h"

// ---------------------------------------------------------------------------
// "Make this the player's active/tracked quest."
//
// This is a stub, and it should stay one. Decompiling Pipboy_DataPage.swf
// settled how the vanilla UI does it: QuestsTab talks to the engine through
//
//     Shared::BGSExternalInterface.call("SetQuestActive", <formID>)
//     Shared::BGSExternalInterface.call("ShowQuestOnMap", <formID>)
//
// Those are reachable straight from AS3. Calling them from the panel is
// strictly better than anything this file could do:
//
//   - no C++, no reverse engineering, nothing to break on a game update
//   - identical to the stock UI, because it *is* the stock code path
//   - "show on map" comes free, which the plugin never had a route to
//
// So the intended end state is that the panel calls BGSExternalInterface and
// this function is deleted along with the setTracked binding in Bridge.cpp.
// See docs/DataPage-injection.md.
//
// For the record, the Papyrus VM path that used to live here is a dead end in
// CommonLibF4: GetObjectHandlePolicy returns a reference not a pointer, there
// is no RE::VMTypeID, no RE::FormType (form types are RE::ENUM_FORM_ID), no
// IVirtualMachine::BindObject and no RE::MakeFunctionArguments. Five APIs to
// reverse engineer to do what one string does. Don't.
//
// If your CommonLibF4 does expose RE::TESQuest::SetActive, defining
// QLS_HAS_NATIVE_SETACTIVE gives you a working native path in the meantime.
// ---------------------------------------------------------------------------

namespace QLS
{
	bool SetQuestTracked([[maybe_unused]] std::uint32_t a_formID,
		[[maybe_unused]] bool a_tracked)
	{
#ifdef QLS_HAS_NATIVE_SETACTIVE
		auto* quest = LookupQuest(a_formID);
		if (!quest) {
			QLS_WARN("quest {:08X} is not loaded", a_formID);
			return false;
		}
		quest->SetActive(a_tracked);
		return true;
#else
		static bool warned = false;
		if (!warned) {
			warned = true;
			QLS_WARN("setTracked called, but tracking belongs in AS3 - "
					 "use BGSExternalInterface.call(\"SetQuestActive\", formID)");
		}
		return false;
#endif
	}
}
