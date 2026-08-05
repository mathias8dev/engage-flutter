package io.engage.engage_flutter

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.net.Uri
import io.engage.sdk.Engage
import io.engage.sdk.EngageConfig
import io.engage.sdk.EngageLogger
import io.engage.sdk.ActionResult
import io.engage.sdk.push
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

internal object EngageFlutterStartup {
    private const val PREFERENCES = "engage_flutter_startup"
    private const val CONFIGURATION = "configuration"
    private const val INSTALLED_AT = "installed_at"
    private const val REGISTERED_ACTIONS = "registered_actions"
    private const val PENDING_ACTIONS = "pending_actions"
    private const val PENDING_PUSH_EVENTS = "pending_push_events"
    private const val MAX_PENDING_ACTIONS = 64
    private const val MAX_PENDING_PUSH_EVENTS = 32
    private val backgroundActionRegistrations = mutableMapOf<String, AutoCloseable>()
    private val backgroundScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var pushEventJob: Job? = null

    fun persist(context: Context, arguments: FlutterMap) {
        EngageLogger.debug("FlutterStartup", "startup configuration persistence started keys=${arguments.keys.sorted()}")
        val serialized = JSONObject(arguments.mapValues { (_, value) -> value.toJsonValue() }).toString()
        check(
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit()
                .putString(CONFIGURATION, serialized)
                .putLong(INSTALLED_AT, context.installedAt())
                .commit(),
        ) { "Could not persist the Engage Flutter startup configuration" }
        EngageLogger.debug("FlutterStartup", "startup configuration persisted")
    }

    fun restore(context: Context): EngageConfig? {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val serialized = preferences.getString(CONFIGURATION, null) ?: run {
            EngageLogger.debug("FlutterStartup", "startup configuration absent")
            return null
        }
        if (preferences.getLong(INSTALLED_AT, Long.MIN_VALUE) != context.installedAt()) {
            preferences.edit().remove(CONFIGURATION).remove(INSTALLED_AT).commit()
            EngageLogger.info("FlutterStartup", "startup configuration cleared reason=application_updated")
            return null
        }
        return runCatching {
            JSONObject(serialized).toFlutterMap().toEngageConfig(context)
                .also { EngageLogger.debug("FlutterStartup", "startup configuration restored") }
        }.getOrElse {
            preferences.edit().remove(CONFIGURATION).remove(INSTALLED_AT).commit()
            EngageLogger.warn("FlutterStartup", "startup configuration cleared reason=decode_failure", it)
            null
        }
    }

    @Synchronized
    fun rememberAction(context: Context, name: String) {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val names = preferences.getStringSet(REGISTERED_ACTIONS, emptySet()).orEmpty() + name
        check(preferences.edit().putStringSet(REGISTERED_ACTIONS, names).commit()) {
            "Could not persist the Engage Flutter action registry"
        }
        EngageLogger.debug("FlutterStartup", "background action remembered name=$name count=${names.size}")
    }

    @Synchronized
    fun forgetAction(context: Context, name: String) {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val names = preferences.getStringSet(REGISTERED_ACTIONS, emptySet()).orEmpty() - name
        val pending = readPending(preferences.getString(PENDING_ACTIONS, null))
            .filterNot { action -> action.name == name }
        check(
            preferences.edit()
                .putStringSet(REGISTERED_ACTIONS, names)
                .putString(PENDING_ACTIONS, pending.toActionJson().toString())
                .commit(),
        ) { "Could not remove the Engage Flutter action registration" }
        backgroundActionRegistrations.remove(name)?.close()
        EngageLogger.debug("FlutterStartup", "background action forgotten name=$name pendingRemoved=${pending.size}")
    }

    @Synchronized
    fun installBackgroundActionHandlers(context: Context) {
        backgroundActionRegistrations.values.forEach { registration -> runCatching { registration.close() } }
        backgroundActionRegistrations.clear()
        val names = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getStringSet(REGISTERED_ACTIONS, emptySet()).orEmpty()
        EngageLogger.debug("FlutterStartup", "background action handlers installing count=${names.size}")
        names.forEach { name ->
            backgroundActionRegistrations[name] = Engage.actions.register(name) { action ->
                if (enqueuePendingAction(context, name, action.arguments.asJson())) {
                    ActionResult.COMPLETED
                } else {
                    ActionResult.REJECTED
                }
            }
        }
        EngageLogger.debug("FlutterStartup", "background action handlers installed count=${names.size}")
    }

    @Synchronized
    fun installBackgroundPushBuffer(context: Context) {
        EngageLogger.debug("FlutterStartup", "background push buffer starting")
        pushEventJob?.cancel()
        pushEventJob = backgroundScope.launch(start = CoroutineStart.UNDISPATCHED) {
            Engage.push.events.collect { event -> enqueuePushEvent(context, event.toFlutter()) }
        }
    }

    @Synchronized
    fun stopBackgroundPushBuffer() {
        pushEventJob?.cancel()
        pushEventJob = null
        EngageLogger.debug("FlutterStartup", "background push buffer stopped")
    }

    @Synchronized
    fun pendingActions(context: Context, name: String): List<PendingFlutterAction> =
        readPending(
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getString(PENDING_ACTIONS, null),
        ).filter { action -> action.name == name }

    @Synchronized
    fun acknowledgeAction(context: Context, id: String) {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val remaining = readPending(preferences.getString(PENDING_ACTIONS, null))
            .filterNot { action -> action.id == id }
        check(preferences.edit().putString(PENDING_ACTIONS, remaining.toActionJson().toString()).commit()) {
            "Could not acknowledge the Engage Flutter action"
        }
        EngageLogger.verbose("FlutterStartup", "pending action acknowledged id=$id remaining=${remaining.size}")
    }

