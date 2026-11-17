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
}
