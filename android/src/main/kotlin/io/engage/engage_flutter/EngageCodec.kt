package io.engage.engage_flutter

import android.content.Context
import io.engage.sdk.AndroidPushAction
import io.engage.sdk.AndroidPushCategory
import io.engage.sdk.AndroidPushChannel
import io.engage.sdk.AndroidPushConfig
import io.engage.sdk.AndroidPushSound
import io.engage.sdk.EmbeddedPresentation
import io.engage.sdk.EngageConfig
import io.engage.sdk.EngageLogLevel
import io.engage.sdk.InAppContent
import io.engage.sdk.InboxEntry
import io.engage.sdk.InboxError
import io.engage.sdk.InboxPagerState
import io.engage.sdk.NotificationImportance
import io.engage.sdk.OverlayPresentation
import io.engage.sdk.PreferenceCenterSnapshot
import io.engage.sdk.PresentationSpec
import io.engage.sdk.PushConfig
import io.engage.sdk.PushEvent
import io.engage.sdk.PushStatus
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.longOrNull
import java.net.URI

internal typealias FlutterMap = Map<String, Any?>

internal fun Any?.asMap(): FlutterMap = (this as? Map<*, *>)
    ?.entries
    ?.associate { (key, value) -> key.toString() to value }
    ?: error("Expected a map, got ${this?.javaClass?.name}")

internal fun Any?.asMapOrEmpty(): FlutterMap =
    if (this == null) emptyMap() else asMap()

internal fun Any?.asList(): List<Any?> = (this as? List<*>)?.toList().orEmpty()

internal inline fun <reified T : Enum<T>> enumValue(raw: Any?): T = enumValueOf(raw as String)

internal fun FlutterMap.string(key: String): String = requireNotNull(this[key] as? String) {
    "Missing string: $key"
}

internal fun FlutterMap.boolean(key: String): Boolean = requireNotNull(this[key] as? Boolean) {
    "Missing boolean: $key"
}

internal fun FlutterMap.toEngageConfig(context: Context): EngageConfig {
    val push = this["push"].asMap()
    return EngageConfig(
        appKey = string("appKey"),
        endpoint = URI.create(string("endpoint")),
        logLevel = when (val raw = this["logLevel"] as? String ?: "INFO") {
            "WARNING" -> EngageLogLevel.WARN
            else -> enumValue(raw)
        },
        push = PushConfig(
            foregroundPresentation = enumValue(push["foregroundPresentation"]),
            android = push["android"]?.asMap()?.toAndroidPushConfig(context),
        ),
    )
}

private fun FlutterMap.toAndroidPushConfig(context: Context): AndroidPushConfig {
    val resources = context.resources
    val packageName = context.packageName
    fun resource(name: String, type: String): Int {
        val normalized = name.substringAfterLast('/').substringAfterLast('.')
        val id = resources.getIdentifier(normalized, type, packageName)
        require(id != 0) { "Android resource $type/$normalized does not exist in $packageName" }
        return id
    }
    return AndroidPushConfig(
        smallIcon = resource(string("smallIconResource"), "drawable"),
        accentColor = (this["accentColorResource"] as? String)?.let { resource(it, "color") },
        defaultChannelKey = string("defaultChannelKey"),
        channels = this["channels"].asList().map { value ->
            val channel = value.asMap()
            val sound = channel["sound"].asMap()
            AndroidPushChannel(
                key = channel.string("key"),
                name = resource(channel.string("nameResource"), "string"),
                description = (channel["descriptionResource"] as? String)?.let { resource(it, "string") },
                importance = enumValue<NotificationImportance>(channel["importance"]),
                showBadge = channel.boolean("showBadge"),
                sound = when (sound.string("type")) {
                    "DEFAULT" -> AndroidPushSound.Default
                    "SILENT" -> AndroidPushSound.Silent
                    "RESOURCE" -> AndroidPushSound.Resource(resource(sound.string("rawResource"), "raw"))
                    else -> error("Unsupported Android push sound: ${sound["type"]}")
                },
            )
        },
        categories = this["categories"].asList().map { value ->
            val category = value.asMap()
            AndroidPushCategory(
                key = category.string("key"),
                actions = category["actions"].asList().map { actionValue ->
                    val action = actionValue.asMap()
                    AndroidPushAction(
                        key = action.string("key"),
                        title = resource(action.string("titleResource"), "string"),
                        opensApp = action.boolean("opensApp"),
                    )
                },
            )
        },
    )
}

