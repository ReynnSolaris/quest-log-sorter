#pragma once

#include "PCH.h"

namespace QLS
{
	enum class QuestStatus : std::uint8_t
	{
		kRunning = 0,
		kCompleted = 1,
		kFailed = 2
	};

	struct ObjectiveInfo
	{
		std::uint32_t index{ 0 };
		std::string text;
		bool displayed{ false };
		bool completed{ false };
		bool failed{ false };
	};

	struct QuestInfo
	{
		std::uint32_t formID{ 0 };
		std::string editorID;   // usually empty at runtime in release builds - see Grouping.h
		std::string name;       // localized FULL name
		std::string sourceFile; // "Fallout4.esm", "DLCCoast.esm", "MyMod.esp"
		std::uint8_t type{ 0 }; // QUEST_DATA::Type - see typeNames in groups.json
		std::uint16_t stage{ 0 };
		QuestStatus status{ QuestStatus::kRunning };
		bool tracked{ false };  // is this the player's active quest
		std::vector<ObjectiveInfo> objectives;
	};

	struct ScanOptions
	{
		bool includeFinished{ true };
		bool includeUnnamed{ false };   // quests with no FULL name (dialogue/system quests)
		bool includeNeverStarted{ false };
	};

	// Walks every TESQuest in the load order and returns the ones the Pip-Boy
	// would plausibly show. Cheap enough to call on menu open (~400 forms in a
	// heavy load order); do not call per frame.
	std::vector<QuestInfo> ScanQuests(const ScanOptions& a_opts);

	// Resolve a quest by FormID. Returns nullptr if it is not loaded.
	RE::TESQuest* LookupQuest(std::uint32_t a_formID);
}
