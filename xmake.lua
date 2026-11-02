-- QuestLogSorter
--
-- Modelled on libxse/commonlibf4-template. If something here stops working
-- after a CommonLibF4 update, diff this file against that template first -
-- the rule config keys are defined by commonlib-shared, not by us.

-- include subprojects
includes("lib/commonlibf4")

-- set project constants
set_project("QuestLogSorter")
set_version("1.0.0")

-- CommonLibF4 is GPL-3.0-or-later with a modding exception. Linking against it
-- and distributing the DLL means distributing this source too. See NOTICE.md.
set_license("GPL-3.0")

set_languages("c++23")
set_warnings("allextra")
set_encodings("utf-8")

-- add common rules
-- note: releasedbg, not release - that is what commonlibf4 itself builds with,
-- and mixing modes across the static lib boundary causes link errors.
add_rules("mode.debug", "mode.releasedbg")
add_rules("plugin.vsxmake.autoupdate")

-- external packages
-- spdlog arrives transitively through commonlib-shared, so it is deliberately
-- not requested here; asking for it again can pull a second, conflicting copy.
add_requires("nlohmann_json")

-- define targets
target("QuestLogSorter")
    -- generates the F4SE version data export from these values, which is why
    -- there is no F4SEPlugin_Version block in src/Plugin.cpp
    add_rules("commonlibf4.plugin", {
        name = "QuestLogSorter",
        author = "EmberFrameworks",
        description = "Grouped, collapsible quest log for the Pip-Boy"
    })

    -- add src files
    add_files("src/**.cpp")
    add_headerfiles("src/**.h")
    add_includedirs("src")
    set_pcxxheader("src/PCH.h")

    add_packages("nlohmann_json")

    -- Ship the data files next to the DLL on `xmake install`, so the install
    -- directory is a coherent Data tree rather than a lone plugin.
    --
    -- The "Data/" prefix matters: commonlibf4.plugin installs the DLL under
    -- Data/F4SE/Plugins, so anything installed without it lands a level up
    -- and the game never sees it. That mismatch is easy to miss because
    -- `xmake install` reports success either way.
    --
    -- For a release archive use tools/package.ps1 instead - Vortex and MO2
    -- want the archive rooted at Data's *contents*, not at Data itself.
    add_installfiles("data/F4SE/Plugins/QuestLogSorter/groups.json", {
        prefixdir = "Data/F4SE/Plugins/QuestLogSorter"
    })

    if os.isfile("data/Interface/QuestLogSorter/QLS.swf") then
        add_installfiles("data/Interface/QuestLogSorter/QLS.swf", {
            prefixdir = "Data/Interface/QuestLogSorter"
        })
    end

    if os.isfile("data/Interface/Pipboy_DataPage.swf") then
        add_installfiles("data/Interface/Pipboy_DataPage.swf", {
            prefixdir = "Data/Interface"
        })
    end
