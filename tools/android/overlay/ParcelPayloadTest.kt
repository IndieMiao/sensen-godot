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
        val raw = """[{"block_id":"p-3139010","nickname":"[get,secret] 小猫","center":[-122.45,37.73],"device_id":"never-export"}]"""
        val json = ParcelPayload.claims(raw)
        assertFalse(json.contains("never-export")); assertFalse(json.contains("device_id"))
        val f = JsonParser.parseString(json).asJsonObject.getAsJsonArray("features")[0].asJsonObject
        assertEquals("Point", f.getAsJsonObject("geometry").get("type").asString)
        assertEquals("[get,secret] 小猫", f.getAsJsonObject("properties").get("nickname").asString)
    }
    @Test fun emptyClaimsClearsSourceAndInvalidCoordinatesAreRefused() {
        assertEquals(ParcelPayload.EMPTY_COLLECTION, ParcelPayload.claims("[]"))
        assertFails { ParcelPayload.claims("""[{"block_id":"p-a","nickname":"a","center":[200,37]}]""") }
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
}
