package io.engage.engage_flutter

import android.app.Application
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import io.engage.sdk.ForegroundPresentation
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class EngageFlutterStartupTest {
    private lateinit var application: Application

    @Before
    fun reset() {
        application = ApplicationProvider.getApplicationContext()
        application.getSharedPreferences("engage_flutter_startup", Context.MODE_PRIVATE).edit().clear().commit()
    }

    @Test
    fun `restores the validated configuration without a Flutter engine`() {
        EngageFlutterStartup.persist(application, configuration())

        val restored = EngageFlutterStartup.restore(application)

        assertNotNull(restored)
        assertEquals("eng_app_flutter_test", restored?.appKey)
        assertEquals("https://edge.example.test/v1/", restored?.endpoint.toString())
        assertEquals(ForegroundPresentation.SILENT, restored?.push?.foregroundPresentation)
    }

    @Test
    fun `discards a persisted configuration whose Android resources are invalid`() {
        EngageFlutterStartup.persist(
            application,
            configuration(
                android = mapOf(
                    "smallIconResource" to "missing_notification_icon",
                    "accentColorResource" to null,
                    "defaultChannelKey" to "general",
                    "channels" to emptyList<Any>(),
                    "categories" to emptyList<Any>(),
                ),
            ),
        )

        assertNull(EngageFlutterStartup.restore(application))
        assertNull(
            application.getSharedPreferences("engage_flutter_startup", Context.MODE_PRIVATE)
                .getString("configuration", null),
        )
    }

    @Test
    fun `background actions remain durable until Dart acknowledges them`() {
        assertEquals(
            true,
            EngageFlutterStartup.enqueuePendingAction(
                application,
                "open_order",
                buildJsonObject { put("order_id", "order-42") },
            ),
        )

        val pending = EngageFlutterStartup.pendingActions(application, "open_order").single()
        assertEquals("order-42", pending.arguments["order_id"]?.toString()?.trim('"'))

        EngageFlutterStartup.acknowledgeAction(application, pending.id)

        assertEquals(emptyList<PendingFlutterAction>(), EngageFlutterStartup.pendingActions(application, "open_order"))
    }

    @Test
    fun `push events received without Flutter remain durable until the event channel drains them`() {
        val event = mapOf(
            "type" to "OPENED",
            "deliveryId" to "delivery-1",
            "messageId" to "message-1",
            "deepLink" to "engage-test://orders/42",
            "data" to mapOf("merchant" to "Paris"),
        )
        assertEquals(true, EngageFlutterStartup.enqueuePushEvent(application, event))

        val pending = EngageFlutterStartup.pendingPushEvents(application).single()
        assertEquals(event, pending.event)

        EngageFlutterStartup.acknowledgePushEvent(application, pending.id)

        assertEquals(emptyList<PendingFlutterPushEvent>(), EngageFlutterStartup.pendingPushEvents(application))
    }

    private fun configuration(android: Map<String, Any?>? = null): FlutterMap = mapOf(
        "appKey" to "eng_app_flutter_test",
        "endpoint" to "https://edge.example.test/v1/",
        "push" to mapOf(
            "foregroundPresentation" to "SILENT",
            "android" to android,
            "ios" to null,
        ),
    )
}
