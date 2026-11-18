package com.sensen.map

import com.mapbox.geojson.Geometry
import java.util.UUID

/** A single volatile native geometry. The key reveals no provider identifier or coordinates. */
internal class ParcelBuildingSelection(private val newKey: () -> String = { UUID.randomUUID().toString() }) {
    private var key = ""
    private var geometry: Geometry? = null
    private var generation = -1L
    private var epoch = -1L
    fun remember(ticket: ParcelTicket, value: Geometry): String {
        clear(); generation = ticket.generation; epoch = ticket.epoch; geometry = value; key = newKey()
        return key
    }
    fun lookup(nextGeneration: Long, nextEpoch: Long, candidate: String): Geometry? =
        if (candidate.isNotEmpty() && candidate == key && nextGeneration == generation && nextEpoch == epoch) geometry else null
    fun clear() { key = ""; geometry = null; generation = -1; epoch = -1 }
}
