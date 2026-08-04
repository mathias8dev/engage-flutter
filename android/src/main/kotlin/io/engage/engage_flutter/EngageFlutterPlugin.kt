package io.engage.engage_flutter

import android.content.Context
import android.view.View
import io.engage.sdk.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import java.util.concurrent.ConcurrentHashMap
import kotlin.coroutines.resume

public class EngageFlutterPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {
    private lateinit var applicationContext: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val observationJobs = mutableListOf<Job>()
    private val placementJobs = ConcurrentHashMap<String, Job>()
    private val centerJobs = ConcurrentHashMap<String, Job>()
    private val pagers = ConcurrentHashMap<String, PagerRegistration>()
    private val actions = ConcurrentHashMap<String, AutoCloseable>()
    private val overlayDecisions = ConcurrentHashMap<String, DisplayDecision>()
    private val pendingOverlayDecisions = ConcurrentHashMap.newKeySet<String>()
    private var eventSink: EventChannel.EventSink? = null
    private var observersStarted = false

    private val overlayDelegate = InAppOverlayDisplayDelegate { candidate ->
        val key = candidate.identity()
        overlayDecisions.remove(key) ?: run {
            if (pendingOverlayDecisions.add(key)) requestOverlayDecision(key, candidate)
            DisplayDecision.DEFER
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, METHODS_CHANNEL)
        events = EventChannel(binding.binaryMessenger, EVENTS_CHANNEL)
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
        binding.platformViewRegistry.registerViewFactory(
            IN_APP_VIEW,
            EngageInAppViewFactory(),
        )
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        launch(result) {
            val arguments = call.arguments.asMap()
            when (call.method) {
                "start" -> start(arguments)
                "installation.issueBindingCode" -> Engage.installation.issueBindingCode()
                "installation.editAttributes" -> Engage.installation.editAttributes {
                    applyAttributes(arguments)
                }
                "installation.editSubscriptions" -> Engage.installation.editSubscriptions {
                    applyInstallationSubscriptions(arguments)
                }
                "profile.editAttributes" -> Engage.profile.editAttributes { applyAttributes(arguments) }
                "profile.editTags" -> Engage.profile.editTags { applyTags(arguments) }
                "profile.editSubscriptions" -> Engage.profile.editSubscriptions {
                    applyProfileSubscriptions(arguments)
                }
                "events.track" -> Engage.events.track(arguments.string("name")) {
                    applyEvent(arguments)
                }
                "events.trackScreen" -> Engage.events.trackScreen(arguments.string("screenKey"))
                "events.clearScreen" -> Engage.events.clearScreen()
                "events.flush" -> Engage.events.flush()
                "actions.register" -> registerAction(arguments.string("name"))
                "actions.unregister" -> unregisterAction(arguments.string("name"))
                "sdkFeatures.edit" -> Engage.sdkFeatures.edit {
                    val desired = arguments["enabled"].asList()
                        .map { enumValue<SdkFeature>(it) }
                        .toSet()
                    SdkFeature.entries.forEach { feature ->
                        if (feature in desired) enable(feature) else disable(feature)
                    }
                }
                "flags.getBoolean" -> Engage.flags.getBoolean(
                    arguments.string("key"),
                    arguments.boolean("default"),
                )
                "flags.getString" -> Engage.flags.getString(
                    arguments.string("key"),
                    arguments.string("default"),
                )
                "flags.getNumber" -> Engage.flags.getNumber(
                    arguments.string("key"),
                    (arguments["default"] as Number).toDouble(),
                )
                "flags.getJson" -> Engage.flags.getJson(
                    arguments.string("key"),
                    JsonElement.serializer(),
                    arguments["default"].toJsonElement(),
                ).toFlutter()
                "preferenceCenter.observe" -> observePreferenceCenter(arguments["key"] as String?)
                "preferenceCenter.display" -> (arguments["key"] as String?)
                    ?.let(Engage.preferenceCenter::display)
                    ?: Engage.preferenceCenter.display()
                "privacy.optIn" -> Engage.privacy.optIn()
                "privacy.optOut" -> Engage.privacy.optOut()
                "privacy.optOutAndWipe" -> Engage.privacy.optOutAndWipe()
                "push.optIn" -> Engage.push.optIn()
                "push.optOut" -> Engage.push.optOut()
                "inApp.overlays.pause" -> Engage.inApp.overlays.pause()
                "inApp.overlays.resume" -> Engage.inApp.overlays.resume()
                "inApp.observePlacement" -> observePlacement(arguments.string("key"))
                "messageCenter.display" -> Engage.messageCenter.display()
                "messageCenter.pager.create" -> createPager(
                    arguments.string("pagerId"),
                    (arguments["pageSize"] as Number).toInt(),
                )
                "messageCenter.pager.refresh" -> pager(arguments).refresh()
                "messageCenter.pager.loadNextPage" -> pager(arguments).loadNextPage()
                "messageCenter.pager.close" -> closePager(arguments.string("pagerId"))
                "messageCenter.markRead" -> Engage.messageCenter.inbox.markRead(
                    InboxEntryId(arguments.string("entryId")),
                )
                "messageCenter.markUnread" -> Engage.messageCenter.inbox.markUnread(
                    InboxEntryId(arguments.string("entryId")),
                )
                "messageCenter.markAllRead" -> Engage.messageCenter.inbox.markAllRead()
                "messageCenter.delete" -> Engage.messageCenter.inbox.delete(
                    InboxEntryId(arguments.string("entryId")),
                )
                else -> return@launch NotImplemented
            }
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        eventSink = sink
        if (observersStarted) {
            emitCurrentState()
            drainPendingPushEvents()
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        eventSink = null
        actions.values.forEach { runCatching { it.close() } }
        actions.clear()
        if (::applicationContext.isInitialized && Engage.state.value is EngageLifecycle.Started) {
            EngageFlutterStartup.installBackgroundActionHandlers(applicationContext)
            EngageFlutterStartup.installBackgroundPushBuffer(applicationContext)
        }
        pagers.values.forEach(PagerRegistration::close)
        pagers.clear()
        scope.cancel()
    }

    private fun start(arguments: FlutterMap) {
        val config = arguments.toEngageConfig(applicationContext)
        val wasStarted = Engage.state.value is EngageLifecycle.Started
        Engage.start(applicationContext, config)
        EngageFlutterStartup.persist(applicationContext, arguments)
        if (!wasStarted) EngageFlutterStartup.installBackgroundActionHandlers(applicationContext)
        if (observersStarted) return
        observersStarted = true
        Engage.inApp.overlays.displayDelegate = overlayDelegate
        observationJobs += scope.launch {
            Engage.installation.id.collect { emit("installation.id", it) }
        }
        observationJobs += scope.launch {
            Engage.sdkFeatures.enabled.collect { enabled ->
                emit("sdkFeatures.enabled", enabled.map(SdkFeature::name))
            }
        }
        observationJobs += scope.launch {
            Engage.privacy.state.collect { emit("privacy.state", it.name) }
        }
        observationJobs += scope.launch {
            Engage.push.status.collect { emit("push.status", it.toFlutter()) }
        }
        observationJobs += scope.launch(start = CoroutineStart.UNDISPATCHED) {
            Engage.push.events.collect { emit("push.events", it.toFlutter()) }
        }
        observationJobs += scope.launch {
            Engage.messageCenter.inbox.unreadCount.collect { emit("messageCenter.unreadCount", it) }
        }
        EngageFlutterStartup.stopBackgroundPushBuffer()
        drainPendingPushEvents()
    }

    private fun emitCurrentState() {
        emit("installation.id", Engage.installation.id.value)
        emit("sdkFeatures.enabled", Engage.sdkFeatures.enabled.value.map(SdkFeature::name))
        emit("privacy.state", Engage.privacy.state.value.name)
        emit("push.status", Engage.push.status.value.toFlutter())
        emit("messageCenter.unreadCount", Engage.messageCenter.inbox.unreadCount.value)
        centerJobs.keys.forEach { scopeKey ->
            val center = if (scopeKey.isEmpty()) {
                Engage.preferenceCenter.center()
            } else {
                Engage.preferenceCenter.center(scopeKey)
            }
            emit("preferenceCenter.center", center.value?.toFlutter(), scopeKey)
        }
        placementJobs.keys.forEach { key ->
            emit("inApp.placement", Engage.inApp.placement(key).value?.toFlutter(), key)
        }
        pagers.forEach { (id, registration) ->
            emit("messageCenter.pager", registration.pager.state.value.toFlutter(), id)
        }
    }

    private fun observePreferenceCenter(key: String?) {
        val scopeKey = key.orEmpty()
        if (centerJobs.containsKey(scopeKey)) return
        val state = key?.let(Engage.preferenceCenter::center) ?: Engage.preferenceCenter.center()
        centerJobs[scopeKey] = scope.launch {
            state.collect { emit("preferenceCenter.center", it?.toFlutter(), scopeKey) }
        }
    }

    private fun observePlacement(key: String) {
        if (placementJobs.containsKey(key)) return
        placementJobs[key] = scope.launch {
            Engage.inApp.placement(key).collect { emit("inApp.placement", it?.toFlutter(), key) }
        }
    }

    private fun createPager(id: String, pageSize: Int) {
        if (pagers.containsKey(id)) return
        val inboxPager = Engage.messageCenter.inbox.pager(pageSize)
        val job = scope.launch {
            inboxPager.state.collect { emit("messageCenter.pager", it.toFlutter(), id) }
        }
        pagers[id] = PagerRegistration(inboxPager, job)
    }

    private fun closePager(id: String) {
        pagers.remove(id)?.close()
    }

    private fun pager(arguments: FlutterMap): InboxPager =
        requireNotNull(pagers[arguments.string("pagerId")]?.pager) { "Unknown Inbox pager" }

    private fun registerAction(name: String) {
        EngageFlutterStartup.rememberAction(applicationContext, name)
        actions.remove(name)?.close()
        actions[name] = Engage.actions.register(name) { action ->
            if (executeDartAction(action.name, action.arguments.asJson().toFlutter())) {
                ActionResult.COMPLETED
            } else {
                ActionResult.REJECTED
            }
        }
        scope.launch {
            EngageFlutterStartup.pendingActions(applicationContext, name).forEach { pending ->
                if (executeDartAction(pending.name, pending.arguments.toFlutter())) {
                    EngageFlutterStartup.acknowledgeAction(applicationContext, pending.id)
                }
            }
        }
    }

    private fun unregisterAction(name: String) {
        actions.remove(name)?.close()
        EngageFlutterStartup.forgetAction(applicationContext, name)
    }

    private suspend fun executeDartAction(name: String, arguments: Any?): Boolean = invokeDart(
        "actions.execute",
        mapOf("name" to name, "arguments" to arguments),
    ) == "COMPLETED"

    private fun drainPendingPushEvents() {
        if (eventSink == null) return
        EngageFlutterStartup.pendingPushEvents(applicationContext).forEach { pending ->
            emit("push.events", pending.event)
            EngageFlutterStartup.acknowledgePushEvent(applicationContext, pending.id)
        }
    }

    private fun requestOverlayDecision(key: String, candidate: InAppContent) {
        scope.launch {
            val response = invokeDart(
                "inApp.overlays.decide",
                mapOf("candidate" to candidate.toFlutter()),
            )
            overlayDecisions[key] = runCatching { enumValueOf<DisplayDecision>(response ?: "ALLOW") }
                .getOrDefault(DisplayDecision.ALLOW)
            pendingOverlayDecisions.remove(key)
            Engage.inApp.overlays.displayDelegate = overlayDelegate
        }
    }

    private suspend fun invokeDart(method: String, arguments: Any?): String? =
        withContext(Dispatchers.Main.immediate) {
            suspendCancellableCoroutine { continuation ->
                methods.invokeMethod(method, arguments, object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        if (continuation.isActive) continuation.resume(result as? String)
                    }
                    override fun error(code: String, message: String?, details: Any?) {
                        if (continuation.isActive) continuation.resume(null)
                    }
                    override fun notImplemented() {
                        if (continuation.isActive) continuation.resume(null)
                    }
                })
            }
        }

