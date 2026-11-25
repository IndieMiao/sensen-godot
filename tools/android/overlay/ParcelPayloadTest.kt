package com.sensen.map

import com.google.gson.JsonParser
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertFails
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class ParcelPayloadTest {
    private val config = """{"parcel_url":"https://demo.example/r2/index.geojson","buildings_url":"https://demo.example/r2/buildings.geojson","min_zoom":17,"address_min_zoom":18,"promote_id":"block_id"}"""
    @Test fun usesNativeUrlSourcesAndCanonicalPrefixedIdContract() {
        val c = ParcelPayload.config(config)
        assertEquals("https://demo.example/r2/index.geojson", c.parcelUrl)
        assertEquals(17.0, c.minZoom); assertEquals(18.0, c.addressMinZoom)
        assertFails { ParcelPayload.config(config.replace("block_id", "parcel_id")) }
    }
    @Test fun refetchBuildingsIsAnOptionalBoolean() {
        assertFalse(ParcelPayload.config(config).refetchBuildings)
        assertTrue(ParcelPayload.config(config.replace("}", ",\"refetch_buildings\":true}")).refetchBuildings)
        assertFails { ParcelPayload.config(config.replace("}", ",\"refetch_buildings\":\"true\"}")) }
    }
    @Test fun rejectsLocalFileCleartextCredentialAndInvalidZoomSources() {
        for (url in listOf("file:///tmp/index.geojson", "http://demo.example/index.geojson", "https://name:secret@demo.example/index.geojson")) {
            assertFails { ParcelPayload.config(config.replace("https://demo.example/r2/index.geojson", url)) }
        }
        assertFails { ParcelPayload.config(config.replace("\"address_min_zoom\":18", "\"address_min_zoom\":16")) }
    }
    @Test fun statesUseBlockIdAndRequireExplicitBooleans() {
        val row = """{"block_id":"p-3139010","selected":false,"claimed":true,"own":false}"""
        assertTrue(ParcelPayload.states("[$row]").getValue("p-3139010").claimed)
        assertFails { ParcelPayload.states("[${row.replace("block_id", "parcel_id") }]") }
        assertFails { ParcelPayload.states("[${row.replace("p-3139010", "3139010") }]") }
        assertFails { ParcelPayload.states("[${row.replace("\"selected\":false", "\"selected\":\"false\"") }]") }
    }
    @Test fun refusesDuplicateAndPartialStateRatherThanSilentClearing() {
        val row = """{"block_id":"p-3139010","selected":false,"claimed":false,"own":false}"""
        assertFails { ParcelPayload.states("[$row,$row]") }
        assertFails { ParcelPayload.states("""[{"block_id":"p-3139010","selected":true}]""") }
        assertTrue(ParcelPayload.states("[$row]").values.single().empty)
    }
    @Test fun claimNicknameIsDataNotAnExpressionAndNoDeviceIdentityIsForwarded() {
        val raw = """[{"block_id":"p-3139010","nickname":"[\"get\",\"secret\"] 小猫","center":[-122.45,37.73],"device_id":"never-export"}]"""
        val names = ParcelPayload.claims(raw)
        assertEquals(mapOf("p-3139010" to "[\"get\",\"secret\"] 小猫"), names)
        val label = JsonParser.parseString(ParcelPayload.claimLabel(names)).asJsonArray
        assertEquals("match", label[0].asString)
        assertEquals("p-3139010", label[2].asString)
        assertTrue(label[3].isJsonPrimitive && label[3].asJsonPrimitive.isString) // never an array/expression
        assertEquals("[\"get\",\"secret\"] 小猫", label[3].asString)
        assertEquals("", label[4].asString)
        assertFalse(ParcelPayload.claimLabel(names).contains("never-export"))
    }
    @Test fun emptyClaimsClearLabelsAndBadRowsAreRefused() {
        assertTrue(ParcelPayload.claims("[]").isEmpty())
        assertEquals("\"\"", ParcelPayload.claimLabel(emptyMap()))
        val filter = JsonParser.parseString(ParcelPayload.claimFilter(emptyMap())).asJsonArray
        assertEquals("in", filter[0].asString); assertEquals(0, filter[2].asJsonArray[1].asJsonArray.size())
        assertEquals("p-a", JsonParser.parseString(ParcelPayload.claimFilter(mapOf("p-a" to "A"))).asJsonArray[2].asJsonArray[1].asJsonArray[0].asString)
        assertFails { ParcelPayload.claims("""[{"block_id":"p-a","nickname":""}]""") }
        assertFails { ParcelPayload.claims("""[{"block_id":"3139010","nickname":"a"}]""") }
        assertFails { ParcelPayload.claims("""[{"block_id":"p-a","nickname":"a"},{"block_id":"p-a","nickname":"b"}]""") }
    }
    @Test fun datasfHighlightFilterMatchesOneParcelsFootprintsAndNothingForBadIds() {
        assertEquals("""["==",["get","block_id"],"p-3250003"]""", ParcelPayload.buildingFilter("p-3250003"))
        assertEquals("""["==",["get","block_id"],""]""", ParcelPayload.buildingFilter(""))
        assertEquals("""["==",["get","block_id"],""]""", ParcelPayload.buildingFilter("3250003"))
        assertEquals("""["==",["get","block_id"],""]""", ParcelPayload.buildingFilter("p-a\"]"))
    }
    @Test fun buildingPaintColoursOnlyOwnedParcelsBuildings() {
        val states = mapOf("p-own" to ParcelVisualState(own = true), "p-taken" to ParcelVisualState(claimed = true),
            "p-chosen" to ParcelVisualState(selected = true, claimed = true))
        assertEquals("""["match",["get","block_id"],["p-own"],"#3E9B55","#D2493F"]""", ParcelPayload.buildingColor(states))
        // Own 0.55, someone else's 0.5, deeper while selected; every other building is not drawn.
        assertEquals("""["match",["get","block_id"],["p-own"],0.55,["p-taken"],0.5,["p-chosen"],0.7,0.0]""", ParcelPayload.buildingOpacity(states))
        val mine = mapOf("p-own" to ParcelVisualState(own = true, selected = true))
        assertEquals("""["match",["get","block_id"],["p-own"],0.75,0.0]""", ParcelPayload.buildingOpacity(mine))
    }
    @Test fun buildingPaintWithoutStatesStaysAValidFeatureDependentMatch() {
        // A constant 0 could drop the layer from Mapbox's hit index, and match needs at least one label: a
        // never-matching "" that takes the fallback value.
        assertEquals("""["match",["get","block_id"],"","#D2493F","#D2493F"]""", ParcelPayload.buildingColor(emptyMap()))
        assertEquals("""["match",["get","block_id"],"",0.0,0.0]""", ParcelPayload.buildingOpacity(emptyMap()))
        assertEquals("""["match",["get","block_id"],"",0.0,0.0]""", ParcelPayload.buildingOpacity(mapOf("p-a" to ParcelVisualState(selected = true))))
    }
    @Test fun onlyWhitelistedOwnSourcePropertiesAreReturned() {
        val input = JsonParser.parseString("""{"block_id":"p-3139010","parcel_id":"3139010","address":null,"center":[-122,37],"geometry":{"type":"Polygon"},"device_id":"secret","other":"omit"}""").asJsonObject
        val output = ParcelPayload.publicProperties(input)!!
        assertEquals("p-3139010", output.get("block_id").asString)
        assertEquals("3139010", output.get("parcel_id").asString)
        assertTrue(output.get("address").isJsonNull); assertNotNull(output.get("center"))
        assertFalse(output.has("geometry")); assertFalse(output.has("device_id")); assertFalse(output.has("other"))
    }
    @Test fun bareParcelIdsCannotBeUsedAsClaimOrSelectionIds() {
        assertNull(ParcelPayload.publicProperties(JsonParser.parseString("""{"parcel_id":"3139010"}""").asJsonObject))
        assertNull(ParcelPayload.publicProperties(JsonParser.parseString("""{"block_id":"3139010"}""").asJsonObject))
    }
    // C-130: the starter zone marker.
    private val zone = """{"boundary":[[-122.409,37.800],[-122.406,37.801],[-122.405,37.798],[-122.408,37.797],[-122.409,37.800]],"line_color":"#3E7D43","line_width":3.0,"mask_color":"#FBF8F1","mask_opacity":0.45}"""
    @Test fun starterZoneIsAClosedRingWithAStyleOrNothing() {
        assertNull(ParcelPayload.starterZone(""))
        val marker = ParcelPayload.starterZone(zone)!!
        assertEquals(5, marker.ring.size); assertEquals("#3E7D43", marker.lineColor); assertEquals(0.45, marker.maskOpacity)
        assertFails { ParcelPayload.starterZone(zone.replace("[-122.409,37.800]]", "[-122.409,37.801]]")) } // Open ring.
        assertFails { ParcelPayload.starterZone(zone.replace("#3E7D43", "red")) }
        assertFails { ParcelPayload.starterZone(zone.replace("0.45", "1.5")) }
        assertFails { ParcelPayload.starterZone(zone.replace("\"line_width\":3.0,", "")) }
        assertFails { ParcelPayload.starterZone(zone.replace("37.797", "95.0")) }
        assertFails { ParcelPayload.starterZone("[]") }
    }
    @Test fun starterZoneMaskHasTheZoneAsAnOppositelyWoundHoleAndAnEdgeLine() {
        for (raw in listOf(zone, zone.replace("[[-122.409,37.800],[-122.406,37.801],[-122.405,37.798],[-122.408,37.797],[-122.409,37.800]]",
                "[[-122.409,37.800],[-122.408,37.797],[-122.405,37.798],[-122.406,37.801],[-122.409,37.800]]"))) {
            val features = JsonParser.parseString(ParcelPayload.starterZoneGeoJson(ParcelPayload.starterZone(raw)!!)).asJsonObject.getAsJsonArray("features")
            val mask = features[0].asJsonObject; val edge = features[1].asJsonObject
            assertEquals("mask", mask.getAsJsonObject("properties").get("kind").asString)
            val rings = mask.getAsJsonObject("geometry").getAsJsonArray("coordinates").map { r -> r.asJsonArray.map { p -> p.asJsonArray[0].asDouble to p.asJsonArray[1].asDouble } }
            assertEquals(2, rings.size)
            assertTrue(ParcelPayload.signedArea(rings[0]) > 0 && ParcelPayload.signedArea(rings[1]) < 0, "world outer ring and zone hole wind oppositely")
            assertEquals("edge", edge.getAsJsonObject("properties").get("kind").asString)
            assertEquals("LineString", edge.getAsJsonObject("geometry").get("type").asString)
        }
    }
    @Test fun mapboxBuildingsFadeOnlyFromTheParcelZoom() {
        assertEquals("""["interpolate",["linear"],["zoom"],15,0,16.0,0.3]""", ParcelPayload.mapboxBuildingOpacity(16.0))
        assertEquals("""["interpolate",["linear"],["zoom"],15,0,15.5,0.3]""", ParcelPayload.mapboxBuildingOpacity(12.0))
    }
}
