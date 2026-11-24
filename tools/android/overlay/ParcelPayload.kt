package com.sensen.map

import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import com.google.gson.JsonPrimitive
import java.net.URI

internal data class ParcelSourceConfig(
    val parcelUrl: String, val buildingsUrl: String, val minZoom: Double, val addressMinZoom: Double,
    val sourceType: String = "geojson", val tiles: List<String> = emptyList(), val sourceLayer: String? = null,
    val sourceMinZoom: Int = 0, val sourceMaxZoom: Int = 22,
    val buildingSource: String = "datasf", val mapboxBuildingLayers: List<String> = listOf("building"),
    /** C-124: set by the player's Retry or the building load timeout; a building copy still loading is fetched again. */
    val refetchBuildings: Boolean = false,
)
internal object ParcelPayload {
    const val EMPTY_COLLECTION = "{\"type\":\"FeatureCollection\",\"features\":[]}"
    private val idPattern = Regex("p-[A-Za-z0-9._:*-]{1,126}")
    val propertyKeys = setOf("block_id", "parcel_id", "selection_unit", "name", "address", "address_count", "center", "center_lon", "center_lat", "bbox", "cell_count", "core_cell_count", "extension_cell_count", "total_cell_count", "farm_path", "source_area_m2", "inset_area_m2", "building_count")
    fun validId(id: String): Boolean = idPattern.matches(id)
    fun config(raw: String): ParcelSourceConfig {
        require(raw.length <= 16384)
        val input = JsonParser.parseString(raw).asJsonObject
        require(input.get("promote_id")?.asString == "block_id") { "promote_id_must_be_block_id" }
        fun url(text: String, template: Boolean = false): String {
            var parsed = text
            if (template) {
                for (key in listOf("{z}", "{x}", "{y}")) {
                    require(parsed.split(key).size == 2) { "xyz_template_required" }
                    parsed = parsed.replace(key, "0")
                }
            }
            val uri = URI(parsed)
            require(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.rawUserInfo == null && uri.fragment == null) { "https_source_required" }
            return text
        }
        val type = input.get("source_type")?.asString ?: "geojson"
        val building = input.get("building_source")?.asString ?: "datasf"
        require(type in listOf("geojson", "vector") && building in listOf("mapbox", "datasf"))
        val parcelUrl = input.get("parcel_url")?.takeUnless { it.isJsonNull }?.asString.orEmpty()
        val tiles = input.getAsJsonArray("parcel_tiles")?.map { url(it.asString, true) }.orEmpty()
        require(tiles.size <= 4)
        val layer = input.get("parcel_source_layer")?.takeUnless { it.isJsonNull }?.asString
        val sourceMin = if (type == "vector") input.get("source_minzoom")?.asInt ?: 15 else 0
        val sourceMax = if (type == "vector") input.get("source_maxzoom")?.asInt ?: 18 else 22
        if (type == "vector") {
            require((parcelUrl.isNotEmpty()) != tiles.isNotEmpty()) { "one_tile_locator_required" }
            require(layer != null && Regex("[A-Za-z0-9_-]{1,64}").matches(layer)) { "source_layer_required" }
            require(sourceMin in 0..sourceMax && sourceMax <= 22)
        } else require(parcelUrl.isNotEmpty() && tiles.isEmpty())
        if (parcelUrl.isNotEmpty()) url(parcelUrl)
        val buildingsUrl = input.get("buildings_url")?.takeUnless { it.isJsonNull }?.asString.orEmpty()
        if (building == "datasf") url(buildingsUrl)
        val layers = input.getAsJsonArray("mapbox_building_layers")?.map { it.asString } ?: listOf("building")
        require(layers.size in 1..8 && layers.distinct().size == layers.size && layers.all { Regex("[A-Za-z0-9_-]{1,80}").matches(it) })
        val min = input.get("min_zoom").asDouble; val address = input.get("address_min_zoom").asDouble
        require(min.isFinite() && address.isFinite() && min in 0.0..22.0 && address in min..22.0)
        val refetch = input.get("refetch_buildings")?.let { require(it.isJsonPrimitive && it.asJsonPrimitive.isBoolean); it.asBoolean } ?: false
        return ParcelSourceConfig(parcelUrl, buildingsUrl, min, address, type, tiles, layer, sourceMin, sourceMax, building, layers, refetch)
    }
    fun states(raw: String): Map<String, ParcelVisualState> {
        require(raw.length <= 1024 * 1024)
        val batch = JsonParser.parseString(raw).asJsonArray
        require(batch.size() <= 3000)
        val result = linkedMapOf<String, ParcelVisualState>()
        for (entry in batch) {
            val item = entry.asJsonObject
            val idValue = item.get("block_id") ?: error("block_id_required")
            require(idValue.isJsonPrimitive && idValue.asJsonPrimitive.isString)
            val id = idValue.asString
            require(validId(id) && !result.containsKey(id))
            fun bit(name: String): Boolean {
                val value = item.get(name) ?: error("state_field_missing")
                require(value.isJsonPrimitive && value.asJsonPrimitive.isBoolean)
                return value.asBoolean
            }
            result[id] = ParcelVisualState(bit("selected"), bit("claimed"), bit("own"))
        }
        return result
    }
    /** Claimer names keyed by parcel. Nicknames stay plain strings: they become string literals, never expressions. */
    fun claims(raw: String): Map<String, String> {
        require(raw.length <= 1024 * 1024)
        val input = JsonParser.parseString(raw).asJsonArray
        require(input.size() <= 3000)
        val names = linkedMapOf<String, String>()
        for (entry in input) {
            val item = entry.asJsonObject
            val id = item.get("block_id").asString; require(validId(id) && !names.containsKey(id))
            val nickname = item.get("nickname").asString; require(nickname.length in 1..80)
            names[id] = nickname
        }
        return names
    }
    /** text-field for the parcel source: each claimed block_id maps to its claimer's name, everything else to "". */
    fun claimLabel(names: Map<String, String>): String {
        if (names.isEmpty()) return JsonPrimitive("").toString()
        return JsonArray().apply {
            add("match"); add(JsonArray().apply { add("get"); add("block_id") })
            for ((id, nickname) in names) { add(id); add(nickname) }
            add("")
        }.toString()
    }
    /** Only claimed parcels are labelled; an empty filter list still parses as a valid expression. */
    fun claimFilter(names: Map<String, String>): String = JsonArray().apply {
        add("in"); add(JsonArray().apply { add("get"); add("block_id") })
        add(JsonArray().apply { add("literal"); add(JsonArray().apply { names.keys.forEach { add(it) } }) })
    }.toString()
    // C-112 (C-103#18): the buildings of one's own parcel green, of someone else's red, deeper while selected; others
    // are not drawn. Claimable yellow is the selected building's highlight (C-28).
    const val OWN_COLOR = "#3E9B55"
    const val TAKEN_COLOR = "#D2493F"
    const val CLAIMABLE_COLOR = "#FFD15C"
    const val OWN_OPACITY = 0.55
    const val OWN_SELECTED_OPACITY = 0.75
    const val TAKEN_OPACITY = 0.5
    const val TAKEN_SELECTED_OPACITY = 0.7
    /**
     * `["match", ["get","block_id"], [ids…], value, …, fallback]`: a hash lookup per building however many parcels are
     * owned. Empty groups are left out; with none left a never-matching "" (given the fallback) keeps it a valid,
     * feature-dependent expression, so the layer stays hit-tested when nothing is owned.
     */
    private fun byParcel(groups: List<Pair<Collection<String>, Any>>, fallback: Any): String = JsonArray().apply {
        fun put(value: Any) = if (value is Number) add(value) else add(value.toString())
        add("match"); add(JsonArray().apply { add("get"); add("block_id") })
        val used = groups.filter { it.first.isNotEmpty() }
        if (used.isEmpty()) { add(""); put(fallback) }
        for ((ids, value) in used) { add(JsonArray().apply { ids.forEach { add(it) } }); put(value) }
        put(fallback)
    }.toString()
    private fun ids(states: Map<String, ParcelVisualState>, test: (ParcelVisualState) -> Boolean) = states.filterValues(test).keys
    /** fill-color of the DataSF building layer. */
    fun buildingColor(states: Map<String, ParcelVisualState>): String = byParcel(listOf(ids(states) { it.own } to OWN_COLOR), TAKEN_COLOR)
    /** fill-opacity of the DataSF building layer: 0 for every building whose parcel is neither own nor someone else's. */
    fun buildingOpacity(states: Map<String, ParcelVisualState>): String = byParcel(listOf(
        ids(states) { it.own && !it.selected } to OWN_OPACITY, ids(states) { it.own && it.selected } to OWN_SELECTED_OPACITY,
        ids(states) { it.claimed && !it.own && !it.selected } to TAKEN_OPACITY, ids(states) { it.claimed && !it.own && it.selected } to TAKEN_SELECTED_OPACITY,
    ), 0.0)
    /** DataSF highlight: every footprint of one parcel, since its farm core is all of them (C-43 V-199). "" matches none. */
    fun buildingFilter(parcelId: String): String = JsonArray().apply {
        add("=="); add(JsonArray().apply { add("get"); add("block_id") }); add(if (validId(parcelId)) parcelId else "")
    }.toString()
    /** Copy only our public selection metadata; never geometry, device identity or arbitrary properties. */
    fun publicProperties(properties: JsonObject): JsonObject? {
        val id = properties.get("block_id") ?: return null
        if (!id.isJsonPrimitive || !id.asJsonPrimitive.isString || !validId(id.asString)) return null
        return JsonObject().apply {
            for (key in propertyKeys) properties.get(key)?.let { add(key, it) }
            if (!has("center") && properties.get("center_lon")?.isJsonPrimitive == true && properties.get("center_lat")?.isJsonPrimitive == true) {
                val lon = runCatching { properties.get("center_lon").asDouble }.getOrNull()
                val lat = runCatching { properties.get("center_lat").asDouble }.getOrNull()
                if (lon != null && lat != null && lon.isFinite() && lat.isFinite() && lon in -180.0..180.0 && lat in -90.0..90.0) {
                    add("center", JsonArray().apply { add(lon); add(lat) })
                }
            }
        }
    }
}
