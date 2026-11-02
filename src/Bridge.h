#pragma once

#include "PCH.h"

namespace QLS
{
	// Registered with F4SE's Scaleform interface. Everything we expose lands on
	//   root1.f4se.plugins.QuestLogSorter
	// which is what the AS3 panel talks to.
	bool RegisterScaleform(Scaleform::GFx::Movie* a_movie, Scaleform::GFx::Value* a_root);

	// Collapse state, persisted to My Games so it survives a restart.
	namespace State
	{
		void Load();
		void Save();
		bool IsCollapsed(const std::string& a_key, bool a_default);
		void SetCollapsed(const std::string& a_key, bool a_collapsed);
	}

	// Makes a_formID the player's active/tracked quest. Returns false if the
	// quest is not loaded or the VM refused the call.
	bool SetQuestTracked(std::uint32_t a_formID, bool a_tracked);
}
