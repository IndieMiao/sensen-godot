package com.sensen.map

import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class GodotMapPluginTest {
    @Test
    fun mapLabelsAlwaysRequestEnglish() {
        assertEquals(Locale.ENGLISH, GodotMapPlugin.MAP_LABEL_LOCALE)
    }

    @Test
    fun englishOnlyFilterSelectsEveryTextLabelCategory() {
        val selected = listOf(
            "poi-label",
            "building-number-label",
            "waterway-label",
            "water-line-label",
            "water-point-label",
            "transit-label",
            "airport-label",
            "natural-line-label",
            "NATURAL-POINT-LABEL",
            "road-label",
            "settlement-major-label",
            "city-label",
            "state-label",
            "country-label",
            "airport-road-label",
        )

        selected.forEach { layerId ->
            assertTrue(
                GodotMapPlugin.shouldRequireEnglishName(layerId),
                "Expected English-only filtering for $layerId",
            )
        }
    }

    @Test
    fun englishOnlyFilterIgnoresNonLabelLayerIds() {
        for (layerId in listOf("poi", "poi-icon", "water", "building-extrusion")) {
            assertFalse(
                GodotMapPlugin.shouldRequireEnglishName(layerId),
                "Expected non-label layer to remain unchanged for $layerId",
            )
        }
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
