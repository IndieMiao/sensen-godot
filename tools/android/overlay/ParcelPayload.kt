package com.sensen.map

import com.google.gson.JsonArray
import com.google.gson.JsonObject
import com.google.gson.JsonParser
import java.net.URI

internal data class ParcelSourceConfig(val parcelUrl: String, val buildingsUrl: String, val minZoom: Double, val addressMinZoom: Double)
internal object ParcelPayload {
    const val EMPTY_COLLECTION = "{\"type\":\"FeatureCollection\",\"features\":[]}"
    private val idPattern = Regex("p-[A-Za-z0-9._:-]{1,126}")
    val propertyKeys = setOf("block_id", "parcel_id", "selection_unit", "name", "address", "address_count", "center", "bbox", "cell_count", "farm_path", "source_area_m2", "inset_area_m2", "building_count")
    fun validId(id: String): Boolean = idPattern.matches(id)
    fun config(raw: String): ParcelSourceConfig {
        require(raw.length <= 16384)
        val input = JsonParser.parseString(raw).asJsonObject
        require(input.get("promote_id")?.asString == "block_id") { "promote_id_must_be_block_id" }
        fun url(key: String): String {
            val text = input.get(key).asString
            val uri = URI(text)
            require(uri.scheme == "https" && !uri.host.isNullOrBlank() && uri.rawUserInfo == null && uri.fragment == null) { "https_source_required" }
            return text
        }
        val min = input.get("min_zoom").asDouble; val address = input.get("address_min_zoom").asDouble
        require(min.isFinite() && address.isFinite() && min in 0.0..22.0 && address in min..22.0)
        return ParcelSourceConfig(url("parcel_url"), url("buildings_url"), min, address)
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
    fun claims(raw: String): String {
        require(raw.length <= 1024 * 1024)
        val input = JsonParser.parseString(raw).asJsonArray
        require(input.size() <= 3000)
        val ids = hashSetOf<String>(); val features = JsonArray()
        for (entry in input) {
            val item = entry.asJsonObject
            val id = item.get("block_id").asString; require(validId(id) && ids.add(id))
            val nickname = item.get("nickname").asString; require(nickname.length in 1..80)
            val xy = item.getAsJsonArray("center"); require(xy.size() == 2)
            val lng = xy[0].asDouble; val lat = xy[1].asDouble
            require(lng.isFinite() && lat.isFinite() && lng in -180.0..180.0 && lat in -90.0..90.0)
            features.add(JsonObject().apply {
                addProperty("type", "Feature"); addProperty("id", id)
                add("geometry", JsonObject().apply { addProperty("type", "Point"); add("coordinates", xy) })
                add("properties", JsonObject().apply { addProperty("block_id", id); addProperty("nickname", nickname) })
            })
        }
        return JsonObject().apply { addProperty("type", "FeatureCollection"); add("features", features) }.toString()
    }
    /** Copy only our public selection metadata; never geometry, device identity or arbitrary properties. */
    fun publicProperties(properties: JsonObject): JsonObject? {
        val id = properties.get("block_id") ?: return null
        if (!id.isJsonPrimitive || !id.asJsonPrimitive.isString || !validId(id.asString)) return null
        return JsonObject().apply { for (key in propertyKeys) properties.get(key)?.let { add(key, it) } }
    }
}
