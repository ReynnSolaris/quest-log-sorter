#include "Quests.h"

namespace QLS
{
	// =====================================================================
	// CommonLibF4 adapter
	//
	// TESQuest in this fork exposes only SetStage and GetAliasedRef - none of
	// the IsRunning/IsCompleted/IsActive helpers Skyrim modders expect. Status
	// lives in the flag bits of QUEST_DATA:
	//
	//   class QUEST_DATA {
	//       float         questDelayTime;  // 00
	//       std::uint16_t flags;           // 04
	//       std::int8_t   priority;        // 06
	//       std::int8_t   questType;       // 07
	//   };
	//
	// Every engine-specific access in this file goes through this block. If
	// something reads wrong in game, the fix is here and nowhere else.
	// =====================================================================
	namespace adapter
	{
		// Set true to dump raw flags for every quest to the log on the first
		// scan. Do that once, compare against a quest you know is completed or
		// tracked, and you can confirm the constants below in a single run.
		inline constexpr bool kLogRawFlags = false;

		// QUST \ DNAM flag bits.
		enum QuestFlag : std::uint16_t
		{
			kStartGameEnabled = 1 << 0,
			kCompleted = 1 << 1,
			kAddIdleTopicToHello = 1 << 2,
			kAllowRepeatedStages = 1 << 3,
			kStartsEnabled = 1 << 4,
			kDisplayed = 1 << 5,
			kFailed = 1 << 6,
			kStageWait = 1 << 7,
			kWarnOnAliasFillFailure = 1 << 8,
			kActive = 1 << 9,  // the player's tracked quest
			kRepeatsConditions = 1 << 10,
			kKeepInstance = 1 << 11,
			kWantDormant = 1 << 12
		};

		inline std::uint16_t Flags(RE::TESQuest* a_quest)
		{
			return a_quest->data.flags;
		}

		inline bool HasFlag(RE::TESQuest* a_quest, std::uint16_t a_flag)
		{
			return (Flags(a_quest) & a_flag) != 0;
		}

		inline bool IsCompleted(RE::TESQuest* a_quest)
		{
			return HasFlag(a_quest, kCompleted);
		}

		inline bool IsFailed(RE::TESQuest* a_quest)
		{
			return HasFlag(a_quest, kFailed);
		}

		// Is this the *tracked* quest - the one with the map marker - rather
		// than merely a quest that happens to be running.
		inline bool IsTracked(RE::TESQuest* a_quest)
		{
			return HasFlag(a_quest, kActive);
		}

		// Reached a stage, or finished one way or the other.
		inline bool HasStarted(RE::TESQuest* a_quest)
		{
			return a_quest->currentStage > 0 || IsCompleted(a_quest) || IsFailed(a_quest);
		}

		inline bool IsRunning(RE::TESQuest* a_quest)
		{
			return HasStarted(a_quest) && !IsCompleted(a_quest) && !IsFailed(a_quest);
		}

		// QUST \ DNAM \ Type. Grouping fallback only, so a wrong value here is
		// cosmetic rather than broken.
		inline std::uint8_t QuestType(RE::TESQuest* a_quest)
		{
			return static_cast<std::uint8_t>(a_quest->data.questType);
		}

		// Fallout 4 keeps quest EditorIDs at runtime - TESQuest has a real
		// BSString formEditorID member, unlike Skyrim where they are stripped.
		// That means the EditorID prefix rules in groups.json actually fire.
		inline const char* EditorID(RE::TESQuest* a_quest)
		{
			return a_quest->GetFormEditorID();
		}

		// BGSQuestObjective::state is a plain char, so a straight cast is right.
		inline std::uint32_t ObjectiveState(RE::BGSQuestObjective* a_obj)
		{
			return static_cast<std::uint32_t>(static_cast<unsigned char>(a_obj->state));
		}

		// displayText is a BGSLocalizedString. If this line does not compile,
		// open RE\B\BGSLocalizedString.h - the accessor is c_str(), GetString()
		// or an implicit conversion. This is the only call in the project not
		// verified against a header.
		inline std::string ObjectiveText(RE::BGSQuestObjective* a_obj)
		{
			const auto* text = a_obj->displayText.c_str();
			return text ? std::string{ text } : std::string{};
		}
	}

	namespace
	{
		// QUEST_OBJECTIVE_STATE bit flags.
		constexpr std::uint32_t kObjDisplayed = 0x01;
		constexpr std::uint32_t kObjCompleted = 0x02;
		constexpr std::uint32_t kObjFailed = 0x04;
		constexpr std::uint32_t kObjDormant = 0x08;

