package io.engage.engage_flutter

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.view.ContextThemeWrapper
import android.view.View
import io.engage.sdk.*
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry.NewIntentListener
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.plugin.common.StandardMessageCodec
import io.engage.sdk.messagecenter.divkit.MessageCenterViewError
import io.engage.sdk.messagecenter.divkit.MessageCenterMaterialTheme
import io.engage.sdk.messagecenter.divkit.MessageCenterViewLayout
import io.engage.sdk.messagecenter.divkit.render.EngageMessageCenterDetailView
import io.engage.sdk.messagecenter.divkit.render.EngageMessageCenterListView
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
import java.util.Locale
import kotlin.coroutines.resume

public class EngageFlutterPlugin :
    FlutterPlugin,
    ActivityAware,
    NewIntentListener,
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
    private var activityBinding: ActivityPluginBinding? = null

    private val overlayDelegate = InAppOverlayDisplayDelegate { candidate ->
        val key = candidate.identity()
        overlayDecisions.remove(key) ?: run {
            if (pendingOverlayDecisions.add(key)) requestOverlayDecision(key, candidate)
            DisplayDecision.DEFER
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        EngageLogger.info("Flutter", "Android plugin attaching to engine")
        applicationContext = binding.applicationContext
        methods = MethodChannel(binding.binaryMessenger, METHODS_CHANNEL)
        events = EventChannel(binding.binaryMessenger, EVENTS_CHANNEL)
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
        binding.platformViewRegistry.registerViewFactory(
            IN_APP_VIEW,
            EngageInAppViewFactory(),
        )
        binding.platformViewRegistry.registerViewFactory(
            MESSAGE_CENTER_LIST_VIEW,
            EngageMessageCenterListViewFactory(binding.binaryMessenger),
        )
        binding.platformViewRegistry.registerViewFactory(
            MESSAGE_CENTER_DETAIL_VIEW,
            EngageMessageCenterDetailViewFactory(binding.binaryMessenger),
        )
        EngageLogger.info("Flutter", "Android plugin attached channelsReady=true")
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val argumentKeys = (call.arguments as? Map<*, *>)?.keys?.map(Any?::toString)?.sorted().orEmpty()
        EngageLogger.verbose("Flutter", "method received name=${call.method} argumentKeys=$argumentKeys")
        launch(result, call.method) {
            val arguments = call.arguments.asMapOrEmpty()
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
                "messageCenter.display" -> (arguments["entryId"] as? String)
                    ?.let { Engage.messageCenter.display(InboxEntryId(it)) }
                    ?: Engage.messageCenter.display()
                "messageCenter.pager.create" -> createPager(
                    arguments.string("pagerId"),
                    (arguments["pageSize"] as Number).toInt(),
                    arguments.inboxSortOrder(),
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

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addOnNewIntentListener(this)
        EngageLogger.debug("Flutter", "Activity attached newIntentListener=true")
    }

    override fun onDetachedFromActivityForConfigChanges() = detachFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() = detachFromActivity()

    override fun onNewIntent(intent: Intent): Boolean {
        if (Engage.state.value !is EngageLifecycle.Started) {
            EngageLogger.debug("Flutter", "new intent deferred reason=sdk_not_started")
            return false
        }
        val handled = Engage.push.handleOpenIntent(intent)
        EngageLogger.debug("Flutter", "new intent processed engage=$handled")
        return handled
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        EngageLogger.debug("Flutter", "event listener attached observersStarted=$observersStarted")
        eventSink = sink
        if (observersStarted) {
            emitCurrentState()
            drainPendingPushEvents()
        }
    }

    override fun onCancel(arguments: Any?) {
        EngageLogger.debug("Flutter", "event listener detached")
        eventSink = null
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        EngageLogger.info("Flutter", "Android plugin detaching from engine")
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
        EngageLogger.info("Flutter", "Android plugin detached")
    }

    private fun detachFromActivity() {
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
        EngageLogger.debug("Flutter", "Activity detached newIntentListener=false")
    }

    private fun start(arguments: FlutterMap) {
        EngageLogger.debug("Flutter", "start bridge decoding configuration keys=${arguments.keys.sorted()}")
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
        EngageLogger.info(
            "Flutter",
            "start bridge ready installationId=${Engage.installation.id.value} observersStarted=$observersStarted",
        )
    }

    private fun emitCurrentState() {
        EngageLogger.debug("Flutter", "current state replay started")
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
        EngageLogger.debug("Flutter", "current state replay finished")
    }

    private fun observePreferenceCenter(key: String?) {
        val scopeKey = key.orEmpty()
        if (centerJobs.containsKey(scopeKey)) {
            EngageLogger.verbose("Flutter", "preference center observation reused key=$scopeKey")
            return
        }
        EngageLogger.debug("Flutter", "preference center observation started key=$scopeKey")
        val state = key?.let(Engage.preferenceCenter::center) ?: Engage.preferenceCenter.center()
        centerJobs[scopeKey] = scope.launch {
            state.collect { emit("preferenceCenter.center", it?.toFlutter(), scopeKey) }
        }
    }

    private fun observePlacement(key: String) {
        if (placementJobs.containsKey(key)) {
            EngageLogger.verbose("Flutter", "in-app placement observation reused key=$key")
            return
        }
        EngageLogger.debug("Flutter", "in-app placement observation started key=$key")
        placementJobs[key] = scope.launch {
            Engage.inApp.placement(key).collect { emit("inApp.placement", it?.toFlutter(), key) }
        }
    }

    private fun createPager(id: String, pageSize: Int, sortOrder: InboxSortOrder) {
        if (pagers.containsKey(id)) {
            EngageLogger.verbose("Flutter", "message center pager reused id=$id")
            return
        }
        EngageLogger.debug("Flutter", "message center pager created id=$id pageSize=$pageSize")
        val inboxPager = Engage.messageCenter.inbox.pager(pageSize, sortOrder)
        val job = scope.launch {
            inboxPager.state.collect { emit("messageCenter.pager", it.toFlutter(), id) }
        }
        pagers[id] = PagerRegistration(inboxPager, job)
    }

    private fun closePager(id: String) {
        val removed = pagers.remove(id)
        removed?.close()
        EngageLogger.debug("Flutter", "message center pager closed id=$id existed=${removed != null}")
    }

    private fun pager(arguments: FlutterMap): InboxPager =
        requireNotNull(pagers[arguments.string("pagerId")]?.pager) { "Unknown Inbox pager" }

    private fun registerAction(name: String) {
        EngageLogger.debug("Flutter", "Dart action registration started name=$name")
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
            val pendingActions = EngageFlutterStartup.pendingActions(applicationContext, name)
            EngageLogger.debug("Flutter", "pending Dart actions draining name=$name count=${pendingActions.size}")
            pendingActions.forEach { pending ->
                if (executeDartAction(pending.name, pending.arguments.toFlutter())) {
                    EngageFlutterStartup.acknowledgeAction(applicationContext, pending.id)
                }
            }
        }
        EngageLogger.info("Flutter", "Dart action registered name=$name")
    }

    private fun unregisterAction(name: String) {
        val removed = actions.remove(name)
        removed?.close()
        EngageFlutterStartup.forgetAction(applicationContext, name)
        EngageLogger.info("Flutter", "Dart action unregistered name=$name existed=${removed != null}")
    }

    private suspend fun executeDartAction(name: String, arguments: Any?): Boolean = invokeDart(
        "actions.execute",
        mapOf("name" to name, "arguments" to arguments),
    ) == "COMPLETED"

    private fun drainPendingPushEvents() {
        if (eventSink == null) {
            EngageLogger.verbose("Flutter", "pending push drain deferred reason=no_listener")
            return
        }
        val pendingEvents = EngageFlutterStartup.pendingPushEvents(applicationContext)
        EngageLogger.debug("Flutter", "pending push drain started count=${pendingEvents.size}")
        pendingEvents.forEach { pending ->
            emit("push.events", pending.event)
            EngageFlutterStartup.acknowledgePushEvent(applicationContext, pending.id)
        }
        EngageLogger.debug("Flutter", "pending push drain finished count=${pendingEvents.size}")
    }

    private fun requestOverlayDecision(key: String, candidate: InAppContent) {
        EngageLogger.debug(
            "Flutter",
            "overlay decision requested experienceId=${candidate.experienceId} messageId=${candidate.messageId}",
        )
        scope.launch {
            val response = invokeDart(
                "inApp.overlays.decide",
                mapOf("candidate" to candidate.toFlutter()),
            )
            overlayDecisions[key] = runCatching { enumValueOf<DisplayDecision>(response ?: "ALLOW") }
                .getOrDefault(DisplayDecision.ALLOW)
            pendingOverlayDecisions.remove(key)
            Engage.inApp.overlays.displayDelegate = overlayDelegate
            EngageLogger.debug(
                "Flutter",
                "overlay decision received experienceId=${candidate.experienceId} decision=${overlayDecisions[key]}",
            )
        }
    }

    private suspend fun invokeDart(method: String, arguments: Any?): String? =
        withContext(Dispatchers.Main.immediate) {
            suspendCancellableCoroutine { continuation ->
                methods.invokeMethod(method, arguments, object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        EngageLogger.verbose("Flutter", "Dart callback succeeded method=$method")
                        if (continuation.isActive) continuation.resume(result as? String)
                    }
                    override fun error(code: String, message: String?, details: Any?) {
                        EngageLogger.warn("Flutter", "Dart callback failed method=$method code=$code")
                        if (continuation.isActive) continuation.resume(null)
                    }
                    override fun notImplemented() {
                        EngageLogger.warn("Flutter", "Dart callback not implemented method=$method")
                        if (continuation.isActive) continuation.resume(null)
                    }
                })
            }
        }

    private fun emit(key: String, value: Any?, scopeKey: String? = null) {
        EngageLogger.verbose(
            "Flutter",
            "event emitted key=$key scope=${scopeKey.orEmpty()} valueType=${value?.javaClass?.simpleName ?: "null"}",
        )
        eventSink?.success(
            buildMap {
                put("key", key)
                put("value", value)
                if (scopeKey != null) put("scope", scopeKey)
            },
        )
    }

    private fun launch(result: MethodChannel.Result, method: String, block: suspend () -> Any?) {
        scope.launch {
            val startedAt = System.nanoTime()
            try {
                when (val value = block()) {
                    NotImplemented -> {
                        EngageLogger.warn("Flutter", "method not implemented name=$method")
                        result.notImplemented()
                    }
                    Unit -> result.success(null)
                    else -> result.success(value)
                }
                val durationMillis = (System.nanoTime() - startedAt) / 1_000_000
                EngageLogger.verbose("Flutter", "method completed name=$method durationMs=$durationMillis")
            } catch (failure: Throwable) {
                EngageLogger.error("Flutter", "method failed name=$method", failure)
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
        const val MESSAGE_CENTER_LIST_VIEW = "io.engage.flutter/message_center_list"
        const val MESSAGE_CENTER_DETAIL_VIEW = "io.engage.flutter/message_center_detail"
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
        EngageLogger.debug("Flutter", "in-app platform view created viewId=$viewId placementKey=$key")
        return object : PlatformView {
            private val content = EngageInAppView(context).apply { placementKey = key }
            override fun getView(): View = content
            override fun dispose() {
                EngageLogger.debug("Flutter", "in-app platform view disposed viewId=$viewId placementKey=$key")
            }
        }
    }
}

private class EngageMessageCenterListViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, arguments: Any?): PlatformView {
        val parameters = arguments.asMap()
        val environment = context.messageCenterEnvironment(parameters)
        val channel = MethodChannel(messenger, "io.engage.flutter/message_center_list/$viewId")
        val content = EngageMessageCenterListView(
            environment,
            sortOrder = parameters.inboxSortOrder(),
            onEntryTap = { entry -> channel.invokeMethod("entryTap", entry.toFlutter()) },
            onError = { error -> channel.invokeMethod("error", error.toFlutter()) },
            startImmediately = false,
            materialTheme = environment.messageCenterMaterialTheme(parameters),
            layout = parameters.messageCenterLayout(),
        )
        channel.setMethodCallHandler { call, result ->
            if (call.method == "ready") {
                content.start()
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        EngageLogger.debug("Flutter", "Message Center list platform view created viewId=$viewId")
        return object : PlatformView {
            override fun getView(): View = content
            override fun dispose() {
                channel.setMethodCallHandler(null)
                content.close()
                EngageLogger.debug("Flutter", "Message Center list platform view disposed viewId=$viewId")
            }
        }
    }
}

private class EngageMessageCenterDetailViewFactory(
    private val messenger: BinaryMessenger,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, arguments: Any?): PlatformView {
        val parameters = arguments.asMap()
        val entryId = InboxEntryId(parameters.string("entryId"))
        val environment = context.messageCenterEnvironment(parameters)
        val channel = MethodChannel(messenger, "io.engage.flutter/message_center_detail/$viewId")
        val content = EngageMessageCenterDetailView(
            environment,
            onUnavailable = { channel.invokeMethod("unavailable", null) },
            onError = { error -> channel.invokeMethod("error", error.toFlutter()) },
            materialTheme = environment.messageCenterMaterialTheme(parameters),
            layout = parameters.messageCenterLayout(),
        )
        channel.setMethodCallHandler { call, result ->
            if (call.method == "ready") {
                content.display(entryId)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
        EngageLogger.debug(
            "Flutter",
            "Message Center detail platform view created viewId=$viewId entryId=$entryId",
        )
        return object : PlatformView {
            override fun getView(): View = content
            override fun dispose() {
                channel.setMethodCallHandler(null)
                content.close()
                EngageLogger.debug("Flutter", "Message Center detail platform view disposed viewId=$viewId")
            }
        }
    }
}

private fun MessageCenterViewError.toFlutter(): FlutterMap = mapOf(
    "code" to code.name,
    "message" to message,
    "isRetryable" to isRetryable,
)

private fun Context.messageCenterEnvironment(arguments: FlutterMap): Context {
    val configuration = Configuration(resources.configuration)
    configuration.uiMode = (configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
        if (arguments["appearance"] == "DARK") Configuration.UI_MODE_NIGHT_YES
        else Configuration.UI_MODE_NIGHT_NO
    (arguments["locale"] as? String)?.takeIf(String::isNotBlank)?.let { languageTag ->
        configuration.setLocale(Locale.forLanguageTag(languageTag))
    }
    return ContextThemeWrapper(this, theme).apply {
        applyOverrideConfiguration(configuration)
    }
}

private fun Context.messageCenterMaterialTheme(arguments: FlutterMap): MessageCenterMaterialTheme {
    val defaults = MessageCenterMaterialTheme.defaults(this)
    val values = arguments["material3"]?.asMap() ?: return defaults
    fun color(key: String, fallback: Int): Int = (values[key] as? Number)?.toLong()?.toInt() ?: fallback
    return MessageCenterMaterialTheme(
        primary = color("primary", defaults.primary),
        onPrimary = color("onPrimary", defaults.onPrimary),
        primaryContainer = color("primaryContainer", defaults.primaryContainer),
        surface = color("surface", defaults.surface),
        surfaceContainerLow = color("surfaceContainerLow", defaults.surfaceContainerLow),
        surfaceContainer = color("surfaceContainer", defaults.surfaceContainer),
        onSurface = color("onSurface", defaults.onSurface),
        onSurfaceVariant = color("onSurfaceVariant", defaults.onSurfaceVariant),
        outlineVariant = color("outlineVariant", defaults.outlineVariant),
        error = color("error", defaults.error),
        onError = color("onError", defaults.onError),
    )
}

private fun FlutterMap.messageCenterLayout(): MessageCenterViewLayout {
    val defaults = MessageCenterViewLayout()
    val values = this["layout"]?.asMap() ?: return defaults
    fun dimension(key: String, fallback: Float): Float = (values[key] as? Number)?.toFloat() ?: fallback
    return MessageCenterViewLayout(
        horizontalPaddingDp = dimension("horizontalPadding", defaults.horizontalPaddingDp),
        itemSpacingDp = dimension("itemSpacing", defaults.itemSpacingDp),
        itemCornerRadiusDp = dimension("itemCornerRadius", defaults.itemCornerRadiusDp),
    )
}

private fun FlutterMap.inboxSortOrder(): InboxSortOrder = when (this["sortOrder"] as? String) {
    "OLDEST_FIRST" -> InboxSortOrder.OLDEST_FIRST
    else -> InboxSortOrder.NEWEST_FIRST
}
