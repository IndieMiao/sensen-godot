package com.sensen.map

import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals

class GodotMapPluginTest {
    @Test
    fun mapLabelsFollowTheSelectedLanguageAndDefaultToChinese() {
        assertEquals(Locale.ENGLISH, GodotMapPlugin.mapLabelLocale("en"))
        assertEquals(Locale.SIMPLIFIED_CHINESE, GodotMapPlugin.mapLabelLocale("zh_CN"))
        assertEquals(Locale.SIMPLIFIED_CHINESE, GodotMapPlugin.mapLabelLocale(""))
    }

    @Test
    fun debugStressExtraAddsOnlyTheGodotUserArgument() {
        assertEquals(
            listOf("++", "--qa-scene=stress"),
            GodotMapPlugin.qaCommandLine(debuggable = true, scene = "stress"),
        )
    }

    @Test
    fun releaseBuildIgnoresStressExtra() {
        assertEquals(
            emptyList(),
            GodotMapPlugin.qaCommandLine(debuggable = false, scene = "stress"),
        )
    }

    @Test
    fun debugBuildIgnoresMissingOrNonExactSceneValues() {
        for (scene in listOf<String?>(null, "", "Stress", "dressing", " stress", "stress ")) {
            assertEquals(
                emptyList(),
                GodotMapPlugin.qaCommandLine(debuggable = true, scene = scene),
                "Unexpected QA command line for scene=$scene",
            )
        }
    }
}