		std::string SafeString(const char* a_str)
		{
			return a_str ? std::string{ a_str } : std::string{};
		}

		std::string SourceFileOf(RE::TESForm* a_form)
		{
			// GetFile(0) is the *defining* file, not the last overriding plugin.
			// A quest defined in DLCCoast.esm and tweaked by a patch still
			// belongs to Far Harbor.
			if (auto* file = a_form->GetFile(0); file) {
				return std::string{ file->GetFilename() };
			}
			return "Fallout4.esm";
		}

		void ReadObjectives(RE::TESQuest* a_quest, QuestInfo& a_out)
		{
			for (auto* obj : a_quest->objectives) {
				if (!obj) {
					continue;
				}

				const auto raw = adapter::ObjectiveState(obj);
				if (raw & kObjDormant) {
					continue;
				}

				ObjectiveInfo info{};
				info.index = obj->index;
				info.text = adapter::ObjectiveText(obj);
				info.displayed = (raw & kObjDisplayed) != 0;
				info.completed = (raw & kObjCompleted) != 0;
				info.failed = (raw & kObjFailed) != 0;

				// An objective the player has never seen is noise. Completed and
				// failed ones stay, so a finished quest still reads as history.
				if (!info.displayed && !info.completed && !info.failed) {
					continue;
				}
				if (info.text.empty()) {
					continue;
				}

				a_out.objectives.push_back(std::move(info));
			}

			std::stable_sort(
				a_out.objectives.begin(), a_out.objectives.end(),
				[](const ObjectiveInfo& a_lhs, const ObjectiveInfo& a_rhs) {
					// Open objectives float up, then original order.
					const auto lhsDone = a_lhs.completed || a_lhs.failed;
					const auto rhsDone = a_rhs.completed || a_rhs.failed;
					if (lhsDone != rhsDone) {
						return !lhsDone;
					}
					return a_lhs.index < a_rhs.index;
				});
		}

		QuestStatus StatusOf(RE::TESQuest* a_quest)
		{
			if (adapter::IsCompleted(a_quest)) {
				return QuestStatus::kCompleted;
			}
			if (adapter::IsFailed(a_quest)) {
				return QuestStatus::kFailed;
			}
			return QuestStatus::kRunning;
		}
	}

	RE::TESQuest* LookupQuest(std::uint32_t a_formID)
	{
		auto* form = RE::TESForm::GetFormByID(a_formID);
		return form ? form->As<RE::TESQuest>() : nullptr;
	}

	std::vector<QuestInfo> ScanQuests(const ScanOptions& a_opts)
	{
		std::vector<QuestInfo> out;

		auto* handler = RE::TESDataHandler::GetSingleton();
		if (!handler) {
			QLS_ERR("no TESDataHandler - scanning too early?");
			return out;
		}

		const auto& forms = handler->GetFormArray<RE::TESQuest>();
		out.reserve(forms.size() / 4);

		for (auto* quest : forms) {
			if (!quest) {
				continue;
			}

			QuestInfo info{};
			info.name = SafeString(quest->GetFullName());

			if (info.name.empty() && !a_opts.includeUnnamed) {
				continue;  // dialogue/system quests
			}
			if (!adapter::HasStarted(quest) && !a_opts.includeNeverStarted) {
				continue;
			}

			info.formID = quest->GetFormID();
			info.editorID = SafeString(adapter::EditorID(quest));
			info.sourceFile = SourceFileOf(quest);
			info.type = adapter::QuestType(quest);
			info.stage = quest->currentStage;
			info.tracked = adapter::IsTracked(quest);
			info.status = StatusOf(quest);

			ReadObjectives(quest, info);

			if (info.status != QuestStatus::kRunning && !a_opts.includeFinished) {
				continue;
			}

			// A running quest with nothing to show is a script holder.
			if (info.objectives.empty() && info.status == QuestStatus::kRunning) {
				continue;
			}

			if constexpr (adapter::kLogRawFlags) {
				QLS_LOG("{:08X} flags={:#06x} type={} stage={} \"{}\" [{}]",
					info.formID, adapter::Flags(quest), info.type, info.stage,
					info.name, info.editorID);
			}

			out.push_back(std::move(info));
		}

		QLS_LOG("scanned {} quests from {} forms", out.size(), forms.size());
		return out;
	}
}
