#pragma once

#include <algorithm>
#include <cstdint>
#include <filesystem>
#include <format>
#include <fstream>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <F4SE/F4SE.h>
#include <RE/Fallout.h>

#include <nlohmann/json.hpp>

// spdlog.h declares spdlog::info / error / set_default_logger / set_pattern.
// Including only basic_file_sink.h gets you the sink type and nothing else,
// which produces a wall of "is not a member of 'spdlog'" errors.
#include <spdlog/spdlog.h>
#include <spdlog/sinks/basic_file_sink.h>

using namespace std::literals;

namespace QLS
{
	// const char* rather than string_view: std::filesystem::path's operator/
	// does not resolve for string_view on MSVC, and this builds paths.
	inline constexpr auto PLUGIN_NAME = "QuestLogSorter";

	// root1.f4se.plugins.QuestLogSorter
	inline constexpr auto SCALEFORM_KEY = "QuestLogSorter"sv;

	// Writable runtime state (collapse folds, log). Data\ is often read-only
	// under MO2's VFS, so this lives in My Games instead.
	std::filesystem::path UserDataDir();

	// Data\F4SE\Plugins\QuestLogSorter\ - read-only config shipped with the mod.
	std::filesystem::path ModDataDir();

	void InitLog();
}

#define QLS_LOG(...) spdlog::info(__VA_ARGS__)
#define QLS_WARN(...) spdlog::warn(__VA_ARGS__)
#define QLS_ERR(...) spdlog::error(__VA_ARGS__)
