package com.sensen.map

import com.google.gson.JsonParser
import com.mapbox.geojson.Polygon
import com.mapbox.geojson.Point
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertFails
import kotlin.test.assertNull
import kotlin.test.assertNotNull

class ParcelR3Test {
    @Test fun officialStarIdentifierIsLiteralAndSeparatorsRemainForbidden() {
        val id = "p-4591A011*"
        assertEquals(true, ParcelPayload.validId(id))
        val row = """[{"block_id":"p-4591A011*","selected":true,"claimed":false,"own":false}]"""
        assertEquals(setOf(id), ParcelPayload.states(row).keys)
        val props = JsonParser.parseString("""{"block_id":"p-4591A011*","parcel_id":"4591A011*"}""").asJsonObject
        assertEquals(id, ParcelPayload.publicProperties(props)!!.get("block_id").asString)
        for (bad in listOf("p-a/b", "p-a\\b", "p-a|b", "p-a b", "p-a\nb", "p-a?b", "p-a#b")) assertFalse(ParcelPayload.validId(bad))
    }
    private val common = """"source_type":"vector","parcel_source_layer":"parcels","promote_id":"block_id","source_minzoom":15,"source_maxzoom":18,"min_zoom":16,"address_min_zoom":18,"building_source":"mapbox","mapbox_building_layers":["building"]"""
    @Test fun vectorTileJsonUsesDeclaredSourceLayerAndZoom() {
        val cfg = ParcelPayload.config("""{$common,"parcel_url":"https://demo.example/tilejson.json"}""")
        assertEquals("vector", cfg.sourceType); assertEquals("parcels", cfg.sourceLayer)
        assertEquals(15, cfg.sourceMinZoom); assertEquals(18, cfg.sourceMaxZoom)
        assertEquals("", cfg.buildingsUrl); assertEquals("mapbox", cfg.buildingSource)
    }
    @Test fun xyzBracesAreValidButIncompleteOrAmbiguousLocatorsAreNot() {
        val tiles = """"parcel_tiles":["https://demo.example/tiles/{z}/{x}/{y}.pbf"]"""
        assertEquals(1, ParcelPayload.config("{$common,$tiles}").tiles.size)
        assertFails { ParcelPayload.config("{$common,${tiles.replace("{y}", "0")}}") }
        assertFails { ParcelPayload.config("""{$common,$tiles,"parcel_url":"https://demo.example/tilejson.json"}""") }
        assertFails { ParcelPayload.config("{$common}") }
    }
    @Test fun vectorRequiresSourceLayerAndRejectsInvalidRanges() {
        assertFails { ParcelPayload.config("""{${common.replace("\"parcel_source_layer\":\"parcels\",", "")},"parcel_url":"https://demo.example/tilejson.json"}""") }
        assertFails { ParcelPayload.config("""{${common.replace("\"source_maxzoom\":18", "\"source_maxzoom\":14")},"parcel_url":"https://demo.example/tilejson.json"}""") }
    }
    @Test fun geoJsonFallbackKeepsMapboxBuildingModeWithoutDatasfDownload() {
        val cfg = ParcelPayload.config("""{"source_type":"geojson","parcel_url":"https://demo.example/index.geojson","promote_id":"block_id","min_zoom":16,"address_min_zoom":18,"building_source":"mapbox"}""")
        assertEquals("geojson", cfg.sourceType); assertEquals("", cfg.buildingsUrl)
        assertEquals(listOf("building"), cfg.mapboxBuildingLayers)
        assertFails { ParcelPayload.config("""{"source_type":"geojson","parcel_url":"https://demo.example/index.geojson","promote_id":"block_id","min_zoom":16,"address_min_zoom":18,"building_source":"datasf"}""") }
    }
    @Test fun vectorMetadataCenterIsReconstructedWithoutInventingAreaOrLeakingGeometry() {
        val input = JsonParser.parseString("""{"block_id":"p-3139019","parcel_id":"3139019","center_lon":-122.45,"center_lat":37.73,"geometry":{"coordinates":[1,2]},"height":18,"mapbox_id":"private-provider-id"}""").asJsonObject
        val output = ParcelPayload.publicProperties(input)!!
        assertEquals(-122.45, output.getAsJsonArray("center")[0].asDouble)
        assertEquals(37.73, output.getAsJsonArray("center")[1].asDouble)
        assertFalse(output.has("source_area_m2")); assertFalse(output.has("bbox"))
        assertFalse(output.has("geometry")); assertFalse(output.has("height")); assertFalse(output.has("mapbox_id"))
    }
    private fun geometry() = Polygon.fromLngLats(listOf(listOf(Point.fromLngLat(0.0,0.0),Point.fromLngLat(1.0,0.0),Point.fromLngLat(1.0,1.0),Point.fromLngLat(0.0,0.0))))
    @Test fun opaqueKeyIsBoundToGenerationAndStyleAndNewestTap() {
        var number = 0
        val selection = ParcelBuildingSelection { "opaque-${++number}" }
        val first = selection.remember(ParcelTicket(1,2,3),geometry())
        assertNotNull(selection.lookup(1,2,first))
        assertNull(selection.lookup(2,2,first)); assertNull(selection.lookup(1,3,first))
        val second = selection.remember(ParcelTicket(1,2,4),geometry())
        assertNull(selection.lookup(1,2,first)); assertNotNull(selection.lookup(1,2,second))
        selection.clear(); assertNull(selection.lookup(1,2,second))
    }
    @Test fun emptyOrUnknownKeyCannotSelectProviderGeometry() {
        val selection = ParcelBuildingSelection()
        selection.remember(ParcelTicket(1,1,1),geometry())
        assertNull(selection.lookup(1,1,"")); assertNull(selection.lookup(1,1,"building-123"))
    }
}
