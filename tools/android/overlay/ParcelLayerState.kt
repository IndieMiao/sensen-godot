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
 * C-111: the DataSF building GeoJSON (r6: 60 MB, ~144k footprints) is one Mapbox source kept per style and URL.
 * Parcel layers are rebuilt for every generation; re-adding this source with them re-downloaded and re-parsed it on
 * every return to the map, foreground or reload, and a removed parse could still be running beside the new one
 * (owner's phone: native crash at 2.5 GB RSS, C-111#20). Mapbox-free so JVM tests drive it.
 */
internal class ParcelBuildingsSource {
    enum class Plan { REUSE, ADD, REPLACE }
    var url: String? = null; private set
    var loaded = false; private set
    private var failed = false

    /** [exists]: the current style still has the source; a style reload drops it with every other source. */
    fun plan(next: String, exists: Boolean): Plan = when {
        !exists -> Plan.ADD
        url == null || next != url || failed -> Plan.REPLACE
        else -> Plan.REUSE
    }
    fun added(next: String) { url = next; loaded = false; failed = false }
    /** Load events count while the parcel layers are cleared too: the map may finish a parse behind the 3D farm. */
    fun markLoaded() { if (url != null && !failed) loaded = true }
    /** A failed load is replaced, not reused, so the next setup fetches it again. */
    fun markFailed() { if (url != null) { loaded = false; failed = true } }
    fun dropped() { url = null; loaded = false; failed = false }
}
/** C-27: the one tap waiting for map idle. Mapbox-free so JVM tests drive it; newer taps replace older ones. */
internal class ParcelIdleWait<T : Any> {
    var pending: T? = null; private set
    fun park(value: T) { pending = value }
    fun resume(ready: Boolean): T? = if (ready) pending.also { pending = null } else null
    fun expire(value: T): Boolean = (pending === value).also { if (it) pending = null }
    fun drop() { pending = null }
}
