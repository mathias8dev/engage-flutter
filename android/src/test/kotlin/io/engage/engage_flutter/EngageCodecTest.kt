package io.engage.engage_flutter

import androidx.test.core.app.ApplicationProvider
import io.engage.sdk.EngageLogLevel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.net.URI
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class EngageCodecTest {
    @Test
    fun `missing Flutter arguments decode as an empty map`() {
        assertTrue(null.asMapOrEmpty().isEmpty())
    }

    @Test
    fun `Flutter warning log level maps to Android warn`() {
        val config = mapOf(
            "appKey" to "eng_app_test",
            "endpoint" to "https://edge.example.test/v1/",
            "legacyEndpoints" to listOf("https://old-edge.example.test/v1/"),
            "logLevel" to "WARNING",
            "push" to mapOf("foregroundPresentation" to "SHOW"),
        ).toEngageConfig(ApplicationProvider.getApplicationContext())

        assertEquals(EngageLogLevel.WARN, config.logLevel)
        assertEquals(listOf("https://old-edge.example.test/v1/"), config.legacyEndpoints.map(URI::toString))
    }
}
