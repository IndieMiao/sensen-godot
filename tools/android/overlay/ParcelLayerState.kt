package com.sensen.map

/** UI-thread state only. Tests exercise delayed work without an Android/Mapbox runtime. */
internal data class ParcelVisualState(val selected: Boolean = false, val claimed: Boolean = false, val own: Boolean = false) {
    val empty: Boolean get() = !selected && !claimed && !own
}
internal data class ParcelTicket(val generation: Long, val epoch: Long, val serial: Long)
internal class ParcelLayerState {
    var generation = -1L; private set
    var epoch = 0L; private set
    var active = false; private set
    var ready = false; private set
    private var querySerial = 0L
    private var interactive = true
    private val states = linkedMapOf<String, ParcelVisualState>()

    fun begin(next: Long): Long? {
        if (next < 0 || next < generation) return null
        if (next != generation) states.clear()
        generation = next; active = true; ready = false; epoch++; querySerial++
        return epoch
    }
    fun reloading(): Long { ready = false; epoch++; querySerial++; return epoch }
    fun accepts(turn: Long): Boolean = active && turn == epoch
    fun loaded(turn: Long): Boolean {
        if (!accepts(turn)) return false
        ready = true
        return true
    }
    fun update(next: Long, batch: Map<String, ParcelVisualState>): Map<String, ParcelVisualState> {
        if (!active || generation != next) return emptyMap()
        val retained = states.keys.toMutableSet()
        for ((id, visual) in batch) { if (visual.empty) retained.remove(id) else retained.add(id) }
        require(retained.size <= 3000) { "state_limit" }
        val changed = linkedMapOf<String, ParcelVisualState>()
        for ((id, state) in batch) {
            val previous = states[id] ?: ParcelVisualState()
            if (previous == state) continue
            if (state.empty) states.remove(id) else states[id] = state
            changed[id] = state
        }
        return changed
    }
    fun replay(): Map<String, ParcelVisualState> = states.toMap()
    fun unavailable() { ready = false; querySerial++ }
    fun invalidateQueries() { querySerial++ }
    fun setInteractive(value: Boolean) {
        if (interactive == value) return
        interactive = value; querySerial++
    }
    fun query(next: Long): ParcelTicket? {
        if (!active || !ready || !interactive || next != generation) return null
        return ParcelTicket(generation, epoch, ++querySerial)
    }
    fun current(ticket: ParcelTicket): Boolean = active && ready && interactive && ticket.generation == generation && ticket.epoch == epoch && ticket.serial == querySerial
    fun clear(next: Long): Boolean {
        if (next != generation) return false
        active = false; ready = false; epoch++; querySerial++; states.clear()
        return true
    }
}
/** C-27: the one tap waiting for map idle. Mapbox-free so JVM tests drive it; newer taps replace older ones. */
internal class ParcelIdleWait<T : Any> {
    var pending: T? = null; private set
    fun park(value: T) { pending = value }
    fun resume(ready: Boolean): T? = if (ready) pending.also { pending = null } else null
    fun expire(value: T): Boolean = (pending === value).also { if (it) pending = null }
    fun drop() { pending = null }
}
/**
 * C-83: Mapbox's map-wide idle waits for every request, including ones still backing off after a network outage, so
 * after a Retry it can lag long past our own layers. A tap only needs the sources it queries loaded for the current
 * camera and one frame rendered with them. Only tile events count: a GeoJSON metadata event can report loaded before
 * its tiles exist. Mapbox-free so JVM tests drive it.
 */
internal class ParcelQuerySettle {
    private var required: Set<String> = emptySet()
    private val loaded = mutableSetOf<String>()
    private var frameDue = false
    var settled = false; private set
    fun reset(sources: Set<String>) { required = sources; unsettle() }
    fun cameraChanged() = unsettle()
    fun tileLoaded(source: String, complete: Boolean?) {
        if (source !in required || complete == null) return
        if (!complete) { loaded.remove(source); frameDue = false; settled = false; return }
        if (loaded.add(source) && !settled && loaded.containsAll(required)) frameDue = true
    }
    /** True when this frame is the first rendered with every required source loaded. */
    fun frameRendered(): Boolean {
        if (!frameDue) return false
        frameDue = false; settled = true
        return true
    }
    private fun unsettle() { loaded.clear(); frameDue = false; settled = false }
}
