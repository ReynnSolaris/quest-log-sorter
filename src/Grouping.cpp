#include "Grouping.h"

using json = nlohmann::json;

namespace QLS::Rules
{
	namespace
	{
		struct PrefixRule
		{
			std::string prefix;
			std::string line;
			int order{ 1000 };
		};

		struct RuleSet
		{
			// file name (lowercased) -> display name / order
			std::unordered_map<std::string, std::pair<std::string, int>> sections;
			// "file.esm|001CB0B" (lowercased file, local FormID hex, no padding) -> line
			std::unordered_map<std::string, std::string> lineByForm;
			// longest-prefix-wins over EditorID
			std::vector<PrefixRule> lineByPrefix;
			// QUEST_DATA::Type -> line
			std::unordered_map<int, std::string> lineByType;
			std::unordered_map<std::string, int> lineOrder;
			std::unordered_set<std::string> hiddenForms;
			std::vector<std::string> hiddenPrefixes;
			std::string fallbackLine{ "Other" };
			int defaultSectionOrder{ 500 };
		};

		RuleSet g_rules;
		bool g_loaded{ false };

		std::string Lower(std::string a_str)
		{
			std::transform(a_str.begin(), a_str.end(), a_str.begin(), [](unsigned char a_c) {
				return static_cast<char>(std::tolower(a_c));
			});
			return a_str;
		}

		// Strip the load-order byte so keys stay stable no matter where the
		// plugin sits. Light plugins (FE xxx yyy) keep only the low 12 bits.
		std::uint32_t LocalFormID(std::uint32_t a_formID)
		{
			if ((a_formID & 0xFF000000u) == 0xFE000000u) {
				return a_formID & 0x00000FFFu;
			}
			return a_formID & 0x00FFFFFFu;
		}

		std::string FormKey(const QuestInfo& a_quest)
		{
			char buf[16]{};
			std::snprintf(buf, sizeof(buf), "%06X", LocalFormID(a_quest.formID));
			return Lower(a_quest.sourceFile) + "|" + buf;
		}

		std::string ParseHexOr(const std::string& a_str, std::uint32_t a_fallback)
		{
			(void)a_fallback;
			// Accept "0x0001CB0B", "0001CB0B" or "1CB0B" - normalise to 6 digits.
			auto s = a_str;
			if (s.rfind("0x", 0) == 0 || s.rfind("0X", 0) == 0) {
				s = s.substr(2);
			}
			const auto value = static_cast<std::uint32_t>(std::strtoul(s.c_str(), nullptr, 16));
			char buf[16]{};
			std::snprintf(buf, sizeof(buf), "%06X", LocalFormID(value));
			return buf;
		}

		bool StartsWith(std::string_view a_haystack, std::string_view a_needle)
		{
			return a_haystack.size() >= a_needle.size() &&
			       a_haystack.compare(0, a_needle.size(), a_needle) == 0;
		}

		void ParseSections(const json& a_json, RuleSet& a_out)
		{
			for (const auto& entry : a_json) {
				const auto file = Lower(entry.value("file", ""s));
				if (file.empty()) {
					continue;
				}
				a_out.sections[file] = {
					entry.value("name", file),
					entry.value("order", 500)
				};
			}
		}

		void ParseLines(const json& a_json, RuleSet& a_out)
		{
			if (a_json.contains("byForm")) {
				for (const auto& [file, forms] : a_json.at("byForm").items()) {
					for (const auto& [formID, line] : forms.items()) {
						a_out.lineByForm[Lower(file) + "|" + ParseHexOr(formID, 0)] =
							line.get<std::string>();
					}
				}
			}

			if (a_json.contains("byPrefix")) {
				for (const auto& entry : a_json.at("byPrefix")) {
					PrefixRule rule{};
					rule.prefix = Lower(entry.value("prefix", ""s));
					rule.line = entry.value("line", ""s);
					rule.order = entry.value("order", 1000);
					if (!rule.prefix.empty() && !rule.line.empty()) {
						a_out.lineByPrefix.push_back(std::move(rule));
					}
				}
				// Longest prefix first so "DLC03MQ" beats "DLC03".
				std::sort(
					a_out.lineByPrefix.begin(), a_out.lineByPrefix.end(),
					[](const PrefixRule& a_lhs, const PrefixRule& a_rhs) {
						return a_lhs.prefix.size() > a_rhs.prefix.size();
					});
			}

			if (a_json.contains("byType")) {
				for (const auto& [type, line] : a_json.at("byType").items()) {
					a_out.lineByType[std::stoi(type)] = line.get<std::string>();
				}
			}

			if (a_json.contains("order")) {
				for (const auto& [line, order] : a_json.at("order").items()) {
					a_out.lineOrder[line] = order.get<int>();
				}
			}
		}

		void ParseHidden(const json& a_json, RuleSet& a_out)
		{
			if (a_json.contains("byPrefix")) {
				for (const auto& entry : a_json.at("byPrefix")) {
					a_out.hiddenPrefixes.push_back(Lower(entry.get<std::string>()));
				}
			}
			if (a_json.contains("byForm")) {
				for (const auto& [file, forms] : a_json.at("byForm").items()) {
					for (const auto& formID : forms) {
						a_out.hiddenForms.insert(
							Lower(file) + "|" + ParseHexOr(formID.get<std::string>(), 0));
					}
				}
			}
		}

