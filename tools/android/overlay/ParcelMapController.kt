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
import com.mapbox.maps.LayerPosition
import com.mapbox.maps.MapView
import com.mapbox.maps.RenderedQueryGeometry
import com.mapbox.maps.RenderedQueryOptions
import com.mapbox.maps.ScreenCoordinate
import com.mapbox.maps.SourceDataLoadedType
import com.mapbox.maps.Style
import com.mapbox.maps.StylePropertyValueKind

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
    private val buildingSource = ParcelBuildingsSource(BUILDINGS_SOURCE)
    private var buildingSourceAddedAt = 0L
    private var cameraRevision = 0L
    private var mapIdle = false
    private var mapboxLoadFailed = false
    private var closed = false
    private val subscriptions = mutableListOf<Cancelable>()
    private val hiddenPlaces = linkedMapOf<String, Value>() // Place icon layer -> its visibility before we hid it.
    private var fadedBuildings: Value? = null // Mapbox's building fill-opacity before the DataSF buildings went over it.
    private var zone: StarterZoneMarker? = null // C-130: this generation's starter zone marker, drawn by installZone().
    private val sourceTimeout = ParcelSourceTimeout() // C-130 (V-362): counts only while the parcel layers are drawn.
    private val map get() = view.mapboxMap

    companion object {
        const val FILL = "gensen-parcel-fill"
        const val BUILDING_FILL = "gensen-parcel-building-fill"
        /** C-118: one source for the life of the map, unlike the per-generation parcel sources (see ParcelBuildingsSource).
         *  C-124: the prefix of its id; every new copy gets the next number. */
        const val BUILDINGS_SOURCE = "gensen-buildings-datasf"
        const val HIGHLIGHT_FILL = "gensen-selected-building-fill"
        const val ADDRESSES = "gensen-parcel-addresses"
        const val CLAIM_NAMES = "gensen-parcel-claim-names"
        /** C-130 (C-129#6): the DataSF buildings as the map's visible buildings, in Mapbox's own building paint, right
         *  above Mapbox's `building` layer, so the selected/own/other fills sit exactly on a visible building. */
        const val BUILDING_BASE = "gensen-parcel-building-base"
        /** Mapbox Streets' building layer: lighter while the DataSF buildings are drawn over it (restored afterwards). */
        const val MAPBOX_BUILDINGS = "building"
        /** C-130: the starter zone marker, its own source and layers (not part of the parcel layers' colouring). */
        const val ZONE_SOURCE = "gensen-starter-zone"
        const val ZONE_MASK = "gensen-starter-zone-mask"
        const val ZONE_EDGE = "gensen-starter-zone-edge"
        val ZONE_LAYERS = listOf(ZONE_MASK, ZONE_EDGE)
        // C-112 (C-103#18): no parcel fill or outline and no dark building frames. Only buildings are coloured
        // (own green, someone else's red, claimable yellow when selected), and only by fills, so no colour leaves them.
        val LAYERS = listOf(FILL, BUILDING_BASE, BUILDING_FILL, HIGHLIGHT_FILL, ADDRESSES, CLAIM_NAMES)
        /** Never drawn, still hit-tested: a feature-dependent 0, as the parcel fill's unclaimed case always was
         *  (C-28/C-32 picked parcels through it). A constant 0 may let Mapbox leave the layer out of its hit index. */
        private const val HIT_ONLY = """["case",["boolean",["feature-state","selected"],false],0.0,0.0]"""
        /** C-112 (C-103#17): Mapbox's own place icons (shops, schools, stations, airports, peaks) while parcels show. */
        val PLACE_ICON_LAYERS = listOf("poi-label", "transit-label", "airport-label", "natural-point-label")
        /** A tap right after a pan waits this long for map idle before answering "loading". */
        const val IDLE_WAIT_MS = 4000L
        /** The parcel source not loaded this long while its layers are drawn (camera at or above the selectable zoom). */
        const val SOURCE_TIMEOUT_MS = 20000L
    }
    private class WaitingQuery(val requestId: Long, val generation: Long, val x: Double, val y: Double, val ticket: ParcelTicket, val revision: Long)
    init {
        subscriptions += map.subscribeStyleLoaded {
            if (!closed && state.active) {
                query?.cancel(); query = null; waiting.drop(); hiddenPlaces.clear(); fadedBuildings = null // A new style has its own icons and buildings.
                state.reloading(); mapIdle = false; mapboxLoadFailed = false; buildingSelection.clear(); sources.clear(); loaded.clear()
                buildingSource.dropped() // The new style has none of our sources.
                settle.reset(emptySet())
                install()
            }
        }
        subscriptions += map.subscribeCameraChanged {
            cameraRevision++; mapIdle = false; settle.cameraChanged()
            if (!closed && state.active) watchSourceTimeout() // Also retires a count once the source has loaded.
        }
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
            if (!closed && event.loaded == true) when {
                buildingSource.markLoaded(event.sourceId) -> buildingsLog("LOADED ms=${SystemClock.uptimeMillis() - buildingSourceAddedAt}")
                buildingSource.stale(event.sourceId) -> buildingsLog("STALE LOADED")
            }
            if (!closed && state.active && sources.containsValue(event.sourceId) && event.loaded == true) {
                val changed = loaded.add(event.sourceId)
                val becameReady = !state.ready && sources["parcels"] in loaded && state.loaded(state.epoch)
                if (changed || becameReady) emitReady()
                resumeWaiting()
            }
        }
        subscriptions += map.subscribeMapLoadingError { event ->
            if (!closed) when {
                buildingSource.markFailed(event.sourceId) -> buildingsLog("FAILED")
                buildingSource.stale(event.sourceId) -> buildingsLog("STALE FAILED")
            }
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
        if (oldGeneration != generation) zone = null // Godot sends the zone again for every new generation.
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
        if (cfg.buildingSource != "datasf") dropBuildings(style)
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
            val buildings = installBuildings(style, cfg.buildingsUrl, cfg.refetchBuildings)
            ok = buildings != null
            if (buildings != null) {
                sources["buildings"] = buildings
                // C-43 V-199: drawn from the selectable zoom. A source no layer draws never reports loaded, so taps below
                // the address zoom waited for it forever.
                val drawn = "\"source\":\"$buildings\",\"minzoom\":${cfg.minZoom}"
                highlightSource = "$drawn,\"filter\":${ParcelPayload.buildingFilter("")}"
                // C-112: the buildings are hit-tested and coloured here only by their parcel's state (own, someone else's).
                val states = state.replay()
                ok = layer("""{"id":"$BUILDING_FILL","type":"fill",$drawn,"paint":{"fill-color":${ParcelPayload.buildingColor(states)},"fill-opacity":${ParcelPayload.buildingOpacity(states)}}}""") &&
                    installBuildingBase(style, buildings, cfg.minZoom)
            }
        }
        // C-83: the sources a tap queries, by the current building copy's id (C-124), so a replaced copy's late tile
        // events cannot settle a tap. A reused copy still waits for its own tile events: Mapbox lays its tiles out
        // again for the re-added fill layer, and a query before that would miss the building.
        settle.reset(ParcelQuerySettle.sourcesFor(parcel, cfg.buildingSource == "datasf", sources["buildings"]))
        ok = ok && layer("""{"id":"$HIGHLIGHT_FILL","type":"fill",$highlightSource,"paint":{"fill-color":"${ParcelPayload.CLAIMABLE_COLOR}","fill-opacity":0.65}}""") &&
            layer("""{"id":"$ADDRESSES","type":"symbol","source":"$parcel"$sourceLayer,"minzoom":${cfg.addressMinZoom},"layout":{"text-field":["coalesce",["get","address"],""],"text-size":11,"text-max-width":8,"text-allow-overlap":false},"paint":{"text-color":"#37463B","text-halo-color":"#FFFFFF","text-halo-width":1.2}}""") &&
            layer("""{"id":"$CLAIM_NAMES","type":"symbol","source":"$parcel"$sourceLayer,"minzoom":${cfg.minZoom},"filter":${ParcelPayload.claimFilter(claims)},"layout":{"text-field":${ParcelPayload.claimLabel(claims)},"text-size":13,"text-max-width":8,"text-allow-overlap":false},"paint":{"text-color":"#7A2620","text-halo-color":"#FFFFFF","text-halo-width":1.5}}""")
        if (!ok) {
            removeLayers(style); state.unavailable()
            error(state.generation, turn, "layer_install_failed"); return
        }
        hidePlaceIcons(style)
        installZone(style)
        emitReady() // source_ready gates picking on parcel data; hidden building layers must not block z17 selection.
        sourceTimeout.reset(); watchSourceTimeout()
    }
    /**
     * C-130 (V-362): the parcel source loads only where a layer draws it, from the selectable zoom ([ParcelSourceConfig.minZoom]).
     * Entering the map below it (the starter zone's landing view) loads nothing, so its load timeout counts only while
     * the camera is at or above that zoom; zooming out again before it loads stops the count, zooming in starts it anew.
     */
    private fun watchSourceTimeout() {
        val cfg = config ?: return
        if (closed || !map.isValid()) return
        val turn = state.epoch
        val token = sourceTimeout.update(state.active && !state.ready, map.cameraState.zoom >= cfg.minZoom) ?: return
        handler.postDelayed({
            if (!closed && sourceTimeout.fires(token) && state.accepts(turn) && !state.ready) error(state.generation, turn, "source_timeout")
        }, SOURCE_TIMEOUT_MS)
    }
    /** C-118: reuse the loaded or still-loading building source; fetch again only for a new URL, a failure or a new style.
     *  C-124: [refetch] also replaces a copy still loading. Returns the copy's source id, null if Mapbox refused it. */
    private fun installBuildings(style: Style, url: String, refetch: Boolean): String? {
        val current = buildingSource.id
        val plan = buildingSource.plan(url, current != null && style.styleSourceExists(current), refetch)
        buildingsLog("$plan loaded=${buildingSource.loaded} refetch=$refetch")
        when (plan) {
            ParcelBuildingsSource.Plan.REUSE -> { if (buildingSource.loaded) loaded.add(current!!); return current }
            ParcelBuildingsSource.Plan.REPLACE -> style.removeStyleSource(current!!) // Its layer went in removeLayers.
            ParcelBuildingsSource.Plan.ADD -> Unit
        }
        val id = buildingSource.added(url); buildingSourceAddedAt = SystemClock.uptimeMillis()
        return id.takeUnless { style.addStyleSource(id, Value(hashMapOf("type" to Value("geojson"), "data" to Value(url)))).isError }
    }
    private fun dropBuildings(style: Style? = if (map.isValid()) map.style else null) {
        val id = buildingSource.id
        if (style != null && id != null && style.styleSourceExists(id)) style.removeStyleSource(id)
        buildingSource.dropped()
    }
    /** Counted by tools/dev/dynamic_farm/crash_repro.sh: one ADD per run, then only REUSE. */
    private fun buildingsLog(text: String) = Log.i("GodotMapPlugin", "DYNAMIC_BUILDINGS_SOURCE $text")
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
    /**
     * C-130 (C-129#6): 0.4.2 drew every DataSF building with a dark frame, so the visible building was the very footprint
     * the yellow/green/red fills use. C-112 removed that frame and left Mapbox's own buildings (OpenStreetMap, 1–2 m off
     * DataSF) as the visible ones, so the fills looked shifted. The DataSF buildings are drawn again, in Mapbox's own
     * building paint (no dark frame), right above Mapbox's building layer, which turns lighter beneath them.
     */
    private fun installBuildingBase(style: Style, buildings: String, minZoom: Double): Boolean {
        val mapbox = style.styleLayerExists(MAPBOX_BUILDINGS)
        val json = """{"id":"$BUILDING_BASE","type":"fill","source":"$buildings","minzoom":$minZoom,"paint":{"fill-opacity":1}}"""
        val position = if (mapbox) LayerPosition(MAPBOX_BUILDINGS, null, null) else LayerPosition(null, BUILDING_FILL, null)
        if (style.addStyleLayer(value(json), position).isError) return false
        fun copy(property: String, fallback: String) {
            val own = if (mapbox) style.getStyleLayerProperty(MAPBOX_BUILDINGS, property) else null
            val paint = own?.takeIf { it.kind != StylePropertyValueKind.UNDEFINED }?.value ?: Value(fallback)
            if (style.setStyleLayerProperty(BUILDING_BASE, property, paint).isError) style.setStyleLayerProperty(BUILDING_BASE, property, Value(fallback))
        }
        copy("fill-color", ParcelPayload.BUILDING_BASE_COLOR)
        copy("fill-outline-color", ParcelPayload.BUILDING_BASE_OUTLINE)
        if (mapbox && fadedBuildings == null) {
            fadedBuildings = style.getStyleLayerProperty(MAPBOX_BUILDINGS, "fill-opacity").value
            style.setStyleLayerProperty(MAPBOX_BUILDINGS, "fill-opacity", value(ParcelPayload.mapboxBuildingOpacity(minZoom)))
        }
        return true
    }
    private fun restoreMapboxBuildings(style: Style?) {
        val original = fadedBuildings ?: return
        if (style != null && style.styleLayerExists(MAPBOX_BUILDINGS)) style.setStyleLayerProperty(MAPBOX_BUILDINGS, "fill-opacity", original)
        fadedBuildings = null
    }
    /** C-130: the starter zone marker for this generation; "" removes it. A malformed zone is reported and not drawn. */
    fun setStarterZone(generation: Long, raw: String) {
        if (closed || !state.active || generation != state.generation) return
        zone = runCatching { ParcelPayload.starterZone(raw) }.getOrElse {
            zone = null; installZone(); error(generation, state.epoch, "invalid_starter_zone"); return
        }
        installZone()
    }
    /**
     * The zone's own source and layers: the map outside it washed in the panel tone, its edge a dashed line. Both sit
     * just under the base style's labels, so street names stay readable and every building colour (our layers on top)
     * stays as it is. They are not hit-tested: taps still go to the parcel and building layers.
     */
    private fun installZone(style: Style? = if (map.isValid()) map.style else null) {
        if (style == null) return
        removeZone(style)
        val marker = zone ?: return
        // Inline GeoJSON as an object (a plain string would be read as a URL), as the highlight source does.
        if (style.addStyleSource(ZONE_SOURCE, Value(hashMapOf("type" to Value("geojson"), "data" to value(ParcelPayload.starterZoneGeoJson(marker))))).isError) {
            error(state.generation, state.epoch, "starter_zone_failed"); return
        }
        // Above the base style's last non-label layer (roads, boundaries), i.e. under its label block. Streets also has
        // a few early symbol layers (building entrances); going under the first symbol would leave the roads unwashed.
        val ours = LAYERS + ZONE_LAYERS
        val ground = style.styleLayers.lastOrNull { it.type != "symbol" && it.id !in ours }?.id
        val position = if (ground != null) LayerPosition(ground, null, null) else LayerPosition(null, null, 0)
        val mask = """{"id":"$ZONE_MASK","type":"fill","source":"$ZONE_SOURCE","filter":["==",["get","kind"],"mask"],"paint":{"fill-color":"${marker.maskColor}","fill-opacity":${marker.maskOpacity}}}"""
        val edge = """{"id":"$ZONE_EDGE","type":"line","source":"$ZONE_SOURCE","filter":["==",["get","kind"],"edge"],"layout":{"line-join":"round","line-cap":"round"},"paint":{"line-color":"${marker.lineColor}","line-width":${marker.lineWidth},"line-dasharray":[2,1.5]}}"""
        if (style.addStyleLayer(value(mask), position).isError || style.addStyleLayer(value(edge), LayerPosition(ZONE_MASK, null, null)).isError) {
            removeZone(style); error(state.generation, state.epoch, "starter_zone_failed")
        }
    }
    private fun removeZone(style: Style?) {
        if (style == null) return
        for (layer in ZONE_LAYERS.reversed()) if (style.styleLayerExists(layer)) style.removeStyleLayer(layer)
        if (style.styleSourceExists(ZONE_SOURCE)) style.removeStyleSource(ZONE_SOURCE)
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
        query?.cancel(); query = null; waiting.drop(); config = null; claims = emptyMap(); zone = null
        removeLayers()
    }
    private fun removeLayers(style: Style? = if (map.isValid()) map.style else null) {
        if (style != null) {
            for (layer in LAYERS.reversed()) if (style.styleLayerExists(layer)) style.removeStyleLayer(layer)
            // The building source outlives its layer (C-118); only close() or a new URL/style drops it.
            for ((kind, id) in sources) if (kind != "buildings" && style.styleSourceExists(id)) style.removeStyleSource(id)
        }
        removeZone(style)
        restorePlaceIcons(style); restoreMapboxBuildings(style)
        sources.clear(); loaded.clear(); buildingSelection.clear(); settle.reset(emptySet()); sourceTimeout.reset()
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