    private fun emit(key: String, value: Any?, scopeKey: String? = null) {
        eventSink?.success(
            buildMap {
                put("key", key)
                put("value", value)
                if (scopeKey != null) put("scope", scopeKey)
            },
        )
    }

    private fun launch(result: MethodChannel.Result, block: suspend () -> Any?) {
        scope.launch {
            try {
                when (val value = block()) {
                    NotImplemented -> result.notImplemented()
                    Unit -> result.success(null)
                    else -> result.success(value)
                }
            } catch (failure: Throwable) {
                result.error(
                    "ENGAGE_${failure.javaClass.simpleName.uppercase()}",
                    failure.message ?: failure.toString(),
                    null,
                )
            }
        }
    }

    private data class PagerRegistration(val pager: InboxPager, val job: Job) {
        fun close() {
            job.cancel()
            pager.close()
        }
    }

    private data object NotImplemented

    private companion object {
        const val METHODS_CHANNEL = "io.engage.flutter/methods"
        const val EVENTS_CHANNEL = "io.engage.flutter/events"
        const val IN_APP_VIEW = "io.engage.flutter/in_app_placement"
    }
}

private fun AttributeEditor.applyAttributes(arguments: FlutterMap) {
    arguments["set"].asMap().forEach { (key, value) ->
        when (value) {
            is String -> set(key, value)
            is Boolean -> set(key, value)
            is Int -> set(key, value)
            is Long -> set(key, value)
            is Float -> set(key, value.toDouble())
            is Double -> set(key, value)
            else -> setJson(key, value.toJsonElement())
        }
    }
    arguments["remove"].asList().forEach { remove(it as String) }
}