    @Synchronized
    internal fun enqueuePendingAction(context: Context, name: String, arguments: JsonObject): Boolean {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val pending = readPending(preferences.getString(PENDING_ACTIONS, null)).toMutableList()
        pending += PendingFlutterAction(UUID.randomUUID().toString(), name, arguments)
        while (pending.size > MAX_PENDING_ACTIONS) pending.removeAt(0)
        val persisted = preferences.edit().putString(PENDING_ACTIONS, pending.toActionJson().toString()).commit()
        EngageLogger.debug(
            "FlutterStartup",
            "pending action enqueued name=$name argumentKeys=${arguments.keys.sorted()} count=${pending.size} persisted=$persisted",
        )
        return persisted
    }

    @Synchronized
    fun pendingPushEvents(context: Context): List<PendingFlutterPushEvent> = readPendingPushEvents(
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getString(PENDING_PUSH_EVENTS, null),
    )

    @Synchronized
    fun acknowledgePushEvent(context: Context, id: String) {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val remaining = readPendingPushEvents(preferences.getString(PENDING_PUSH_EVENTS, null))
            .filterNot { event -> event.id == id }
        check(preferences.edit().putString(PENDING_PUSH_EVENTS, remaining.toPushEventJson().toString()).commit()) {
            "Could not acknowledge the Engage Flutter push event"
        }
        EngageLogger.verbose("FlutterStartup", "pending push event acknowledged id=$id remaining=${remaining.size}")
    }

    @Synchronized
    internal fun enqueuePushEvent(context: Context, event: FlutterMap): Boolean {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val pending = readPendingPushEvents(preferences.getString(PENDING_PUSH_EVENTS, null)).toMutableList()
        pending += PendingFlutterPushEvent(UUID.randomUUID().toString(), event)
        while (pending.size > MAX_PENDING_PUSH_EVENTS) pending.removeAt(0)
        val persisted = preferences.edit().putString(PENDING_PUSH_EVENTS, pending.toPushEventJson().toString()).commit()
        EngageLogger.debug(
            "FlutterStartup",
            "pending push event enqueued eventKeys=${event.keys.sorted()} count=${pending.size} persisted=$persisted",
        )
        return persisted
    }

    private fun Context.installedAt(): Long = packageManager.getPackageInfo(packageName, 0).lastUpdateTime
}

public class EngageFlutterInitProvider : ContentProvider() {
    override fun onCreate(): Boolean {
        val application = context?.applicationContext ?: return false
        EngageLogger.debug("FlutterStartup", "Android startup provider created")
        EngageFlutterStartup.restore(application)?.let { config ->
            EngageLogger.info("FlutterStartup", "automatic SDK startup beginning")
            Engage.start(application, config)
            EngageFlutterStartup.installBackgroundActionHandlers(application)
            EngageFlutterStartup.installBackgroundPushBuffer(application)
            EngageLogger.info(
                "FlutterStartup",
                "automatic SDK startup complete installationId=${Engage.installation.id.value}",
            )
        }
        return true
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? = null

    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0
}

internal data class PendingFlutterAction(
    val id: String,
    val name: String,
    val arguments: JsonObject,
)

internal data class PendingFlutterPushEvent(
    val id: String,
    val event: FlutterMap,
)

private fun readPending(serialized: String?): List<PendingFlutterAction> {
    if (serialized.isNullOrBlank()) return emptyList()
    return runCatching {
        val array = JSONArray(serialized)
        (0 until array.length()).map { index ->
            val value = array.getJSONObject(index)
            PendingFlutterAction(
                id = value.getString("id"),
                name = value.getString("name"),
                arguments = Json.parseToJsonElement(value.getJSONObject("arguments").toString()) as JsonObject,
            )
        }
    }.getOrDefault(emptyList())
}

private fun List<PendingFlutterAction>.toActionJson(): JSONArray = JSONArray().also { array ->
    forEach { action ->
        array.put(
            JSONObject()
                .put("id", action.id)
                .put("name", action.name)
                .put("arguments", JSONObject(action.arguments.toString())),
        )
    }
}

private fun readPendingPushEvents(serialized: String?): List<PendingFlutterPushEvent> {
    if (serialized.isNullOrBlank()) return emptyList()
    return runCatching {
        val array = JSONArray(serialized)
        (0 until array.length()).map { index ->
            val value = array.getJSONObject(index)
            PendingFlutterPushEvent(
                id = value.getString("id"),
                event = value.getJSONObject("event").toFlutterMap(),
            )
        }
    }.getOrDefault(emptyList())
}

private fun List<PendingFlutterPushEvent>.toPushEventJson(): JSONArray = JSONArray().also { array ->
    forEach { pending ->
        array.put(
            JSONObject()
                .put("id", pending.id)
                .put("event", JSONObject(pending.event.mapValues { (_, value) -> value.toJsonValue() })),
        )
    }
}

private fun Any?.toJsonValue(): Any = when (this) {
    null -> JSONObject.NULL
    is Map<*, *> -> JSONObject(entries.associate { (key, value) -> key.toString() to value.toJsonValue() })
    is Iterable<*> -> JSONArray(map { value -> value.toJsonValue() })
    is Array<*> -> JSONArray(map { value -> value.toJsonValue() })
    is String, is Boolean, is Number -> this
    else -> error("Unsupported startup configuration value: ${javaClass.name}")
}

private fun JSONObject.toFlutterMap(): FlutterMap = keys().asSequence().associateWith { key ->
    get(key).toFlutterValue()
}

private fun Any.toFlutterValue(): Any? = when (this) {
    JSONObject.NULL -> null
    is JSONObject -> toFlutterMap()
    is JSONArray -> (0 until length()).map { index -> get(index).toFlutterValue() }
    else -> this
}
