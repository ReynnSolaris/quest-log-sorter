#pragma once

#include "PCH.h"
#include "Quests.h"

namespace QLS
{
	// The tree the UI renders:
	//   Section   "Main Game" / "Far Harbor" / "Nuka-World" / "<mod name>"
	//     Line    "Main Story" / "Brotherhood of Steel" / "Companion Quests"
	//       Quest -> objectives
	struct QuestLine
	{
		std::string name;
		int order{ 1000 };
		std::vector<QuestInfo> quests;
	};

	struct Section
	{
		std::string name;
		int order{ 1000 };
		std::vector<QuestLine> lines;
	};

	namespace Rules
	{
		// Reads Data\F4SE\Plugins\QuestLogSorter\groups.json. Safe to call again
		// to hot-reload; a malformed file leaves the previous rules in place.
		bool Load();

		// Groups a flat scan into the section/line tree, applying sort order and
		// dropping anything matched by the "hide" list.
		std::vector<Section> Build(std::vector<QuestInfo> a_quests);
	}
}
