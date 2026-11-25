package com.sensen.map

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.assertFails

class ParcelLayerStateTest {
    private fun loaded(): ParcelLayerState = ParcelLayerState().apply { begin(10); loaded(epoch) }
    @Test fun delayedQueryCannotSurviveStyleReload() {
        val state = loaded(); val query = state.query(10)!!
        state.reloading(); state.loaded(state.epoch)
        assertFalse(state.current(query)); assertNotNull(state.query(10))
    }
    @Test fun delayedQueryCannotSurviveSceneReplacementOrClear() {
        val state = loaded(); val old = state.query(10)!!
        state.clear(10); assertFalse(state.current(old))
        state.begin(11); state.loaded(state.epoch)
        assertFalse(state.current(old)); assertNull(state.begin(10)); assertFalse(state.clear(10))
        assertTrue(state.active)
    }
    @Test fun newerTapAndInvalidTapRetirePreviousResult() {
        val state = loaded(); val first = state.query(10)!!; val second = state.query(10)!!
        assertFalse(state.current(first)); assertTrue(state.current(second))
        state.invalidateQueries(); assertFalse(state.current(second))
    }
    @Test fun cannotQueryBeforeDataReadyOrForWrongScene() {
        val state = ParcelLayerState(); state.begin(10)
        assertNull(state.query(10)); state.loaded(state.epoch); assertNull(state.query(9))
    }
    @Test fun preLoadChangesAreRetainedAndReplayedAfterReload() {
        val state = ParcelLayerState(); state.begin(10)
        val visual = ParcelVisualState(selected = true, claimed = true)
        state.update(10, mapOf("p-a" to visual)); state.loaded(state.epoch)
        state.reloading(); assertFalse(state.ready)
        state.loaded(state.epoch); assertEquals(mapOf("p-a" to visual), state.replay())
    }
    @Test fun differenceBatchClearsOldSelectionWithoutErasingOthers() {
        val state = loaded(); val selected = ParcelVisualState(selected = true); val claim = ParcelVisualState(claimed = true)
        assertEquals(mapOf("p-a" to selected, "p-b" to claim), state.update(10, mapOf("p-a" to selected, "p-b" to claim)))
        assertTrue(state.update(10, mapOf("p-b" to claim)).isEmpty())
        assertEquals(mapOf("p-a" to ParcelVisualState()), state.update(10, mapOf("p-a" to ParcelVisualState())))
        assertEquals(mapOf("p-b" to claim), state.replay())
    }
    @Test fun oldDatasetStateCannotTintNewDataset() {
        val state = loaded(); state.update(10, mapOf("p-a" to ParcelVisualState(own = true)))
        state.begin(11); state.update(10, mapOf("p-b" to ParcelVisualState(selected = true)))
        state.loaded(state.epoch); assertTrue(state.replay().isEmpty())
    }
    @Test fun stateLimitRejectsWholeBatchWithoutPartialMutation() {
        val state = loaded()
        state.update(10, (0 until 3000).associate { "p-$it" to ParcelVisualState(claimed = true) })
        val before = state.replay()
        assertFails { state.update(10, mapOf("p-new" to ParcelVisualState(selected = true))) }
        assertEquals(before, state.replay())
    }
    @Test fun oldSourceCompletionCannotMarkNewSourceReady() {
        val state = ParcelLayerState(); val oldEpoch = state.begin(10)!!; state.begin(11)
        assertFalse(state.loaded(oldEpoch)); assertFalse(state.ready)
    }
    @Test fun hideOrBackgroundRetiresPendingQueriesEvenAfterResume() {
        val state = loaded(); val old = state.query(10)!!
        state.setInteractive(false)
        assertFalse(state.current(old)); assertNull(state.query(10))
        state.setInteractive(true)
        assertFalse(state.current(old)); assertNotNull(state.query(10))
    }
    @Test fun styleLoadWhileHiddenCannotEnablePicking() {
        val state = ParcelLayerState(); state.setInteractive(false)
        state.begin(10); state.loaded(state.epoch)
        assertNull(state.query(10))
        state.setInteractive(true); assertNotNull(state.query(10))
    }
    @Test fun idleWaitAnswersTheTapOnceTheMapSettles() {
        val wait = ParcelIdleWait<String>(); wait.park("tap")
        assertNull(wait.resume(false)); assertEquals("tap", wait.resume(true))
        assertNull(wait.resume(true)); assertFalse(wait.expire("tap"))
    }
    @Test fun idleWaitTimeoutOnlyExpiresTheCurrentTap() {
        val wait = ParcelIdleWait<String>(); wait.park("first"); wait.park("second")
        assertFalse(wait.expire("first")); assertEquals("second", wait.pending)
        assertTrue(wait.expire("second")); assertNull(wait.resume(true))
        wait.park("third"); wait.drop(); assertNull(wait.resume(true)); assertFalse(wait.expire("third"))
    }
    @Test fun querySettlesAfterItsSourcesLoadAndOneFrameRenders() {
        val settle = ParcelQuerySettle(); settle.reset(setOf("parcels", "buildings"))
        assertFalse(settle.frameRendered())
        settle.tileLoaded("parcels", true); assertFalse(settle.frameRendered())
        settle.tileLoaded("composite", false); settle.tileLoaded("buildings", null); assertFalse(settle.frameRendered())
        settle.tileLoaded("buildings", true); assertFalse(settle.settled)
        assertTrue(settle.frameRendered()); assertTrue(settle.settled)
        assertFalse(settle.frameRendered()); assertTrue(settle.settled) // Reported once; later frames keep it.
        settle.tileLoaded("parcels", true); assertFalse(settle.frameRendered()); assertTrue(settle.settled)
    }
    @Test fun querySettleRestartsOnCameraChangeIncompleteTilesAndNewSources() {
        val settle = ParcelQuerySettle(); settle.reset(setOf("parcels", "buildings"))
        settle.tileLoaded("parcels", true); settle.tileLoaded("buildings", true); settle.cameraChanged()
        assertFalse(settle.frameRendered()); assertFalse(settle.settled) // Loaded before the pan: the new view is unknown.
        settle.tileLoaded("parcels", true); settle.tileLoaded("buildings", true); assertTrue(settle.frameRendered())
        settle.tileLoaded("buildings", false); assertFalse(settle.settled); assertFalse(settle.frameRendered())
        settle.tileLoaded("buildings", true); assertTrue(settle.frameRendered())
        settle.reset(setOf("parcels-2")); assertFalse(settle.settled)
        settle.tileLoaded("parcels", true); assertFalse(settle.frameRendered())
        settle.tileLoaded("parcels-2", true); assertTrue(settle.frameRendered())
        settle.reset(emptySet()); settle.tileLoaded("parcels-2", true); assertFalse(settle.frameRendered()); assertFalse(settle.settled)
    }
    // C-118: returning to the map, the foreground or a reload must not fetch and parse the 60 MB building file again.
    private val buildingsUrl = "https://example.test/r6/buildings.geojson"
    private fun buildings() = ParcelBuildingsSource("gensen-buildings-datasf")
    @Test fun buildingSourceIsAddedOnceAndReusedWhileLoadingOrLoaded() {
        val source = buildings()
        assertEquals(ParcelBuildingsSource.Plan.ADD, source.plan(buildingsUrl, exists = false))
        val id = source.added(buildingsUrl); assertEquals(id, source.id)
        assertEquals(ParcelBuildingsSource.Plan.REUSE, source.plan(buildingsUrl, exists = true)); assertFalse(source.loaded)
        assertTrue(source.markLoaded(id)); assertFalse(source.markLoaded(id)) // Later tile events are not a second load.
        assertEquals(ParcelBuildingsSource.Plan.REUSE, source.plan(buildingsUrl, exists = true)); assertTrue(source.loaded)
        assertEquals(id, source.id)
    }
    @Test fun buildingSourceIsFetchedAgainForANewUrlAFailureOrANewStyle() {
        val source = buildings(); val first = source.added(buildingsUrl); source.markLoaded(first)
        assertEquals(ParcelBuildingsSource.Plan.REPLACE, source.plan("https://example.test/r7/buildings.geojson", exists = true))
        assertTrue(source.markFailed(first)); assertFalse(source.loaded)
        assertEquals(ParcelBuildingsSource.Plan.REPLACE, source.plan(buildingsUrl, exists = true))
        assertFalse(source.markLoaded(first)); assertFalse(source.loaded) // A late event cannot revive the failed load.
        val second = source.added(buildingsUrl); assertEquals(ParcelBuildingsSource.Plan.REUSE, source.plan(buildingsUrl, exists = true))
        // A style reload drops every source: added again, never reported loaded from the old style.
        source.markLoaded(second); source.dropped()
        assertEquals(ParcelBuildingsSource.Plan.ADD, source.plan(buildingsUrl, exists = false)); assertFalse(source.loaded)
        assertFalse(source.markLoaded(second)); assertTrue(source.stale(second))
    }
    @Test fun anUntrackedSourceIsNeverReused() {
        val source = buildings()
        assertEquals(ParcelBuildingsSource.Plan.ADD, source.plan(buildingsUrl, exists = true))
        assertFalse(source.markLoaded("gensen-buildings-datasf")); assertFalse(source.loaded)
    }
    // C-124: a copy Mapbox never finishes nor fails is not waited for again after a Retry or the load timeout.
    @Test fun refetchReplacesACopyStillLoadingButKeepsALoadedOne() {
        val source = buildings(); val stuck = source.added(buildingsUrl)
        assertEquals(ParcelBuildingsSource.Plan.REUSE, source.plan(buildingsUrl, exists = true)) // Pause and resume.
        assertEquals(ParcelBuildingsSource.Plan.REPLACE, source.plan(buildingsUrl, exists = true, refetch = true))
        val fresh = source.added(buildingsUrl); assertTrue(fresh != stuck)
        assertTrue(source.markLoaded(fresh))
        assertEquals(ParcelBuildingsSource.Plan.REUSE, source.plan(buildingsUrl, exists = true, refetch = true))
        assertEquals(ParcelBuildingsSource.Plan.ADD, source.plan(buildingsUrl, exists = false, refetch = true))
    }
    // C-124: the copy before a replacement may still report; its events must not touch the new copy.
    @Test fun aReplacedCopysLateEventsDoNotChangeTheNewCopy() {
        val source = buildings(); val old = source.added(buildingsUrl)
        val next = source.added("https://example.test/r7/buildings.geojson")
        assertTrue(source.stale(old)); assertFalse(source.stale(next)); assertFalse(source.stale("composite"))
        assertFalse(source.markLoaded(old)); assertFalse(source.loaded) // Not marked loaded early.
        assertFalse(source.markFailed(old)) // Not fetched again for the old copy's error.
        assertEquals(ParcelBuildingsSource.Plan.REUSE, source.plan("https://example.test/r7/buildings.geojson", exists = true))
        assertTrue(source.markLoaded(next)); assertFalse(source.markFailed(old)); assertTrue(source.loaded)
        assertEquals(ParcelBuildingsSource.Plan.REUSE, source.plan("https://example.test/r7/buildings.geojson", exists = true))
        // The same for a copy replaced at the same URL after a failure.
        source.markFailed(next); val third = source.added("https://example.test/r7/buildings.geojson")
        assertFalse(source.markLoaded(next)); assertFalse(source.markFailed(next)); assertTrue(source.markLoaded(third))
    }
    // C-83 on C-118/C-124: a tap settles on the current building copy's own tile events, never a replaced copy's.
    @Test fun querySettleFollowsTheCurrentBuildingCopy() {
        val source = buildings(); val settle = ParcelQuerySettle()
        val stuck = source.added(buildingsUrl) // Download cut off by the outage, neither loaded nor failed.
        settle.reset(ParcelQuerySettle.sourcesFor("parcels-1", true, stuck))
        assertEquals(ParcelBuildingsSource.Plan.REPLACE, source.plan(buildingsUrl, exists = true, refetch = true)) // Retry.
        val fresh = source.added(buildingsUrl)
        settle.reset(ParcelQuerySettle.sourcesFor("parcels-2", true, fresh))
        settle.tileLoaded("parcels-2", true); settle.tileLoaded(stuck, true) // The old copy finishing late.
        assertFalse(settle.frameRendered()); assertFalse(settle.settled)
        settle.tileLoaded(fresh, true); assertTrue(settle.frameRendered())
    }
    @Test fun aReusedLoadedCopyStillNeedsItsOwnTileEvents() {
        val source = buildings(); val settle = ParcelQuerySettle()
        val id = source.added(buildingsUrl); source.markLoaded(id)
        assertEquals(ParcelBuildingsSource.Plan.REUSE, source.plan(buildingsUrl, exists = true)); assertTrue(source.loaded)
        // The fill layer is added again: its tiles are laid out again before a query can hit a building.
        settle.reset(ParcelQuerySettle.sourcesFor("parcels-2", true, source.id))
        settle.tileLoaded("parcels-2", true); assertFalse(settle.frameRendered()); assertFalse(settle.settled)
        settle.tileLoaded(id, true); assertTrue(settle.frameRendered())
    }
    @Test fun querySettleSourcesByBuildingKind() {
        assertEquals(setOf("parcels", "composite"), ParcelQuerySettle.sourcesFor("parcels", false, null))
        assertEquals(setOf("parcels", "gensen-buildings-datasf-3"), ParcelQuerySettle.sourcesFor("parcels", true, "gensen-buildings-datasf-3"))
        assertEquals(emptySet<String>(), ParcelQuerySettle.sourcesFor("parcels", true, null)) // Mapbox refused the copy.
    }
    @Test fun sourceTimeoutCountsOnlyWhileTheParcelLayersAreDrawn() { // C-130 V-362
        val timeout = ParcelSourceTimeout()
        assertNull(timeout.update(awaited = true, drawn = false)) // Entered below the selectable zoom: nothing to load.
        assertFalse(timeout.armed)
        val first = assertNotNull(timeout.update(awaited = true, drawn = true)) // Zoomed in: the count starts.
        assertNull(timeout.update(awaited = true, drawn = true)) // Further camera changes keep the same count.
        assertTrue(timeout.fires(first))
        assertNull(timeout.update(awaited = true, drawn = false)) // Zoomed out again before loading: stopped.
        assertFalse(timeout.fires(first))
        val second = assertNotNull(timeout.update(awaited = true, drawn = true)) // A fresh, full count.
        assertFalse(timeout.fires(first)); assertTrue(timeout.fires(second))
        assertNull(timeout.update(awaited = false, drawn = true)) // Loaded.
        assertFalse(timeout.fires(second))
        val third = assertNotNull(timeout.update(awaited = true, drawn = true))
        timeout.reset() // Reinstalled (new sources or style): the old countdown is retired.
        assertFalse(timeout.fires(third))
    }
}
