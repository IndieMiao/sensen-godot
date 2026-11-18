package com.sensen.map

import java.util.Locale
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

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
    @Test fun hideCoversBackgroundThenHidesViewBeforeStoppingRender() {
        val events = mutableListOf<String>()
        val p = NativeMapPresentation({ events.add("background:$it") }, { events.add("visible:$it") }, { events.add("render:$it") })
        val green = NativeMapPresentation.opaqueRgb("#E7F0DF")!!
        p.apply(true, true, green); events.clear()
        p.apply(false, true, green)
        assertEquals(listOf("background:$green", "visible:false", "render:false"), events)
        events.clear(); p.apply(false, false, green); p.apply(false, true, green)
        assertEquals(listOf("background:$green", "visible:false", "background:$green", "visible:false"), events)
    }
    @Test fun returnStartsMapThenShowsItAndClearsOpaqueBackdrop() {
        val events = mutableListOf<String>()
        val p = NativeMapPresentation({ events.add("background:$it") }, { events.add("visible:$it") }, { events.add("render:$it") })
        p.apply(false, true, -1); events.clear()
        p.apply(true, true, -1)
        assertEquals(listOf("render:true", "visible:true", "background:0"), events)
    }
    @Test fun mapRequestedWhileBackgroundedStaysHiddenUntilResume() {
        val events = mutableListOf<String>()
        val p = NativeMapPresentation({ events.add("background:$it") }, { events.add("visible:$it") }, { events.add("render:$it") })
        p.apply(true, false, -1)
        assertEquals(listOf("background:-1", "visible:false", "render:false"), events)
        events.clear(); p.apply(true, true, -1)
        assertEquals(listOf("render:true", "visible:true", "background:0"), events)
    }
    @Test fun hiddenColorChangeAndRepeatedHideDoNotRestartRenderer() {
        val events = mutableListOf<String>()
        val p = NativeMapPresentation({ events.add("background:$it") }, { events.add("visible:$it") }, { events.add("render:$it") })
        p.apply(false, true, -1); events.clear()
        val green = NativeMapPresentation.opaqueRgb("#e7f0df")!!
        p.apply(false, true, green)
        assertEquals(listOf("background:$green", "visible:false"), events)
    }
    @Test fun occlusionColorNeverAcceptsTransparentOrMalformedInput() {
        assertEquals(0xffe7f0df.toInt(), NativeMapPresentation.opaqueRgb("#E7F0DF"))
        for (raw in listOf("", "transparent", "#00E7F0DF", "#FFF", " E7F0DF", "#GG0000")) assertNull(NativeMapPresentation.opaqueRgb(raw))
    }
}
