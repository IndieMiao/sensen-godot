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
    fun query(next: Long): ParcelTicket? {
        if (!active || !ready || next != generation) return null
        return ParcelTicket(generation, epoch, ++querySerial)
    }
    fun current(ticket: ParcelTicket): Boolean = active && ready && ticket.generation == generation && ticket.epoch == epoch && ticket.serial == querySerial
    fun clear(next: Long): Boolean {
        if (next != generation) return false
        active = false; ready = false; epoch++; querySerial++; states.clear()
        return true
    }
}
