package com.sensen.map

import android.os.Handler
import android.os.Looper
import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.mapbox.bindgen.Value
import com.mapbox.common.Cancelable
import com.mapbox.geojson.Feature
import com.mapbox.geojson.FeatureCollection
import com.mapbox.geojson.Geometry
import com.mapbox.geojson.Polygon
import com.mapbox.geojson.MultiPolygon
import com.mapbox.maps.MapView
import com.mapbox.maps.RenderedQueryGeometry
import com.mapbox.maps.RenderedQueryOptions
import com.mapbox.maps.ScreenCoordinate
import com.mapbox.maps.SourceDataLoadedType
import com.mapbox.maps.Style

/** Optional dynamic-farm native overlay. Mapbox owns URL loading, geometry projection, rendering and hit testing. */
internal class ParcelMapController(
    private val view: MapView,
    private val ready: (Long, Long, String) -> Unit,
    private val result: (Long, Long, Long, String) -> Unit,
    private val error: (Long, Long, String) -> Unit,
) {
    private val state = ParcelLayerState()
    private val handler = Handler(Looper.getMainLooper())
    private var config: ParcelSourceConfig? = null
    private var claims: Map<String, String> = emptyMap()
    private val sources = linkedMapOf<String, String>()
    private val loaded = mutableSetOf<String>()
    private var query: Cancelable? = null
    private val waiting = ParcelIdleWait<WaitingQuery>()
    private val settle = ParcelQuerySettle()
    private val buildingSelection = ParcelBuildingSelection()
    private var cameraRevision = 0L
    private var mapIdle = false
    private var mapboxLoadFailed = false
    private var closed = false
    private val subscriptions = mutableListOf<Cancelable>()
    private val map get() = view.mapboxMap

    companion object {
        const val FILL = "gensen-parcel-fill"
        const val LINE = "gensen-parcel-line"
        const val BUILDINGS = "gensen-parcel-buildings"
        const val BUILDING_FILL = "gensen-parcel-building-fill"
        const val HIGHLIGHT_FILL = "gensen-selected-building-fill"
        const val HIGHLIGHT_LINE = "gensen-selected-building-line"
        const val ADDRESSES = "gensen-parcel-addresses"
        const val CLAIM_NAMES = "gensen-parcel-claim-names"
        val LAYERS = listOf(FILL, LINE, BUILDING_FILL, BUILDINGS, HIGHLIGHT_FILL, HIGHLIGHT_LINE, ADDRESSES, CLAIM_NAMES)
        // C-32 / q(342): own parcel green, someone else's red. Claimable yellow is the selected building's highlight.
        const val OWN_COLOR = "#3E9B55"
        const val TAKEN_COLOR = "#D2493F"
        private const val OWN = """["boolean",["feature-state","own"],false]"""
        private const val TAKEN = """["boolean",["feature-state","claimed"],false]"""
        private const val SELECTED = """["boolean",["feature-state","selected"],false]"""
        /** A tap right after a pan waits this long for map idle before answering "loading". */
        const val IDLE_WAIT_MS = 4000L
    }
    private class WaitingQuery(val requestId: Long, val generation: Long, val x: Double, val y: Double, val ticket: ParcelTicket, val revision: Long)
    init {
        subscriptions += map.subscribeStyleLoaded {
            if (!closed && state.active) {
                query?.cancel(); query = null; waiting.drop()
                state.reloading(); mapIdle = false; mapboxLoadFailed = false; buildingSelection.clear(); sources.clear(); loaded.clear()
                settle.reset(emptySet())
                install()
            }
        }
        subscriptions += map.subscribeCameraChanged { cameraRevision++; mapIdle = false; settle.cameraChanged() }
        subscriptions += map.subscribeMapIdle {
            if (!closed) { mapIdle = true; if (state.active) emitReady(); resumeWaiting() }
        }
        // C-83: our own sources can be ready for this camera while map-wide idle still waits on unrelated requests.
        subscriptions += map.subscribeRenderFrameFinished {
            if (!closed && settle.frameRendered()) { if (state.active) emitReady(); resumeWaiting() }
        }
        subscriptions += map.subscribeSourceDataLoaded { event ->
            if (!closed && event.type == SourceDataLoadedType.TILE) settle.tileLoaded(event.sourceId, event.loaded)
            if (!closed && event.sourceId == "composite" && event.loaded == true) mapboxLoadFailed = false
            if (!closed && state.active && sources.containsValue(event.sourceId) && event.loaded == true) {
                val changed = loaded.add(event.sourceId)
                val becameReady = !state.ready && sources["parcels"] in loaded && state.loaded(state.epoch)
                if (becameReady) applyStates(state.replay())
                if (changed || becameReady) emitReady()
                resumeWaiting()
            }
        }
        subscriptions += map.subscribeMapLoadingError { event ->
            if (!closed && config?.buildingSource == "mapbox" && event.sourceId == "composite") {
                mapboxLoadFailed = true
                if (state.active) { emitReady(); error(state.generation, state.epoch, "building_load_failed") }
            }
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
        if (oldGeneration != generation) claims = emptyMap()
        query?.cancel(); query = null; waiting.drop()
        removeLayers(); config = next; mapIdle = false; mapboxLoadFailed = false; settle.reset(emptySet())
        install()
    }
    private fun install() {
        val cfg = config ?: return
        if (closed || !state.active || !map.isValid()) return
        val style = map.style ?: return
        val turn = state.epoch
        removeLayers(style)
        val prefix = "gensen-parcels-${state.generation}-$turn"
        sources.putAll(mapOf("parcels" to prefix, "highlight" to "$prefix-highlight"))
        if (cfg.buildingSource == "datasf") sources["buildings"] = "$prefix-buildings"
        // The sources a tap queries: parcels plus DataSF buildings, or the style's composite for Mapbox buildings.
        settle.reset(setOf(sources.getValue("parcels"), sources["buildings"] ?: "composite"))
        val parcel = sources.getValue("parcels"); val highlight = sources.getValue("highlight")
        fun geoSource(id: String, data: Value): Boolean = !style.addStyleSource(id, Value(hashMapOf("type" to Value("geojson"), "data" to data))).isError
        fun layer(json: String): Boolean = !style.addStyleLayer(value(json), null).isError
        val parcelSource = hashMapOf("type" to Value(cfg.sourceType), "maxzoom" to Value(cfg.sourceMaxZoom.toLong()))
        if (cfg.sourceType == "vector") {
            parcelSource["minzoom"] = Value(cfg.sourceMinZoom.toLong())
            if (cfg.tiles.isNotEmpty()) parcelSource["tiles"] = Value(cfg.tiles.map { Value(it) }) else parcelSource["url"] = Value(cfg.parcelUrl)
            parcelSource["promoteId"] = Value(hashMapOf(cfg.sourceLayer!! to Value("block_id")))
        } else {
            parcelSource["data"] = Value(cfg.parcelUrl); parcelSource["tolerance"] = Value(0.1)
            parcelSource["promoteId"] = Value("block_id")
        }
        val sourceLayer = if (cfg.sourceType == "vector") ",\"source-layer\":\"${cfg.sourceLayer}\"" else ""
        // R4 / decision 1C: no standing frame on unclaimed parcels. Claimed ones are filled by owner (C-32).
        // Do not set visibility:none or remove FILL: queryAt still uses its feature index.
        var ok = !style.addStyleSource(parcel, Value(parcelSource)).isError && geoSource(highlight, value(ParcelPayload.EMPTY_COLLECTION)) &&
            layer("""{"id":"$FILL","type":"fill","source":"$parcel"$sourceLayer,"minzoom":${cfg.minZoom},"paint":{"fill-color":["case",$OWN,"$OWN_COLOR",$TAKEN,"$TAKEN_COLOR","#3B7757"],"fill-opacity":["case",$OWN,["case",$SELECTED,0.6,0.42],$TAKEN,["case",$SELECTED,0.55,0.36],0.0]}}""") &&
            layer("""{"id":"$LINE","type":"line","source":"$parcel"$sourceLayer,"minzoom":${cfg.minZoom},"paint":{"line-color":["case",$OWN,"$OWN_COLOR",$TAKEN,"$TAKEN_COLOR","#ED9F18"],"line-width":2.5,"line-opacity":["case",["any",$OWN,$TAKEN,$SELECTED],1.0,0.0]}}""")
        // DataSF: the yellow highlight filters the building source to the chosen parcel's footprints (C-43 V-199).
        var highlightSource = "\"source\":\"$highlight\""
        if (ok && cfg.buildingSource == "datasf") {
            val buildings = sources.getValue("buildings")
            // C-43 V-199: drawn from the selectable zoom. A source no layer draws never reports loaded, so taps below
            // the address zoom waited for it forever.
            val drawn = "\"source\":\"$buildings\",\"minzoom\":${cfg.minZoom}"
            highlightSource = "$drawn,\"filter\":${ParcelPayload.buildingFilter("")}"
            ok = geoSource(buildings, Value(cfg.buildingsUrl)) &&
                layer("""{"id":"$BUILDING_FILL","type":"fill",$drawn,"paint":{"fill-color":"#716556","fill-opacity":0.16}}""") &&
                layer("""{"id":"$BUILDINGS","type":"line",$drawn,"paint":{"line-color":"#716556","line-width":1.3}}""")
        }
        ok = ok && layer("""{"id":"$HIGHLIGHT_FILL","type":"fill",$highlightSource,"paint":{"fill-color":"#FFD15C","fill-opacity":0.65}}""") &&
            layer("""{"id":"$HIGHLIGHT_LINE","type":"line",$highlightSource,"paint":{"line-color":"#ED9F18","line-width":2.5}}""") &&
            layer("""{"id":"$ADDRESSES","type":"symbol","source":"$parcel"$sourceLayer,"minzoom":${cfg.addressMinZoom},"layout":{"text-field":["coalesce",["get","address"],""],"text-size":11,"text-max-width":8,"text-allow-overlap":false},"paint":{"text-color":"#37463B","text-halo-color":"#FFFFFF","text-halo-width":1.2}}""") &&
            layer("""{"id":"$CLAIM_NAMES","type":"symbol","source":"$parcel"$sourceLayer,"minzoom":${cfg.minZoom},"filter":${ParcelPayload.claimFilter(claims)},"layout":{"text-field":${ParcelPayload.claimLabel(claims)},"text-size":13,"text-max-width":8,"text-allow-overlap":false},"paint":{"text-color":"#7A2620","text-halo-color":"#FFFFFF","text-halo-width":1.5}}""")
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
        addProperty("building_query_ready", settled() && !mapboxLoadFailed && buildingLayers()?.isNotEmpty() == true)
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
            map.setFeatureState(source, config?.takeIf { it.sourceType == "vector" }?.sourceLayer, parcel, bits) { response ->
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
        val style = if (map.isValid()) map.style else null
        if (style == null || !style.styleLayerExists(CLAIM_NAMES)) return // install() applies the latest names.
        if (style.setStyleLayerProperty(CLAIM_NAMES, "filter", value(ParcelPayload.claimFilter(claims))).isError ||
            style.setStyleLayerProperty(CLAIM_NAMES, "text-field", value(ParcelPayload.claimLabel(claims))).isError) error(generation, state.epoch, "claims_update_failed")
    }
    private fun buildingLayers(): List<String>? {
        val cfg = config ?: return null
        val style = if (map.isValid()) map.style else null
        if (style == null) return null
        val ids = if (cfg.buildingSource == "mapbox") cfg.mapboxBuildingLayers else listOf(BUILDING_FILL)
        return ids.takeIf { list -> list.all { id -> style.styleLayers.any { it.id == id && it.type in listOf("fill", "fill-extrusion") } } }
    }
    fun setBuildingHighlight(generation: Long, key: String, parcelId: String = "") {
        if (closed || !state.active || generation != state.generation || !map.isValid()) return
        val geometry = if (key.isEmpty()) null else buildingSelection.lookup(generation, state.epoch, key)
        if (key.isNotEmpty() && geometry == null) { error(generation, state.epoch, "stale_building_key"); return }
        val id = sources["highlight"] ?: return
        val style = map.style ?: return
        val failed = if (config?.buildingSource == "datasf") {
            val filter = value(ParcelPayload.buildingFilter(if (geometry == null) "" else parcelId))
            style.setStyleLayerProperty(HIGHLIGHT_FILL, "filter", filter).isError || style.setStyleLayerProperty(HIGHLIGHT_LINE, "filter", filter).isError
        } else {
            val data = if (geometry == null) ParcelPayload.EMPTY_COLLECTION else FeatureCollection.fromFeature(Feature.fromGeometry(geometry)).toJson()
            style.setStyleSourceProperty(id, "data", value(data)).isError
        }
        if (failed) error(generation, state.epoch, "highlight_failed")
        if (key.isEmpty()) buildingSelection.clear()
    }
    fun queryAt(requestId: Long, generation: Long, x: Double, y: Double) {
        if (closed || !state.active || generation != state.generation) return
        val cfg = config ?: return
        query?.cancel(); query = null; waiting.drop(); state.invalidateQueries()
        setBuildingHighlight(generation, "")
        if (!x.isFinite() || !y.isFinite() || x !in 0.0..1.0 || y !in 0.0..1.0 || view.width <= 0 || view.height <= 0) { failQuery(requestId, generation, "invalid_point"); return }
        val ticket = state.query(generation) ?: run { failQuery(requestId, generation, "loading"); return }
        val tap = WaitingQuery(requestId, generation, x, y, ticket, cameraRevision)
        if (queryReady(cfg)) { runQuery(tap); return }
        // C-27: tiles of a just-panned view are still settling. Answer once the map is idle instead of failing the tap.
        waiting.park(tap)
        handler.postDelayed({
            if (waiting.expire(tap) && !closed && state.current(ticket)) failQuery(requestId, generation, "loading")
        }, IDLE_WAIT_MS)
    }
    private fun settled(): Boolean = mapIdle || settle.settled
    private fun queryReady(cfg: ParcelSourceConfig): Boolean = settled() && (cfg.buildingSource != "datasf" || sources["buildings"] in loaded)
    private fun resumeWaiting() {
        val cfg = config ?: return
        val tap = waiting.resume(queryReady(cfg)) ?: return
        if (!closed && state.current(tap.ticket)) runQuery(tap)
    }
    private fun failQuery(requestId: Long, generation: Long, code: String) {
        val source = config?.buildingSource.orEmpty()
        result(requestId, generation, state.epoch, "{\"parcel_ids\":[],\"properties\":[],\"kind\":\"none\",\"building_key\":\"\",\"building_source\":\"$source\",\"error\":\"$code\"}")
    }
    private fun runQuery(tap: WaitingQuery) {
        val cfg = config ?: return
        val requestId = tap.requestId; val generation = tap.generation; val ticket = tap.ticket
        fun fail(code: String) = failQuery(requestId, generation, code)
        if (tap.revision != cameraRevision) { fail("camera_changed"); return }
        if (cfg.buildingSource == "mapbox" && mapboxLoadFailed) { fail("building_load_failed"); return }
        val buildingIds = buildingLayers() ?: run { fail("building_layer_unavailable"); return }
        val revision = tap.revision
        val source = sources["parcels"] ?: return
        // One rendered-query snapshot: same pixel/camera for building priority and its game parcel candidates.
        query = map.queryRenderedFeatures(RenderedQueryGeometry(ScreenCoordinate(tap.x * view.width, tap.y * view.height)), RenderedQueryOptions(listOf(FILL) + buildingIds, null)) { response ->
            if (closed || !state.current(ticket) || sources["parcels"] != source) return@queryRenderedFeatures
            if (revision != cameraRevision) { fail("camera_changed"); return@queryRenderedFeatures }
            if (response.isError) { fail("query_failed"); return@queryRenderedFeatures }
            val found = linkedMapOf<String, JsonObject>()
            var building: Geometry? = null
            for (hit in response.value.orEmpty()) {
                val feature = hit.queriedFeature.feature
                if (hit.queriedFeature.source == source && hit.layers.contains(FILL) && (cfg.sourceType != "vector" || hit.queriedFeature.sourceLayer == cfg.sourceLayer)) {
                    val properties = feature.properties() ?: continue
                    val safe = ParcelPayload.publicProperties(properties) ?: continue
                    found[safe.get("block_id").asString] = safe
                } else if (building == null && hit.layers.any { it in buildingIds } &&
                    (cfg.buildingSource == "mapbox" || hit.queriedFeature.source == sources["buildings"])) {
                    val geometry = feature.geometry()
                    if (geometry is Polygon || geometry is MultiPolygon) building = geometry
                }
            }
            if (found.size > 32) { fail("too_many_candidates"); return@queryRenderedFeatures }
            if (building != null && found.isEmpty()) { fail("building_without_parcel"); return@queryRenderedFeatures }
            val key = building?.let { buildingSelection.remember(ticket, it) }.orEmpty()
            result(requestId, generation, ticket.epoch, JsonObject().apply {
                add("parcel_ids", JsonArray().apply { found.keys.forEach { add(it) } })
                add("properties", JsonArray().apply { found.values.forEach { add(it) } })
                addProperty("kind", if (building != null) "building" else if (found.isNotEmpty()) "parcel" else "none")
                addProperty("building_source", cfg.buildingSource); addProperty("building_key", key); addProperty("error", "")
            }.toString())
        }
    }
    fun setInteractive(value: Boolean) {
        state.setInteractive(value)
        if (!value) {
            query?.cancel(); query = null; waiting.drop()
            if (state.active) setBuildingHighlight(state.generation, "")
        }
    }
    fun clear(generation: Long) {
        if (closed || !state.clear(generation)) return
        query?.cancel(); query = null; waiting.drop(); config = null; claims = emptyMap()
        removeLayers()
    }
    private fun removeLayers(style: Style? = if (map.isValid()) map.style else null) {
        if (style != null) {
            for (layer in LAYERS.reversed()) if (style.styleLayerExists(layer)) style.removeStyleLayer(layer)
            for (id in sources.values) if (style.styleSourceExists(id)) style.removeStyleSource(id)
        }
        sources.clear(); loaded.clear(); buildingSelection.clear(); settle.reset(emptySet())
    }
    fun close() {
        if (closed) return
        state.clear(state.generation)
        closed = true; query?.cancel(); query = null; waiting.drop()
        subscriptions.forEach { it.cancel() }; subscriptions.clear()
        handler.removeCallbacksAndMessages(null); config = null; claims = emptyMap()
        removeLayers()
    }
    private fun value(json: String): Value = requireNotNull(Value.fromJson(json).value)
}