		bool IsHidden(const QuestInfo& a_quest, const RuleSet& a_rules)
		{
			if (a_rules.hiddenForms.contains(FormKey(a_quest))) {
				return true;
			}
			if (a_quest.editorID.empty()) {
				return false;
			}
			const auto edid = Lower(a_quest.editorID);
			for (const auto& prefix : a_rules.hiddenPrefixes) {
				if (StartsWith(edid, prefix)) {
					return true;
				}
			}
			return false;
		}

		std::string ResolveLine(const QuestInfo& a_quest, const RuleSet& a_rules)
		{
			// 1. Exact FormID match. This is the only rule that works when the
			//    runtime has stripped EditorIDs, which is why the xEdit generator
			//    emits FormID rules rather than prefixes.
			if (auto it = a_rules.lineByForm.find(FormKey(a_quest));
			    it != a_rules.lineByForm.end()) {
				return it->second;
			}

			// 2. EditorID prefix, longest match wins.
			if (!a_quest.editorID.empty()) {
				const auto edid = Lower(a_quest.editorID);
				for (const auto& rule : a_rules.lineByPrefix) {
					if (StartsWith(edid, rule.prefix)) {
						return rule.line;
					}
				}
			}

			// 3. Quest type from the record.
			if (auto it = a_rules.lineByType.find(static_cast<int>(a_quest.type));
			    it != a_rules.lineByType.end()) {
				return it->second;
			}

			return a_rules.fallbackLine;
		}

		std::pair<std::string, int> ResolveSection(const QuestInfo& a_quest, const RuleSet& a_rules)
		{
			if (auto it = a_rules.sections.find(Lower(a_quest.sourceFile));
			    it != a_rules.sections.end()) {
				return it->second;
			}
			// Unknown plugin: use the file name itself so mod quests still land
			// in a sane bucket instead of being dumped into the main game.
			return { a_quest.sourceFile, a_rules.defaultSectionOrder };
		}

		int LineOrder(const std::string& a_line, const RuleSet& a_rules)
		{
			if (auto it = a_rules.lineOrder.find(a_line); it != a_rules.lineOrder.end()) {
				return it->second;
			}
			for (const auto& rule : a_rules.lineByPrefix) {
				if (rule.line == a_line) {
					return rule.order;
				}
			}
			return 1000;
		}
	}

	bool Load()
	{
		const auto path = ModDataDir() / "groups.json";
		std::ifstream file{ path };
		if (!file) {
			QLS_WARN("no groups.json at {} - falling back to quest type grouping",
				path.string());
			g_loaded = true;
			return false;
		}

		try {
			const auto parsed = json::parse(file, nullptr, true, true);  // allow comments

			RuleSet fresh{};
			if (parsed.contains("sections")) {
				ParseSections(parsed.at("sections"), fresh);
			}
			if (parsed.contains("lines")) {
				ParseLines(parsed.at("lines"), fresh);
			}
			if (parsed.contains("hide")) {
				ParseHidden(parsed.at("hide"), fresh);
			}
			fresh.fallbackLine = parsed.value("fallbackLine", "Other"s);
			fresh.defaultSectionOrder = parsed.value("defaultSectionOrder", 500);

			g_rules = std::move(fresh);
			g_loaded = true;
			QLS_LOG("loaded {} sections, {} form rules, {} prefix rules",
				g_rules.sections.size(), g_rules.lineByForm.size(),
				g_rules.lineByPrefix.size());
			return true;
		} catch (const std::exception& a_ex) {
			QLS_ERR("groups.json is malformed ({}) - keeping previous rules", a_ex.what());
			return false;
		}
	}

	std::vector<Section> Build(std::vector<QuestInfo> a_quests)
	{
		if (!g_loaded) {
			Load();
		}

		// section name -> line name -> quests
		std::map<std::string, std::map<std::string, QuestLine>> buckets;
		std::unordered_map<std::string, int> sectionOrders;

		for (auto& quest : a_quests) {
			if (IsHidden(quest, g_rules)) {
				continue;
			}

			auto [sectionName, sectionOrder] = ResolveSection(quest, g_rules);
			auto lineName = ResolveLine(quest, g_rules);

			sectionOrders[sectionName] = sectionOrder;

			auto& line = buckets[sectionName][lineName];
			if (line.name.empty()) {
				line.name = lineName;
				line.order = LineOrder(lineName, g_rules);
			}
			line.quests.push_back(std::move(quest));
		}

		std::vector<Section> out;
		out.reserve(buckets.size());

		for (auto& [sectionName, lines] : buckets) {
			Section section{};
			section.name = sectionName;
			section.order = sectionOrders[sectionName];

			for (auto& [lineName, line] : lines) {
				std::sort(
					line.quests.begin(), line.quests.end(),
					[](const QuestInfo& a_lhs, const QuestInfo& a_rhs) {
						if (a_lhs.tracked != a_rhs.tracked) {
							return a_lhs.tracked;
						}
						if (a_lhs.status != a_rhs.status) {
							return a_lhs.status < a_rhs.status;  // running first
						}
						return a_lhs.name < a_rhs.name;
					});
				section.lines.push_back(std::move(line));
			}

			std::sort(
				section.lines.begin(), section.lines.end(),
				[](const QuestLine& a_lhs, const QuestLine& a_rhs) {
					if (a_lhs.order != a_rhs.order) {
						return a_lhs.order < a_rhs.order;
					}
					return a_lhs.name < a_rhs.name;
				});

			out.push_back(std::move(section));
		}

		std::sort(out.begin(), out.end(), [](const Section& a_lhs, const Section& a_rhs) {
			if (a_lhs.order != a_rhs.order) {
				return a_lhs.order < a_rhs.order;
			}
			return a_lhs.name < a_rhs.name;
		});

		return out;
	}
}