internal fun Any?.toJsonElement(): JsonElement = when (this) {
    null -> JsonNull
    is JsonElement -> this
    is String -> JsonPrimitive(this)
    is Boolean -> JsonPrimitive(this)
    is Byte -> JsonPrimitive(toInt())
    is Short -> JsonPrimitive(toInt())
    is Int -> JsonPrimitive(this)
    is Long -> JsonPrimitive(this)
    is Float -> JsonPrimitive(toDouble())
    is Double -> JsonPrimitive(this)
    is Map<*, *> -> JsonObject(entries.associate { (key, value) -> key.toString() to value.toJsonElement() })
    is List<*> -> JsonArray(map { it.toJsonElement() })
    else -> error("Unsupported JSON value: ${javaClass.name}")
}

internal fun JsonElement.toFlutter(): Any? = when (this) {
    JsonNull -> null
    is JsonObject -> entries.associate { (key, value) -> key to value.toFlutter() }
    is JsonArray -> map(JsonElement::toFlutter)
    is JsonPrimitive -> when {
        isString -> content
        booleanOrNull != null -> booleanOrNull
        longOrNull != null -> longOrNull
        doubleOrNull != null -> doubleOrNull
        else -> contentOrNull
    }
}

internal fun PushStatus.toFlutter(): FlutterMap = mapOf(
    "permission" to permission.name,
    "subscription" to subscription.name,
    "tokenRegistered" to tokenRegistered,
)

internal fun PushEvent.toFlutter(): FlutterMap = when (this) {
    is PushEvent.Received -> mapOf(
        "type" to "RECEIVED",
        "deliveryId" to deliveryId,
        "messageId" to messageId,
        "data" to data,
    )
    is PushEvent.Opened -> mapOf(
        "type" to "OPENED",
        "deliveryId" to deliveryId,
        "messageId" to messageId,
        "deepLink" to deepLink,
        "data" to data,
    )
    is PushEvent.Dismissed -> mapOf(
        "type" to "DISMISSED",
        "deliveryId" to deliveryId,
        "messageId" to messageId,
    )
    is PushEvent.ActionSelected -> mapOf(
        "type" to "ACTION_SELECTED",
        "deliveryId" to deliveryId,
        "messageId" to messageId,
        "actionKey" to actionKey,
        "data" to data,
    )
}

internal fun InAppContent.toFlutter(): FlutterMap = mapOf(
    "experienceId" to experienceId,
    "messageId" to messageId,
    "variantId" to variantId,
    "type" to type.name,
    "payload" to payload.toFlutter(),
    "presentation" to presentation.toFlutter(),
)

private fun PresentationSpec.toFlutter(): FlutterMap = when (this) {
    is OverlayPresentation -> mapOf(
        "kind" to "OVERLAY",
        "format" to format.name,
        "position" to position?.name,
        "backdrop" to backdrop.name,
        "dismissal" to dismissal.name,
        "animation" to animation.name,
        "autoDismissAfterSeconds" to autoDismissAfterSeconds,
    )
    is EmbeddedPresentation -> mapOf(
        "kind" to "EMBEDDED",
        "placementKey" to placementKey,
        "emptyState" to emptyState.name,
    )
}

internal fun PreferenceCenterSnapshot.toFlutter(): FlutterMap = mapOf(
    "key" to key,
    "displayName" to displayName,
    "description" to description,
    "sections" to sections.map { section ->
        mapOf(
            "key" to section.key,
            "title" to section.title,
            "description" to section.description,
            "subscriptions" to section.subscriptions.map { subscription ->
                mapOf(
                    "key" to subscription.key,
                    "displayName" to subscription.displayName,
                    "description" to subscription.description,
                    "profileChoices" to subscription.profileChoices?.mapKeys { it.key.name },
                    "installationChoice" to subscription.installationChoice,
                )
            },
        )
    },
)

internal fun InboxPagerState.toFlutter(): FlutterMap = mapOf(
    "entries" to entries.map(InboxEntry::toFlutter),
    "isRefreshing" to isRefreshing,
    "isLoadingMore" to isLoadingMore,
    "hasMore" to hasMore,
    "error" to error?.toFlutter(),
)

internal fun InboxEntry.toFlutter(): FlutterMap = mapOf(
    "id" to id.value,
    "key" to key,
    "payload" to payload.toFlutter(),
    "sentAt" to sentAt.toString(),
    "expiresAt" to expiresAt?.toString(),
    "readAt" to readAt?.toString(),
)

private fun InboxError.toFlutter(): FlutterMap = mapOf(
    "code" to code.name,
    "message" to message,
    "isRetryable" to isRetryable,
)
