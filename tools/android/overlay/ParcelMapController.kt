package com.sensen.map

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
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
    private val buildingSelection = ParcelBuildingSelection()
    private val buildingSource = ParcelBuildingsSource()
    private var buildingSourceAddedAt = 0L
    private var cameraRevision = 0L
    private var mapIdle = false
    private var mapboxLoadFailed = false
    private var closed = false
    private val subscriptions = mutableListOf<Cancelable>()
    private val hiddenPlaces = linkedMapOf<String, Value>() // Place icon layer -> its visibility before we hid it.
    private val map get() = view.mapboxMap

    companion object {
        const val FILL = "gensen-parcel-fill"
        const val BUILDING_FILL = "gensen-parcel-building-fill"
        /** C-118: one id for the life of the map, unlike the per-generation parcel sources (see ParcelBuildingsSource). */
        const val BUILDINGS_SOURCE = "gensen-buildings-datasf"
        const val HIGHLIGHT_FILL = "gensen-selected-building-fill"
        const val ADDRESSES = "gensen-parcel-addresses"
        const val CLAIM_NAMES = "gensen-parcel-claim-names"
        // C-112 (C-103#18): no parcel fill or outline and no dark building frames. Only buildings are coloured
        // (own green, someone else's red, claimable yellow when selected), and only by fills, so no colour leaves them.
        val LAYERS = listOf(FILL, BUILDING_FILL, HIGHLIGHT_FILL, ADDRESSES, CLAIM_NAMES)
        /** Never drawn, still hit-tested: a feature-dependent 0, as the parcel fill's unclaimed case always was
         *  (C-28/C-32 picked parcels through it). A constant 0 may let Mapbox leave the layer out of its hit index. */
        private const val HIT_ONLY = """["case",["boolean",["feature-state","selected"],false],0.0,0.0]"""
        /** C-112 (C-103#17): Mapbox's own place icons (shops, schools, stations, airports, peaks) while parcels show. */
        val PLACE_ICON_LAYERS = listOf("poi-label", "transit-label", "airport-label", "natural-point-label")
        /** A tap right after a pan waits this long for map idle before answering "loading". */
        const val IDLE_WAIT_MS = 4000L
    }
    private class WaitingQuery(val requestId: Long, val generation: Long, val x: Double, val y: Double, val ticket: ParcelTicket, val revision: Long)
    init {
        subscriptions += map.subscribeStyleLoaded {
            if (!closed && state.active) {
                query?.cancel(); query = null; waiting.drop(); hiddenPlaces.clear() // A new style has its own icons.
                state.reloading(); mapIdle = false; mapboxLoadFailed = false; buildingSelection.clear(); sources.clear(); loaded.clear()
                buildingSource.dropped() // The new style has none of our sources.
                install()
            }
        }
        subscriptions += map.subscribeCameraChanged { cameraRevision++; mapIdle = false }
        subscriptions += map.subscribeMapIdle {
            if (!closed) { mapIdle = true; if (state.active) emitReady(); resumeWaiting() }
        }
        subscriptions += map.subscribeSourceDataLoaded { event ->
            if (!closed && event.sourceId == "composite" && event.loaded == true) mapboxLoadFailed = false
            if (!closed && event.sourceId == BUILDINGS_SOURCE && event.loaded == true && buildingSource.markLoaded()) {
                buildingsLog("LOADED ms=${SystemClock.uptimeMillis() - buildingSourceAddedAt}")
            }
            if (!closed && state.active && sources.containsValue(event.sourceId) && event.loaded == true) {
                val changed = loaded.add(event.sourceId)
                val becameReady = !state.ready && sources["parcels"] in loaded && state.loaded(state.epoch)
                if (changed || becameReady) emitReady()
                resumeWaiting()
            }
        }
        subscriptions += map.subscribeMapLoadingError { event ->
            if (!closed && event.sourceId == BUILDINGS_SOURCE) { buildingSource.markFailed(); buildingsLog("FAILED") }
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
        removeLayers(); config = next; mapIdle = false; mapboxLoadFailed = false
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
        if (cfg.buildingSource == "datasf") sources["buildings"] = BUILDINGS_SOURCE else dropBuildings(style)
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
        // C-112: the parcel layer is never drawn, owned or not (C-103#18 replaces C-32's parcel colours).
        // Do not set visibility:none or remove FILL: queryAt still uses its feature index.
        var ok = !style.addStyleSource(parcel, Value(parcelSource)).isError && geoSource(highlight, value(ParcelPayload.EMPTY_COLLECTION)) &&
            layer("""{"id":"$FILL","type":"fill","source":"$parcel"$sourceLayer,"minzoom":${cfg.minZoom},"paint":{"fill-color":"#3B7757","fill-opacity":$HIT_ONLY}}""")
        // DataSF: the yellow highlight filters the building source to the chosen parcel's footprints (C-43 V-199).
        var highlightSource = "\"source\":\"$highlight\""
        if (ok && cfg.buildingSource == "datasf") {
            val buildings = sources.getValue("buildings")
            // C-43 V-199: drawn from the selectable zoom. A source no layer draws never reports loaded, so taps below
            // the address zoom waited for it forever.
            val drawn = "\"source\":\"$buildings\",\"minzoom\":${cfg.minZoom}"
            highlightSource = "$drawn,\"filter\":${ParcelPayload.buildingFilter("")}"
            // C-112: the buildings are hit-tested and coloured here only by their parcel's state (own, someone else's).
            val states = state.replay()
            ok = installBuildings(style, cfg.buildingsUrl) &&
                layer("""{"id":"$BUILDING_FILL","type":"fill",$drawn,"paint":{"fill-color":${ParcelPayload.buildingColor(states)},"fill-opacity":${ParcelPayload.buildingOpacity(states)}}}""")
        }
        ok = ok && layer("""{"id":"$HIGHLIGHT_FILL","type":"fill",$highlightSource,"paint":{"fill-color":"${ParcelPayload.CLAIMABLE_COLOR}","fill-opacity":0.65}}""") &&
            layer("""{"id":"$ADDRESSES","type":"symbol","source":"$parcel"$sourceLayer,"minzoom":${cfg.addressMinZoom},"layout":{"text-field":["coalesce",["get","address"],""],"text-size":11,"text-max-width":8,"text-allow-overlap":false},"paint":{"text-color":"#37463B","text-halo-color":"#FFFFFF","text-halo-width":1.2}}""") &&
            layer("""{"id":"$CLAIM_NAMES","type":"symbol","source":"$parcel"$sourceLayer,"minzoom":${cfg.minZoom},"filter":${ParcelPayload.claimFilter(claims)},"layout":{"text-field":${ParcelPayload.claimLabel(claims)},"text-size":13,"text-max-width":8,"text-allow-overlap":false},"paint":{"text-color":"#7A2620","text-halo-color":"#FFFFFF","text-halo-width":1.5}}""")
        if (!ok) {
            removeLayers(style); state.unavailable()
            error(state.generation, turn, "layer_install_failed"); return
        }
        hidePlaceIcons(style)
        emitReady() // source_ready gates picking on parcel data; hidden building layers must not block z17 selection.
        handler.postDelayed({
            if (!closed && state.accepts(turn) && !state.ready) error(state.generation, turn, "source_timeout")
        }, 20000)
    }
    /** C-118: reuse the loaded or still-loading building source; fetch again only for a new URL, a failure or a new style. */
    private fun installBuildings(style: Style, url: String): Boolean {
        val plan = buildingSource.plan(url, style.styleSourceExists(BUILDINGS_SOURCE))
        buildingsLog("$plan loaded=${buildingSource.loaded}")
        when (plan) {
            ParcelBuildingsSource.Plan.REUSE -> { if (buildingSource.loaded) loaded.add(BUILDINGS_SOURCE); return true }
            ParcelBuildingsSource.Plan.REPLACE -> style.removeStyleSource(BUILDINGS_SOURCE) // Its layer went in removeLayers.
            ParcelBuildingsSource.Plan.ADD -> Unit
        }
        buildingSource.added(url); buildingSourceAddedAt = SystemClock.uptimeMillis()
        return !style.addStyleSource(BUILDINGS_SOURCE, Value(hashMapOf("type" to Value("geojson"), "data" to Value(url)))).isError
    }
    private fun dropBuildings(style: Style? = if (map.isValid()) map.style else null) {
        if (style != null && style.styleSourceExists(BUILDINGS_SOURCE)) style.removeStyleSource(BUILDINGS_SOURCE)
        buildingSource.dropped()
    }
    /** Counted by tools/dev/dynamic_farm/crash_repro.sh: one ADD per run, then only REUSE. */
    private fun buildingsLog(text: String) = Log.i("GodotMapPlugin", "DYNAMIC_BUILDINGS_SOURCE $text")
    private fun emitReady() = ready(state.generation, state.epoch, JsonObject().apply {
        addProperty("source_ready", state.ready)
        addProperty("parcel_source_ready", sources["parcels"] in loaded)
        addProperty("buildings_source_ready", sources["buildings"] in loaded)
        addProperty("building_query_ready", mapIdle && !mapboxLoadFailed && buildingLayers()?.isNotEmpty() == true)
    }.toString())

    fun setStates(generation: Long, raw: String) {
        if (closed || !state.active || generation != state.generation) return
        val batch = runCatching { ParcelPayload.states(raw) }.getOrElse {
            error(generation, state.epoch, "invalid_states"); return
        }
        val changed = runCatching { state.update(generation, batch) }.getOrElse {
            error(generation, state.epoch, "state_limit"); return
        }
        if (changed.isNotEmpty()) applyStates()
    }
    /** Repaints the building fill from every parcel's state; install() paints the latest states itself. */
    private fun applyStates() {
        val style = if (map.isValid()) map.style else null
        if (style == null || !style.styleLayerExists(BUILDING_FILL)) return
        val states = state.replay()
        if (style.setStyleLayerProperty(BUILDING_FILL, "fill-color", value(ParcelPayload.buildingColor(states))).isError ||
            style.setStyleLayerProperty(BUILDING_FILL, "fill-opacity", value(ParcelPayload.buildingOpacity(states))).isError) error(state.generation, state.epoch, "states_update_failed")
    }
    private fun hidePlaceIcons(style: Style) {
        for (id in PLACE_ICON_LAYERS) {
            if (hiddenPlaces.containsKey(id) || !style.styleLayerExists(id)) continue
            hiddenPlaces[id] = style.getStyleLayerProperty(id, "visibility").value
            style.setStyleLayerProperty(id, "visibility", Value("none"))
        }
    }
    private fun restorePlaceIcons(style: Style?) {
        if (style != null) for ((id, visibility) in hiddenPlaces) if (style.styleLayerExists(id)) style.setStyleLayerProperty(id, "visibility", visibility)
        hiddenPlaces.clear()
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
            style.setStyleLayerProperty(HIGHLIGHT_FILL, "filter", value(ParcelPayload.buildingFilter(if (geometry == null) "" else parcelId))).isError
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
    private fun queryReady(cfg: ParcelSourceConfig): Boolean = mapIdle && (cfg.buildingSource != "datasf" || sources["buildings"] in loaded)
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
            // The building source outlives its layer (C-118); only close() or a new URL/style drops it.
            for (id in sources.values) if (id != BUILDINGS_SOURCE && style.styleSourceExists(id)) style.removeStyleSource(id)
        }
        restorePlaceIcons(style)
        sources.clear(); loaded.clear(); buildingSelection.clear()
    }
    fun close() {
        if (closed) return
        state.clear(state.generation)
        closed = true; query?.cancel(); query = null; waiting.drop()
        subscriptions.forEach { it.cancel() }; subscriptions.clear()
        handler.removeCallbacksAndMessages(null); config = null; claims = emptyMap()
        removeLayers(); dropBuildings()
    }
    private fun value(json: String): Value = requireNotNull(Value.fromJson(json).value)
}
