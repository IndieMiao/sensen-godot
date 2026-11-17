package com.sensen.map

import android.os.Handler
import android.os.Looper
import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.mapbox.bindgen.Value
import com.mapbox.common.Cancelable
import com.mapbox.maps.MapView
import com.mapbox.maps.RenderedQueryGeometry
import com.mapbox.maps.RenderedQueryOptions
import com.mapbox.maps.ScreenCoordinate
import com.mapbox.maps.Style

/** Demo-only native overlay. Mapbox owns URL loading, geometry projection, rendering and hit testing. */
internal class ParcelMapController(
    private val view: MapView,
    private val ready: (Long, Long, String) -> Unit,
    private val result: (Long, Long, Long, String) -> Unit,
    private val error: (Long, Long, String) -> Unit,
) {
    private val state = ParcelLayerState()
    private val handler = Handler(Looper.getMainLooper())
    private var config: ParcelSourceConfig? = null
    private var claims = ParcelPayload.EMPTY_COLLECTION
    private val sources = linkedMapOf<String, String>()
    private val loaded = mutableSetOf<String>()
    private var query: Cancelable? = null
    private var cameraRevision = 0L
    private var closed = false
    private val subscriptions = mutableListOf<Cancelable>()
    private val map get() = view.mapboxMap

    companion object {
        const val FILL = "gensen-parcel-fill"
        const val LINE = "gensen-parcel-line"
        const val BUILDINGS = "gensen-parcel-buildings"
        const val ADDRESSES = "gensen-parcel-addresses"
        const val CLAIM_DOTS = "gensen-parcel-claim-dots"
        const val CLAIM_NAMES = "gensen-parcel-claim-names"
        val LAYERS = listOf(FILL, LINE, BUILDINGS, ADDRESSES, CLAIM_DOTS, CLAIM_NAMES)
    }
    init {
        subscriptions += map.subscribeStyleLoaded {
            if (!closed && state.active) {
                query?.cancel(); query = null
                state.reloading(); sources.clear(); loaded.clear()
                install()
            }
        }
        subscriptions += map.subscribeCameraChanged { cameraRevision++ }
        subscriptions += map.subscribeSourceDataLoaded { event ->
            if (!closed && state.active && sources.containsValue(event.sourceId) && event.loaded == true) {
                val changed = loaded.add(event.sourceId)
                val becameReady = !state.ready && sources["parcels"] in loaded && state.loaded(state.epoch)
                if (becameReady) applyStates(state.replay())
                if (changed || becameReady) emitReady()
            }
        }
        subscriptions += map.subscribeMapLoadingError { event ->
            if (!closed && state.active && sources.containsValue(event.sourceId)) {
                loaded.remove(event.sourceId)
                val kind = sources.entries.first { it.value == event.sourceId }.key
                if (kind == "parcels") state.unavailable()
                emitReady(); error(state.generation, state.epoch, "${kind}_source_load_failed")
            }
        }
    }

    fun setSources(generation: Long, raw: String) {
        if (closed || generation < state.generation) return
        val next = runCatching { ParcelPayload.config(raw) }.getOrElse {
            error(generation, state.epoch, "invalid_source_config"); return
        }
        val oldGeneration = state.generation
        if (state.begin(generation) == null) return
        if (oldGeneration != generation) claims = ParcelPayload.EMPTY_COLLECTION
        query?.cancel(); query = null
        removeLayers(); config = next
        install()
    }
    private fun install() {
        val cfg = config ?: return
        if (closed || !state.active || !map.isValid()) return
        val style = map.style ?: return
        val turn = state.epoch
        removeLayers(style)
        val prefix = "gensen-parcels-${state.generation}-$turn"
        sources.putAll(mapOf("parcels" to prefix, "buildings" to "$prefix-buildings", "claims" to "$prefix-claims"))
        val parcel = sources.getValue("parcels"); val buildings = sources.getValue("buildings"); val points = sources.getValue("claims")
        fun source(id: String, data: Value, promoted: Boolean = false): Boolean {
            val properties = hashMapOf("type" to Value("geojson"), "data" to data, "maxzoom" to Value(22L), "tolerance" to Value(0.1))
            if (promoted) properties["promoteId"] = Value("block_id")
            return !style.addStyleSource(id, Value(properties)).isError
        }
        fun layer(json: String): Boolean = !style.addStyleLayer(value(json), null).isError
        val color = """["case",["boolean",["feature-state","selected"],false],"#ED9F18",["boolean",["feature-state","own"],false],"#B66324",["boolean",["feature-state","claimed"],false],"#496CAD","#3B7757"]"""
        val ok = source(parcel, Value(cfg.parcelUrl), true) && source(buildings, Value(cfg.buildingsUrl)) && source(points, value(claims)) &&
            layer("""{"id":"$FILL","type":"fill","source":"$parcel","minzoom":${cfg.minZoom},"paint":{"fill-color":$color,"fill-opacity":0.16}}""") &&
            layer("""{"id":"$LINE","type":"line","source":"$parcel","minzoom":${cfg.minZoom},"paint":{"line-color":$color,"line-width":["case",["boolean",["feature-state","selected"],false],2.5,1.2]}}""") &&
            layer("""{"id":"$BUILDINGS","type":"line","source":"$buildings","minzoom":${cfg.addressMinZoom},"paint":{"line-color":"#716556","line-width":1.3}}""") &&
            layer("""{"id":"$ADDRESSES","type":"symbol","source":"$parcel","minzoom":${cfg.addressMinZoom},"layout":{"text-field":["coalesce",["get","address"],""],"text-size":11,"text-max-width":8,"text-allow-overlap":false},"paint":{"text-color":"#37463B","text-halo-color":"#FFFFFF","text-halo-width":1.2}}""") &&
            layer("""{"id":"$CLAIM_DOTS","type":"circle","source":"$points","paint":{"circle-radius":4,"circle-color":"#496CAD","circle-stroke-width":1,"circle-stroke-color":"#FFFFFF"}}""") &&
            layer("""{"id":"$CLAIM_NAMES","type":"symbol","source":"$points","layout":{"text-field":["get","nickname"],"text-size":13,"text-offset":[0,1.2],"text-anchor":"top","text-allow-overlap":false},"paint":{"text-color":"#243B30","text-halo-color":"#FFFFFF","text-halo-width":1.5}}""")
        if (!ok) {
            removeLayers(style); state.unavailable()
            error(state.generation, turn, "layer_install_failed"); return
        }
        emitReady() // source_ready gates picking on parcel data; hidden building layers must not block z17 selection.
        handler.postDelayed({
            if (!closed && state.accepts(turn) && !state.ready) error(state.generation, turn, "source_timeout")
        }, 20000)
    }
    private fun emitReady() = ready(state.generation, state.epoch, JsonObject().apply {
        addProperty("source_ready", state.ready)
        addProperty("parcel_source_ready", sources["parcels"] in loaded)
        addProperty("buildings_source_ready", sources["buildings"] in loaded)
    }.toString())

    fun setStates(generation: Long, raw: String) {
        if (closed || !state.active || generation != state.generation) return
        val batch = runCatching { ParcelPayload.states(raw) }.getOrElse {
            error(generation, state.epoch, "invalid_states"); return
        }
        val changed = runCatching { state.update(generation, batch) }.getOrElse {
            error(generation, state.epoch, "state_limit"); return
        }
        if (state.ready) applyStates(changed)
    }
    private fun applyStates(batch: Map<String, ParcelVisualState>) {
        val source = sources["parcels"] ?: return
        val turn = state.epoch
        for ((parcel, visual) in batch) {
            val bits = Value(hashMapOf("selected" to Value(visual.selected), "claimed" to Value(visual.claimed), "own" to Value(visual.own)))
            map.setFeatureState(source, null, parcel, bits) { response ->
                if (!closed && state.accepts(turn) && source == sources["parcels"] && response.isError) error(state.generation, turn, "feature_state_failed")
            }
        }
    }
    fun setClaims(generation: Long, raw: String) {
        if (closed || !state.active || generation != state.generation) return
        val next = runCatching { ParcelPayload.claims(raw) }.getOrElse {
            error(generation, state.epoch, "invalid_claims"); return
        }
        if (next == claims) return
        claims = next
        val id = sources["claims"] ?: return
        val style = map.style ?: return
        if (style.styleSourceExists(id) && style.setStyleSourceProperty(id, "data", value(claims)).isError) error(generation, state.epoch, "claims_update_failed")
    }
    fun queryAt(requestId: Long, generation: Long, x: Double, y: Double) {
        if (closed || !state.active || generation != state.generation) return
        fun fail(code: String) = result(requestId, generation, state.epoch, "{\"parcel_ids\":[],\"properties\":[],\"error\":\"$code\"}")
        query?.cancel(); query = null; state.invalidateQueries()
        if (!x.isFinite() || !y.isFinite() || x !in 0.0..1.0 || y !in 0.0..1.0 || view.width <= 0 || view.height <= 0) {
            fail("invalid_point"); return
        }
        val ticket = state.query(generation) ?: run { fail("loading"); return }
        val revision = cameraRevision
        val source = sources["parcels"] ?: return
        query = map.queryRenderedFeatures(RenderedQueryGeometry(ScreenCoordinate(x * view.width, y * view.height)), RenderedQueryOptions(listOf(FILL), null)) { response ->
            if (closed || !state.current(ticket) || sources["parcels"] != source) return@queryRenderedFeatures
            if (revision != cameraRevision) { fail("camera_changed"); return@queryRenderedFeatures }
            if (response.isError) { fail("query_failed"); return@queryRenderedFeatures }
            val found = linkedMapOf<String, JsonObject>()
            for (hit in response.value.orEmpty()) {
                if (hit.queriedFeature.source != source || !hit.layers.contains(FILL)) continue
                val properties = hit.queriedFeature.feature.properties() ?: continue
                val safe = ParcelPayload.publicProperties(properties) ?: continue
                found[safe.get("block_id").asString] = safe
            }
            if (found.size > 32) { fail("too_many_candidates"); return@queryRenderedFeatures }
            result(requestId, generation, ticket.epoch, JsonObject().apply {
                add("parcel_ids", JsonArray().apply { found.keys.forEach { add(it) } })
                add("properties", JsonArray().apply { found.values.forEach { add(it) } }); addProperty("error", "")
            }.toString())
        }
    }
    fun clear(generation: Long) {
        if (closed || !state.clear(generation)) return
        query?.cancel(); query = null; config = null; claims = ParcelPayload.EMPTY_COLLECTION
        removeLayers()
    }
    private fun removeLayers(style: Style? = if (map.isValid()) map.style else null) {
        if (style != null) {
            for (layer in LAYERS.reversed()) if (style.styleLayerExists(layer)) style.removeStyleLayer(layer)
            for (id in sources.values) if (style.styleSourceExists(id)) style.removeStyleSource(id)
        }
        sources.clear(); loaded.clear()
    }
    fun close() {
        if (closed) return
        state.clear(state.generation)
        closed = true; query?.cancel(); query = null
        subscriptions.forEach { it.cancel() }; subscriptions.clear()
        handler.removeCallbacksAndMessages(null); config = null; claims = ParcelPayload.EMPTY_COLLECTION
        removeLayers()
    }
    private fun value(json: String): Value = requireNotNull(Value.fromJson(json).value)
}
