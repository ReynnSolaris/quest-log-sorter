#include "PCH.h"

#include "Bridge.h"
#include "Grouping.h"

#include <ShlObj.h>

namespace QLS
{
	namespace
	{
		// This fork has no F4SE::log helper, so resolve the folder ourselves.
		// Same location F4SE and every other plugin uses:
		//   %USERPROFILE%\Documents\My Games\Fallout4\F4SE
		//
		// SHGetKnownFolderPath rather than an env var because Documents is
		// commonly redirected to OneDrive, and %USERPROFILE%\Documents then
		// points at a folder the game never writes to.
		std::filesystem::path DocumentsDir()
		{
			PWSTR raw = nullptr;
			const auto hr = SHGetKnownFolderPath(FOLDERID_Documents, KF_FLAG_DEFAULT, nullptr, &raw);
			if (FAILED(hr) || !raw) {
				if (raw) {
					CoTaskMemFree(raw);
				}
				return {};
			}
			std::filesystem::path result{ raw };
			CoTaskMemFree(raw);
			return result;
		}

		std::filesystem::path F4SEDir()
		{
			const auto documents = DocumentsDir();
			if (documents.empty()) {
				return {};
			}
			return documents / "My Games" / "Fallout4" / "F4SE";
		}
	}

	std::filesystem::path UserDataDir()
	{
		const auto base = F4SEDir();
		return base.empty() ? std::filesystem::path{ "." } : base / PLUGIN_NAME;
	}

	std::filesystem::path ModDataDir()
	{
		// Relative to the game root, so MO2's VFS maps it correctly.
		return std::filesystem::current_path() / "Data" / "F4SE" / "Plugins" / PLUGIN_NAME;
	}

	void InitLog()
	{
		// Two candidates. If Documents cannot be resolved - redirected profile,
		// OneDrive weirdness, locked-down permissions - fall back to the game
		// root so there is ALWAYS a log somewhere. A plugin that loads but
		// writes nothing is the worst possible thing to debug.
		std::vector<std::filesystem::path> candidates;
		if (const auto base = F4SEDir(); !base.empty()) {
			candidates.push_back(base);
		}
		candidates.push_back(std::filesystem::current_path());

		for (const auto& dir : candidates) {
			try {
				std::error_code ec;
				std::filesystem::create_directories(dir, ec);

				const auto path = dir / (std::string{ PLUGIN_NAME } + ".log");
				auto sink = std::make_shared<spdlog::sinks::basic_file_sink_mt>(
					path.string(), true);
				auto logger = std::make_shared<spdlog::logger>("global", std::move(sink));
				logger->set_level(spdlog::level::info);
				logger->flush_on(spdlog::level::info);  // survive a crash
				spdlog::set_default_logger(std::move(logger));
				spdlog::set_pattern("[%H:%M:%S] [%l] %v");
				spdlog::info("log opened at {}", path.string());
				return;
			} catch (const std::exception&) {
				// try the next candidate
			}
		}
	}
}

namespace
{
	void MessageHandler(F4SE::MessagingInterface::Message* a_msg)
	{
		if (!a_msg) {
			return;
		}

		switch (a_msg->type) {
		case F4SE::MessagingInterface::kGameDataReady:
			// Forms exist by now, so rules can be validated against real data.
			QLS::Rules::Load();
			QLS::State::Load();
			break;

		case F4SE::MessagingInterface::kPreSaveGame:
			QLS::State::Save();
			break;

		default:
			break;
		}
	}
}

// No F4SEPlugin_Version here on purpose.
//
// The commonlibf4.plugin xmake rule generates commonlibf4-plugin.cpp from the
// name/author/description you pass it in xmake.lua, and that file exports the
// version data. Defining it here as well is a duplicate symbol at link time.
//
// If your linker instead complains that F4SEPlugin_Version is *missing*, the
// rule did not run - check that add_rules("commonlibf4.plugin", {...}) is on
// the target and that lib/commonlibf4 was cloned with --recursive.

extern "C" [[maybe_unused]] __declspec(dllexport) bool F4SEAPI
	F4SEPlugin_Load(const F4SE::LoadInterface* a_f4se)
{
	F4SE::Init(a_f4se);
	QLS::InitLog();
	QLS_LOG("{} loading", QLS::PLUGIN_NAME);

	auto* messaging = F4SE::GetMessagingInterface();
	if (!messaging || !messaging->RegisterListener(MessageHandler)) {
		QLS_ERR("could not register messaging listener");
		return false;
	}

	// Argument order is (name, callback) in this fork - the reverse of the
	// older CommonLibF4 signature, and the reverse of CommonLibSSE.
	auto* scaleform = F4SE::GetScaleformInterface();
	if (!scaleform || !scaleform->Register(QLS::SCALEFORM_KEY, QLS::RegisterScaleform)) {
		QLS_ERR("could not register scaleform callback");
		return false;
	}

	QLS_LOG("{} loaded", QLS::PLUGIN_NAME);
	return true;
}