private fun TagEditor.applyTags(arguments: FlutterMap) {
    arguments["add"].asList().forEach { add(it as String) }
    arguments["remove"].asList().forEach { remove(it as String) }
}

private fun InstallationSubscriptionEditor.applyInstallationSubscriptions(arguments: FlutterMap) {
    arguments["changes"].asList().forEach { value ->
        val change = value.asMap()
        if (change.boolean("subscribed")) subscribe(change.string("list"))
        else unsubscribe(change.string("list"))
    }
}

private fun ProfileSubscriptionEditor.applyProfileSubscriptions(arguments: FlutterMap) {
    arguments["changes"].asList().forEach { value ->
        val change = value.asMap()
        val channels = setOf(enumValue<Channel>(change["channel"]))
        if (change.boolean("subscribed")) subscribe(change.string("list"), channels)
        else unsubscribe(change.string("list"), channels)
    }
}

private fun EventEditor.applyEvent(arguments: FlutterMap) {
    arguments["properties"].asMap().forEach { (key, value) ->
        when (value) {
            is String -> put(key, value)
            is Boolean -> put(key, value)
            is Int -> put(key, value)
            is Long -> put(key, value)
            is Float -> put(key, value.toDouble())
            is Double -> put(key, value)
            else -> putJson(key, value.toJsonElement())
        }
    }
    value = (arguments["value"] as? Number)?.toDouble()
    transactionId = arguments["transactionId"] as? String
}

private fun InAppContent.identity(): String =
    listOf(experienceId, messageId, variantId.orEmpty()).joinToString("\u0000")

private class EngageInAppViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, arguments: Any?): PlatformView {
        val key = arguments.asMap().string("key")
        return object : PlatformView {
            private val content = EngageInAppView(context).apply { placementKey = key }
            override fun getView(): View = content
            override fun dispose() = Unit
        }
    }
}
