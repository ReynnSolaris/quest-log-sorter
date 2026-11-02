#include "Bridge.h"

#include "Grouping.h"
#include "Quests.h"

using json = nlohmann::json;
namespace GFx = Scaleform::GFx;

namespace QLS
{
	namespace State
	{
		namespace
		{
			std::unordered_map<std::string, bool> g_collapsed;
			bool g_dirty{ false };

			std::filesystem::path StatePath()
			{
				return UserDataDir() / "collapse-state.json";
			}
		}

		void Load()
		{
			std::ifstream file{ StatePath() };
			if (!file) {
				return;
			}
			try {
				const auto parsed = json::parse(file);
				for (const auto& [key, value] : parsed.items()) {
					g_collapsed[key] = value.get<bool>();
				}
			} catch (const std::exception& a_ex) {
				QLS_WARN("could not read collapse state: {}", a_ex.what());
			}
		}

		void Save()
		{
			if (!g_dirty) {
				return;
			}
			try {
				std::error_code ec;
				std::filesystem::create_directories(UserDataDir(), ec);
				json out = json::object();
				for (const auto& [key, value] : g_collapsed) {
					out[key] = value;
				}
				std::ofstream file{ StatePath() };
				file << out.dump(1, '\t');
				g_dirty = false;
			} catch (const std::exception& a_ex) {
				QLS_WARN("could not write collapse state: {}", a_ex.what());
			}
		}

		bool IsCollapsed(const std::string& a_key, bool a_default)
		{
			const auto it = g_collapsed.find(a_key);
			return it == g_collapsed.end() ? a_default : it->second;
		}

		void SetCollapsed(const std::string& a_key, bool a_collapsed)
		{
			g_collapsed[a_key] = a_collapsed;
			g_dirty = true;
		}
	}

	namespace
	{
		// --- argument helpers ------------------------------------------------
		// AS3 numbers arrive as int, uint or number depending on the value, so
		// never assume which. GetNumber() asserts if the type is wrong.

		bool ArgBool(const GFx::Value& a_value, bool a_default = false)
		{
			if (a_value.IsBoolean()) {
				return a_value.GetBoolean();
			}
			if (a_value.IsInt()) {
				return a_value.GetInt() != 0;
			}
			if (a_value.IsUInt()) {
				return a_value.GetUInt() != 0;
			}
			if (a_value.IsNumber()) {
				return a_value.GetNumber() != 0.0;
			}
			return a_default;
		}

		double ArgNumber(const GFx::Value& a_value, double a_default = 0.0)
		{
			if (a_value.IsNumber()) {
				return a_value.GetNumber();
			}
			if (a_value.IsInt()) {
				return static_cast<double>(a_value.GetInt());
			}
			if (a_value.IsUInt()) {
				return static_cast<double>(a_value.GetUInt());
			}
			return a_default;
		}

		std::string ArgString(const GFx::Value& a_value)
		{
			if (a_value.IsString()) {
				const auto* str = a_value.GetString();
				return str ? std::string{ str } : std::string{};
			}
			return {};
		}

		// GFx::Value holds a const char* WITHOUT taking ownership - assigning
		// a local string's c_str() leaves a dangling pointer the moment Call
		// returns. This buffer keeps the last returned string alive. Scaleform
		// calls come in on the main thread, so a single static is enough.
		std::string& ReturnBuffer()
		{
			static std::string buffer;
			return buffer;
		}

		void ReturnString(GFx::Value* a_retVal, std::string a_text)
		{
			auto& buffer = ReturnBuffer();
			buffer = std::move(a_text);
			*a_retVal = buffer.c_str();
		}

		// --- tree serialisation ----------------------------------------------
		// The whole tree crosses the boundary once, as JSON, and AS3 calls
		// JSON.parse on it. Flash 11 has native JSON, so this is one marshalling
		// hop instead of a few thousand CreateObject/SetMember calls - and it
		// avoids the lifetime problem above entirely.

		std::string LowerCopy(std::string a_text)
		{
			std::transform(a_text.begin(), a_text.end(), a_text.begin(),
				[](unsigned char a_c) { return static_cast<char>(std::tolower(a_c)); });
			return a_text;
		}

		std::string CollapseKey(const std::string& a_section, const std::string& a_line = {})
		{
			return a_line.empty() ? a_section : a_section + "/" + a_line;
		}

