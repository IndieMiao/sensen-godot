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
/**
 * C-118: the DataSF building GeoJSON (r6: 60 MB, ~144k footprints) is one Mapbox source kept per style and URL.
 * Parcel layers are rebuilt for every generation; re-adding this source with them downloaded and parsed it again on
 * every return to the map, foreground or reload, and a removed parse could still be running beside the new one
 * (C-111). Mapbox-free so JVM tests drive it.
 * C-124: each added copy has its own source id ([prefix] and a counter), so a replaced copy's late load or error event
 * cannot count for the copy after it.
 */
internal class ParcelBuildingsSource(private val prefix: String) {
    enum class Plan { REUSE, ADD, REPLACE }
    /** The current copy's source id; null when this style has none. */
    var id: String? = null; private set
    var url: String? = null; private set
    var loaded = false; private set
    private var failed = false
    private var copies = 0L

    /** [exists]: the current style still has [id]; a style reload drops it with every other source.
     *  [refetch] (C-124): the player's Retry or the building load timeout; a copy still loading then counts as failed. */
    fun plan(next: String, exists: Boolean, refetch: Boolean = false): Plan = when {
        id == null || !exists -> Plan.ADD
        next != url || failed || (refetch && !loaded) -> Plan.REPLACE
        else -> Plan.REUSE
    }
    /** Returns the new copy's source id. */
    fun added(next: String): String {
        url = next; loaded = false; failed = false
        return "$prefix-${++copies}".also { id = it }
    }
    /** Load events count while the parcel layers are cleared too: the map may finish a parse behind the 3D farm.
     *  True only for the first load of the current copy. */
    fun markLoaded(source: String): Boolean {
        if (source != id || failed || loaded) return false
        loaded = true
        return true
    }
    /** A failed load is replaced, not reused, so the next setup fetches it again. False for any other source. */
    fun markFailed(source: String?): Boolean {
        if (source == null || source != id) return false
        loaded = false; failed = true
        return true
    }
    /** An event of a copy already replaced or dropped. */
    fun stale(source: String?): Boolean = source != null && source != id && source.startsWith("$prefix-")
    fun dropped() { id = null; url = null; loaded = false; failed = false }
}
/** C-27: the one tap waiting for map idle. Mapbox-free so JVM tests drive it; newer taps replace older ones. */
internal class ParcelIdleWait<T : Any> {
    var pending: T? = null; private set
    fun park(value: T) { pending = value }
    fun resume(ready: Boolean): T? = if (ready) pending.also { pending = null } else null
    fun expire(value: T): Boolean = (pending === value).also { if (it) pending = null }
    fun drop() { pending = null }
}