		json QuestToJson(const QuestInfo& a_quest)
		{
			json objectives = json::array();
			auto haystack = LowerCopy(a_quest.name);

			for (const auto& obj : a_quest.objectives) {
				objectives.push_back({
					{ "index", obj.index },
					{ "text", obj.text },
					{ "completed", obj.completed },
					{ "failed", obj.failed },
				});
				haystack += " " + LowerCopy(obj.text);
			}

			return {
				{ "formID", a_quest.formID },
				{ "name", a_quest.name },
				{ "editorID", a_quest.editorID },
				{ "source", a_quest.sourceFile },
				{ "stage", a_quest.stage },
				{ "status", static_cast<int>(a_quest.status) },
				{ "tracked", a_quest.tracked },
				{ "objectives", objectives },
				// pre-lowercased so the search box does not lowercase every
				// row on every keystroke
				{ "search", haystack },
			};
		}

		std::string TreeToJson(const std::vector<Section>& a_sections)
		{
			json root = json::array();

			for (const auto& section : a_sections) {
				json lines = json::array();
				int openCount = 0;

				for (const auto& line : section.lines) {
					const auto key = CollapseKey(section.name, line.name);

					// A group where everything is finished starts folded, unless
					// the player has said otherwise.
					const auto allFinished = std::all_of(
						line.quests.begin(), line.quests.end(),
						[](const QuestInfo& a_quest) {
							return a_quest.status != QuestStatus::kRunning;
						});

					json quests = json::array();
					for (const auto& quest : line.quests) {
						quests.push_back(QuestToJson(quest));
						if (quest.status == QuestStatus::kRunning) {
							++openCount;
						}
					}

					lines.push_back({
						{ "name", line.name },
						{ "key", key },
						{ "collapsed", State::IsCollapsed(key, allFinished) },
						{ "total", line.quests.size() },
						{ "quests", quests },
					});
				}

				const auto sectionKey = CollapseKey(section.name);
				root.push_back({
					{ "name", section.name },
					{ "key", sectionKey },
					{ "collapsed", State::IsCollapsed(sectionKey, false) },
					{ "open", openCount },
					{ "lines", lines },
				});
			}

			return root.dump();
		}

		// --- native functions --------------------------------------------------
		// Note the signature: Call takes a *const* Params&.

		class GetTree : public GFx::FunctionHandler
		{
		public:
			void Call(const Params& a_params) override
			{
				ScanOptions opts{};
				if (a_params.argCount > 0) {
					opts.includeFinished = ArgBool(a_params.args[0], true);
				}
				const auto tree = Rules::Build(ScanQuests(opts));
				ReturnString(a_params.retVal, TreeToJson(tree));
			}
		};

		class SetTracked : public GFx::FunctionHandler
		{
		public:
			void Call(const Params& a_params) override
			{
				if (a_params.argCount < 1) {
					*a_params.retVal = false;
					return;
				}
				const auto formID = static_cast<std::uint32_t>(ArgNumber(a_params.args[0]));
				const auto tracked = a_params.argCount > 1 ? ArgBool(a_params.args[1], true) : true;
				*a_params.retVal = SetQuestTracked(formID, tracked);
			}
		};

		class SetCollapsed : public GFx::FunctionHandler
		{
		public:
			void Call(const Params& a_params) override
			{
				if (a_params.argCount < 2) {
					return;
				}
				State::SetCollapsed(ArgString(a_params.args[0]), ArgBool(a_params.args[1]));
			}
		};

		class FlushState : public GFx::FunctionHandler
		{
		public:
			void Call(const Params&) override { State::Save(); }
		};

		class ReloadRules : public GFx::FunctionHandler
		{
		public:
			void Call(const Params& a_params) override
			{
				*a_params.retVal = Rules::Load();
			}
		};

		class Log : public GFx::FunctionHandler
		{
		public:
			void Call(const Params& a_params) override
			{
				if (a_params.argCount > 0) {
					QLS_LOG("[as3] {}", ArgString(a_params.args[0]));
				}
			}
		};

		template <class T>
		void Bind(GFx::Movie* a_movie, GFx::Value* a_root, const char* a_name)
		{
			GFx::Value fn;
			a_movie->CreateFunction(&fn, new T{});
			a_root->SetMember(a_name, fn);
		}
	}

	bool RegisterScaleform(GFx::Movie* a_movie, GFx::Value* a_root)
	{
		Bind<GetTree>(a_movie, a_root, "getTree");
		Bind<SetTracked>(a_movie, a_root, "setTracked");
		Bind<SetCollapsed>(a_movie, a_root, "setCollapsed");
		Bind<FlushState>(a_movie, a_root, "flushState");
		Bind<ReloadRules>(a_movie, a_root, "reloadRules");
		Bind<Log>(a_movie, a_root, "log");

		a_root->SetMember("version", GFx::Value{ 1.0 });
		QLS_LOG("scaleform bound for movie {}", static_cast<const void*>(a_movie));
		return true;
	}
}
