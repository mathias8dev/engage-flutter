import Flutter
import UIKit
import SwiftUI
import EngageSDK

public final class EngageFlutterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let methods: FlutterMethodChannel
  private var eventSink: FlutterEventSink?
  private var pendingEvents: [FlutterMap] = []
  private var started = false
  private var observationTasks: [Task<Void, Never>] = []
  private var placementTasks: [String: Task<Void, Never>] = [:]
  private var centerTasks: [String: Task<Void, Never>] = [:]
  private var pagers: [String: PagerRegistration] = [:]
  private var actions: [String: ActionRegistration] = [:]
  private var overlayDecisions: [String: DisplayDecision] = [:]
  private var pendingOverlayDecisions: Set<String> = []
  private let lock = NSLock()

  private lazy var overlayDelegate: @Sendable (InAppContent) -> DisplayDecision = { [weak self] candidate in
    guard let self else { return .allow }
    let key = self.contentIdentity(candidate)
    self.lock.lock()
    if let decision = self.overlayDecisions.removeValue(forKey: key) {
      self.lock.unlock()
      return decision
    }
    let inserted = self.pendingOverlayDecisions.insert(key).inserted
    self.lock.unlock()
    if inserted { self.requestOverlayDecision(key: key, candidate: candidate) }
    return .deferDisplay
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    EngageLogger.info("Flutter", "iOS plugin registering")
    PushModule.prepareForLaunch()
    let methods = FlutterMethodChannel(
      name: "io.engage.flutter/methods",
      binaryMessenger: registrar.messenger()
    )
    let events = FlutterEventChannel(
      name: "io.engage.flutter/events",
      binaryMessenger: registrar.messenger()
    )
    let instance = EngageFlutterPlugin(methods: methods)
    registrar.addMethodCallDelegate(instance, channel: methods)
    registrar.addApplicationDelegate(instance)
    events.setStreamHandler(instance)
    registrar.register(
      EngageInAppViewFactory(),
      withId: "io.engage.flutter/in_app_placement"
    )
    registrar.register(
      EngageMessageCenterListViewFactory(messenger: registrar.messenger()),
      withId: "io.engage.flutter/message_center_list"
    )
    registrar.register(
      EngageMessageCenterDetailViewFactory(messenger: registrar.messenger()),
      withId: "io.engage.flutter/message_center_detail"
    )
    EngageLogger.info("Flutter", "iOS plugin registered channelsReady=true")
  }

  init(methods: FlutterMethodChannel) {
    self.methods = methods
    super.init()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    Task { @MainActor in
      let startedAt = DispatchTime.now().uptimeNanoseconds
      let argumentKeys = ((call.arguments as? FlutterMap)?.keys.sorted()) ?? []
      EngageLogger.verbose(
        "Flutter",
        "method received name=\(call.method) argumentKeys=\(argumentKeys)"
      )
      defer {
        let durationMilliseconds = (DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000
        EngageLogger.verbose(
          "Flutter",
          "method completed name=\(call.method) durationMs=\(durationMilliseconds)"
        )
      }
      do {
        let arguments = call.arguments as? FlutterMap ?? [:]
        switch call.method {
        case "start":
          EngageLogger.debug("Flutter", "start bridge decoding configuration keys=\(arguments.keys.sorted())")
          Engage.start(config: try engageConfig(arguments))
          startObserversIfNeeded()
          EngageLogger.info(
            "Flutter",
            "start bridge ready installationId=\(Engage.installation.id.value) observersStarted=\(started)"
          )
          result(nil)
        case "installation.issueBindingCode":
          result(try await Engage.installation.issueBindingCode())
        case "installation.editAttributes":
          var editor = AttributeEditor()
          try applyAttributes(arguments, editor: &editor)
          let decodedEditor = editor
          try await Engage.installation.editAttributes { $0 = decodedEditor }
          result(nil)
        case "installation.editSubscriptions":
          var editor = InstallationSubscriptionEditor()
          try applyInstallationSubscriptions(arguments, editor: &editor)
          let decodedEditor = editor
          try await Engage.installation.editSubscriptions { $0 = decodedEditor }
          result(nil)
        case "profile.editAttributes":
          var editor = AttributeEditor()
          try applyAttributes(arguments, editor: &editor)
          let decodedEditor = editor
          try await Engage.profile.editAttributes { $0 = decodedEditor }
          result(nil)
        case "profile.editTags":
          var editor = TagEditor()
          try applyTags(arguments, editor: &editor)
          let decodedEditor = editor
          try await Engage.profile.editTags { $0 = decodedEditor }
          result(nil)
        case "profile.editSubscriptions":
          var editor = ProfileSubscriptionEditor()
          try applyProfileSubscriptions(arguments, editor: &editor)
          let decodedEditor = editor
          try await Engage.profile.editSubscriptions { $0 = decodedEditor }
          result(nil)
        case "events.track":
          var editor = EventEditor()
          try applyEvent(arguments, editor: &editor)
          let decodedEditor = editor
          try await Engage.events.track(try arguments.string("name")) { $0 = decodedEditor }
          result(nil)
        case "events.trackScreen":
          try await Engage.events.trackScreen(try arguments.string("screenKey"))
          result(nil)
        case "events.clearScreen":
          try await Engage.events.clearScreen()
          result(nil)
        case "events.flush":
          try await Engage.events.flush()
          result(nil)
        case "actions.register":
          registerAction(try arguments.string("name"))
          result(nil)
        case "actions.unregister":
          unregisterAction(try arguments.string("name"))
          result(nil)
        case "sdkFeatures.edit":
          let enabled = Set(arguments.list("enabled").compactMap { value in
            (value as? String).flatMap(SdkFeature.init(rawValue:))
          })
          try await Engage.sdkFeatures.edit { editor in
            for feature in SdkFeature.allCases {
              if enabled.contains(feature) { editor.enable(feature) }
              else { editor.disable(feature) }
            }
          }
          result(nil)
        case "flags.getBoolean":
          result(Engage.flags.getBoolean(
            try arguments.string("key"),
            default: try arguments.bool("default")
          ))
        case "flags.getString":
          result(Engage.flags.getString(
            try arguments.string("key"),
            default: try arguments.string("default")
          ))
        case "flags.getNumber":
          result(Engage.flags.getNumber(
            try arguments.string("key"),
            default: (arguments["default"] as? NSNumber)?.doubleValue ?? 0
          ))
        case "flags.getJson":
          let fallback = try jsonValue(arguments["default"])
          let value = Engage.flags.getJSON(
            try arguments.string("key"),
            as: JSONValue.self,
            default: fallback
          )
          result(flutterValue(value))
        case "preferenceCenter.observe":
          observePreferenceCenter(arguments["key"] as? String)
          result(nil)
        case "preferenceCenter.refresh":
          try await Engage.preferenceCenter.refresh()
          result(nil)
        case "preferenceCenter.display":
          Engage.preferenceCenter.display(
            arguments["key"] as? String,
            materialTheme: preferenceCenterMaterialTheme(arguments)
          )
          result(nil)
        case "privacy.optIn":
          try await Engage.privacy.optIn()
          result(nil)
        case "privacy.optOut":
          try await Engage.privacy.optOut()
          result(nil)
        case "privacy.optOutAndWipe":
          try await Engage.privacy.optOutAndWipe()
          result(nil)
        case "push.optIn":
          try await Engage.push.optIn()
          result(nil)
        case "push.optOut":
          try await Engage.push.optOut()
          result(nil)
        case "inApp.overlays.pause":
          Engage.inApp.overlays.pause()
          result(nil)
        case "inApp.overlays.resume":
          Engage.inApp.overlays.resume()
          result(nil)
        case "inApp.observePlacement":
          observePlacement(try arguments.string("key"))
          result(nil)
        case "inApp.trackOutcome":
          let properties = try jsonValue(arguments["properties"])
          guard let object = properties.objectValue else {
            throw EngageFlutterCodecError.invalidArgument("Outcome properties must be a map")
          }
          result(await Engage.inApp.recordOutcome(
            messageId: try arguments.string("messageId"),
            key: try arguments.string("key"),
            properties: object
          ))
        case "messageCenter.display":
          Engage.messageCenter.display(
            entryId: (arguments["entryId"] as? String).map(InboxEntryId.init)
          )
          result(nil)
        case "messageCenter.pager.create":
          createPager(
            id: try arguments.string("pagerId"),
            pageSize: (arguments["pageSize"] as? NSNumber)?.intValue ?? 20,
            sortOrder: inboxSortOrder(arguments)
          )
          result(nil)
        case "messageCenter.pager.refresh":
          try await pager(arguments).pager.refresh()
          result(nil)
        case "messageCenter.pager.loadNextPage":
          try await pager(arguments).pager.loadNextPage()
          result(nil)
        case "messageCenter.pager.close":
          closePager(try arguments.string("pagerId"))
          result(nil)
        case "messageCenter.markRead":
          await Engage.messageCenter.inbox.markRead(InboxEntryId(try arguments.string("entryId")))
          result(nil)
        case "messageCenter.markUnread":
          await Engage.messageCenter.inbox.markUnread(InboxEntryId(try arguments.string("entryId")))
          result(nil)
        case "messageCenter.markAllRead":
          await Engage.messageCenter.inbox.markAllRead()
          result(nil)
        case "messageCenter.delete":
          await Engage.messageCenter.inbox.delete(InboxEntryId(try arguments.string("entryId")))
          result(nil)
        default:
          EngageLogger.warning("Flutter", "method not implemented name=\(call.method)")
          result(FlutterMethodNotImplemented)
        }
      } catch {
        EngageLogger.error("Flutter", "method failed name=\(call.method)", error: error)
        result(FlutterError(
          code: "ENGAGE_\(String(describing: type(of: error)).uppercased())",
          message: String(describing: error),
          details: nil
        ))
      }
    }
  }

  public func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    EngageLogger.debug("Flutter", "event listener attached observersStarted=\(started)")
    lock.lock()
    eventSink = events
    let pending = pendingEvents
    pendingEvents.removeAll()
    pending.forEach { envelope in DispatchQueue.main.async { events(envelope) } }
    lock.unlock()
    if started { emitCurrentState() }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    EngageLogger.debug("Flutter", "event listener detached")
    lock.lock()
    eventSink = nil
    lock.unlock()
    return nil
  }

  public func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    guard started else {
      EngageLogger.debug("Flutter", "APNs token callback ignored reason=not_started")
      return
    }
    EngageLogger.debug("Flutter", "APNs token callback forwarded byteCount=\(deviceToken.count)")
    Engage.push.didRegisterForRemoteNotifications(deviceToken: deviceToken)
  }

  public func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    guard started else {
      EngageLogger.debug("Flutter", "APNs registration failure ignored reason=not_started")
      return
    }
    EngageLogger.warning("Flutter", "APNs registration failure forwarded", error: error)
    Engage.push.didFailToRegisterForRemoteNotifications(error: error)
  }

  private func startObserversIfNeeded() {
    guard !started else {
      EngageLogger.verbose("Flutter", "state observers already started")
      return
    }
    EngageLogger.debug("Flutter", "state observers starting")
    started = true
    Engage.inApp.overlays.displayDelegate = overlayDelegate
    observationTasks = [
      Task { [weak self] in
        for await value in Engage.installation.id.updates {
          self?.emit(key: "installation.id", value: value)
        }
      },
      Task { [weak self] in
        for await value in Engage.sdkFeatures.enabled.updates {
          self?.emit(key: "sdkFeatures.enabled", value: value.map(\.rawValue))
        }
      },
      Task { [weak self] in
        for await value in Engage.privacy.state.updates {
          self?.emit(key: "privacy.state", value: value.rawValue)
        }
      },
      Task { [weak self] in
        for await value in Engage.push.status.updates {
          self?.emit(key: "push.status", value: flutterPushStatus(value))
        }
      },
      Task { [weak self] in
        for await value in Engage.push.events {
          self?.emit(key: "push.events", value: flutterPushEvent(value))
        }
      },
      Task { [weak self] in
        for await value in Engage.messageCenter.inbox.unreadCount.updates {
          self?.emit(key: "messageCenter.unreadCount", value: value)
        }
      },
    ]
    EngageLogger.debug("Flutter", "state observers started count=\(observationTasks.count)")
  }

  private func emitCurrentState() {
    EngageLogger.debug("Flutter", "current state replay started")
    emit(key: "installation.id", value: Engage.installation.id.value)
    emit(key: "sdkFeatures.enabled", value: Engage.sdkFeatures.enabled.value.map(\.rawValue))
    emit(key: "privacy.state", value: Engage.privacy.state.value.rawValue)
    emit(key: "push.status", value: flutterPushStatus(Engage.push.status.value))
    emit(key: "messageCenter.unreadCount", value: Engage.messageCenter.inbox.unreadCount.value)
    for (scope, _) in centerTasks {
      let state = scope.isEmpty
        ? Engage.preferenceCenter.center()
        : Engage.preferenceCenter.center(scope)
      emit(
        key: "preferenceCenter.center",
        value: state.value.map(flutterPreferenceCenter),
        scope: scope
      )
    }
    for (key, _) in placementTasks {
      emit(
        key: "inApp.placement",
        value: Engage.inApp.placement(key).value.map(flutterInAppContent),
        scope: key
      )
    }
    for (id, registration) in pagers {
      emit(key: "messageCenter.pager", value: flutterPagerState(registration.pager.state.value), scope: id)
    }
    EngageLogger.debug("Flutter", "current state replay finished")
  }

  private func observePreferenceCenter(_ key: String?) {
    let scope = key ?? ""
    guard centerTasks[scope] == nil else {
      EngageLogger.verbose("Flutter", "preference center observation reused key=\(scope)")
      return
    }
    EngageLogger.debug("Flutter", "preference center observation started key=\(scope)")
    let state = Engage.preferenceCenter.center(key)
    centerTasks[scope] = Task { [weak self] in
      for await value in state.updates {
        self?.emit(
          key: "preferenceCenter.center",
          value: value.map(flutterPreferenceCenter),
          scope: scope
        )
      }
    }
  }

  private func observePlacement(_ key: String) {
    guard placementTasks[key] == nil else {
      EngageLogger.verbose("Flutter", "in-app placement observation reused key=\(key)")
      return
    }
    EngageLogger.debug("Flutter", "in-app placement observation started key=\(key)")
    let state = Engage.inApp.placement(key)
    placementTasks[key] = Task { [weak self] in
      for await value in state.updates {
        self?.emit(
          key: "inApp.placement",
          value: value.map(flutterInAppContent),
          scope: key
        )
      }
    }
  }

  private func createPager(id: String, pageSize: Int, sortOrder: InboxSortOrder) {
    guard pagers[id] == nil else {
      EngageLogger.verbose("Flutter", "message center pager reused id=\(id)")
      return
    }
    EngageLogger.debug("Flutter", "message center pager created id=\(id) pageSize=\(pageSize)")
    let inboxPager = Engage.messageCenter.inbox.pager(pageSize: pageSize, sortOrder: sortOrder)
    let task = Task { [weak self] in
      for await value in inboxPager.state.updates {
        self?.emit(key: "messageCenter.pager", value: flutterPagerState(value), scope: id)
      }
    }
    pagers[id] = PagerRegistration(pager: inboxPager, task: task)
  }

  private func closePager(_ id: String) {
    let registration = pagers.removeValue(forKey: id)
    registration?.close()
    EngageLogger.debug("Flutter", "message center pager closed id=\(id) existed=\(registration != nil)")
  }

  private func pager(_ arguments: FlutterMap) throws -> PagerRegistration {
    let id = try arguments.string("pagerId")
    guard let pager = pagers[id] else {
      throw EngageFlutterCodecError.invalidArgument("Unknown Inbox pager: \(id)")
    }
    return pager
  }

  private func registerAction(_ name: String) {
    EngageLogger.debug("Flutter", "Dart action registration started name=\(name)")
    unregisterAction(name)
    actions[name] = Engage.actions.register(name) { [weak self] action in
      guard let self else { return .rejected }
      let value = await self.invokeDart(
        method: "actions.execute",
        arguments: [
          "name": action.name,
          "arguments": action.arguments.payload.mapValues(flutterValue),
        ]
      ) as? String
      return value == "COMPLETED" ? .completed : .rejected
    }
    EngageLogger.info("Flutter", "Dart action registered name=\(name)")
  }

  private func unregisterAction(_ name: String) {
    let registration = actions.removeValue(forKey: name)
    registration?.cancel()
    EngageLogger.info("Flutter", "Dart action unregistered name=\(name) existed=\(registration != nil)")
  }

  private func requestOverlayDecision(key: String, candidate: InAppContent) {
    EngageLogger.debug(
      "Flutter",
      "overlay decision requested experienceId=\(candidate.experienceId) messageId=\(candidate.messageId)"
    )
    Task { [weak self] in
      guard let self else { return }
      let value = await self.invokeDart(
        method: "inApp.overlays.decide",
        arguments: ["candidate": flutterInAppContent(candidate)]
      ) as? String
      let decision: DisplayDecision
      switch value {
      case "DISCARD": decision = .discard
      case "DEFER": decision = .deferDisplay
      default: decision = .allow
      }
      self.lock.lock()
      self.overlayDecisions[key] = decision
      self.pendingOverlayDecisions.remove(key)
      self.lock.unlock()
      Engage.inApp.overlays.displayDelegate = self.overlayDelegate
      EngageLogger.debug(
        "Flutter",
        "overlay decision received experienceId=\(candidate.experienceId) decision=\(decision)"
      )
    }
  }

  private func invokeDart(method: String, arguments: Any?) async -> Any? {
    EngageLogger.verbose("Flutter", "Dart callback invoked method=\(method)")
    return await withCheckedContinuation { continuation in
      DispatchQueue.main.async { [methods] in
        methods.invokeMethod(method, arguments: arguments) { value in
          EngageLogger.verbose(
            "Flutter",
            "Dart callback completed method=\(method) resultType=\(String(describing: type(of: value)))"
          )
          continuation.resume(returning: value)
        }
      }
    }
  }

  private func emit(key: String, value: Any?, scope: String? = nil) {
    var envelope: FlutterMap = ["key": key, "value": value ?? NSNull()]
    if let scope { envelope["scope"] = scope }
    lock.lock()
    guard let sink = eventSink else {
      pendingEvents.append(envelope)
      if pendingEvents.count > 64 { pendingEvents.removeFirst(pendingEvents.count - 64) }
      let count = pendingEvents.count
      lock.unlock()
      EngageLogger.verbose("Flutter", "event buffered key=\(key) pending=\(count)")
      return
    }
    lock.unlock()
    EngageLogger.verbose(
      "Flutter",
      "event emitted key=\(key) scope=\(scope ?? "") valueType=\(String(describing: type(of: value)))"
    )
    DispatchQueue.main.async { sink(envelope) }
  }

  private func contentIdentity(_ content: InAppContent) -> String {
    [content.experienceId, content.messageId, content.variantId ?? ""].joined(separator: "\0")
  }
}

private struct PagerRegistration {
  let pager: InboxPager
  let task: Task<Void, Never>

  func close() {
    task.cancel()
    pager.close()
  }
}

private func applyAttributes(_ arguments: FlutterMap, editor: inout AttributeEditor) throws {
  let values = try arguments.map("set")
  for (key, value) in values { editor.set(key, try jsonValue(value)) }
  for value in arguments.list("remove") {
    guard let key = value as? String else {
      throw EngageFlutterCodecError.invalidArgument("Attribute removals must be strings")
    }
    editor.remove(key)
  }
}

private func applyTags(_ arguments: FlutterMap, editor: inout TagEditor) throws {
  for value in arguments.list("add") {
    guard let tag = value as? String else {
      throw EngageFlutterCodecError.invalidArgument("Tag additions must be strings")
    }
    editor.add(tag)
  }
  for value in arguments.list("remove") {
    guard let tag = value as? String else {
      throw EngageFlutterCodecError.invalidArgument("Tag removals must be strings")
    }
    editor.remove(tag)
  }
}

private func applyInstallationSubscriptions(
  _ arguments: FlutterMap,
  editor: inout InstallationSubscriptionEditor
) throws {
  for value in arguments.list("changes") {
    guard let change = value as? FlutterMap else {
      throw EngageFlutterCodecError.invalidArgument("Installation subscription changes must be maps")
    }
    let list = try change.string("list")
    if try change.bool("subscribed") { editor.subscribe(list) }
    else { editor.unsubscribe(list) }
  }
}

private func applyProfileSubscriptions(
  _ arguments: FlutterMap,
  editor: inout ProfileSubscriptionEditor
) throws {
  for value in arguments.list("changes") {
    guard let change = value as? FlutterMap else {
      throw EngageFlutterCodecError.invalidArgument("Profile subscription changes must be maps")
    }
    let list = try change.string("list")
    let rawChannel = try change.string("channel")
    guard let channel = Channel(rawValue: rawChannel) else {
      throw EngageFlutterCodecError.invalidArgument("Unsupported subscription channel: \(rawChannel)")
    }
    if try change.bool("subscribed") {
      editor.subscribe(list, channels: [channel])
    } else {
      editor.unsubscribe(list, channels: [channel])
    }
  }
}

private func applyEvent(_ arguments: FlutterMap, editor: inout EventEditor) throws {
  let properties = try arguments.map("properties")
  for (key, value) in properties { editor.set(key, try jsonValue(value)) }
  if let value = arguments["value"], !(value is NSNull) {
    guard let number = value as? NSNumber else {
      throw EngageFlutterCodecError.invalidArgument("Event value must be a number")
    }
    editor.setValue(number.doubleValue)
  }
  if let value = arguments["transactionId"], !(value is NSNull) {
    guard let transactionId = value as? String else {
      throw EngageFlutterCodecError.invalidArgument("Event transactionId must be a string")
    }
    editor.setTransactionId(transactionId)
  }
}

private final class EngageInAppViewFactory: NSObject, FlutterPlatformViewFactory {
  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let key = (args as? FlutterMap)?["key"] as? String ?? ""
    EngageLogger.debug(
      "Flutter",
      "in-app platform view created viewId=\(viewId) placementKey=\(key)"
    )
    return EngageInAppPlatformView(
      frame: frame,
      key: key
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class EngageInAppPlatformView: NSObject, FlutterPlatformView {
  private let content: EngageInAppPlacementView

  init(frame: CGRect, key: String) {
    content = EngageInAppPlacementView(key: key, inApp: Engage.inApp)
    content.frame = frame
    super.init()
  }

  func view() -> UIView { content }
}

private final class EngageMessageCenterListViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let channel = FlutterMethodChannel(
      name: "io.engage.flutter/message_center_list/\(viewId)",
      binaryMessenger: messenger
    )
    let environment = messageCenterEnvironment(args)
    let readiness = EngagePlatformViewReadiness()
    let content = EngageReadyPlatformContent(readiness: readiness) {
      EngageMessageCenterListView(
        sortOrder: inboxSortOrder(args),
        materialTheme: environment.materialTheme,
        layout: environment.layout,
        onEntryTap: { entry in channel.invokeMethod("entryTap", arguments: flutterInboxEntry(entry)) },
        onError: { error in channel.invokeMethod("error", arguments: flutterMessageCenterError(error)) }
      )
      .environment(\.colorScheme, environment.colorScheme)
      .environment(\.locale, environment.locale)
    }
    return EngageHostingPlatformView(
      frame: frame,
      content: content,
      channel: channel,
      onReady: { readiness.isReady = true }
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class EngageMessageCenterDetailViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let arguments = args as? FlutterMap ?? [:]
    let entryId = InboxEntryId(arguments["entryId"] as? String ?? "")
    let channel = FlutterMethodChannel(
      name: "io.engage.flutter/message_center_detail/\(viewId)",
      binaryMessenger: messenger
    )
    let environment = messageCenterEnvironment(args)
    let readiness = EngagePlatformViewReadiness()
    let content = EngageReadyPlatformContent(readiness: readiness) {
      EngageMessageCenterDetailView(
        entryId: entryId,
        materialTheme: environment.materialTheme,
        onUnavailable: { channel.invokeMethod("unavailable", arguments: nil) },
        onError: { error in channel.invokeMethod("error", arguments: flutterMessageCenterError(error)) }
      )
      .environment(\.colorScheme, environment.colorScheme)
      .environment(\.locale, environment.locale)
    }
    return EngageHostingPlatformView(
      frame: frame,
      content: content,
      channel: channel,
      onReady: { readiness.isReady = true }
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class EngageHostingPlatformView<Content: View>: NSObject, FlutterPlatformView {
  private let container: EngageHostingContainerView
  private let channel: FlutterMethodChannel

  init(
    frame: CGRect,
    content: Content,
    channel: FlutterMethodChannel,
    onReady: @escaping () -> Void
  ) {
    container = EngageHostingContainerView(frame: frame, content: content)
    self.channel = channel
    super.init()
    channel.setMethodCallHandler { call, result in
      if call.method == "ready" {
        onReady()
        result(nil)
      }
      else { result(FlutterMethodNotImplemented) }
    }
  }

  func view() -> UIView { container }

  deinit { channel.setMethodCallHandler(nil) }
}

private final class EngagePlatformViewReadiness: ObservableObject {
  @Published var isReady = false
}

private struct EngageReadyPlatformContent<Content: View>: View {
  @ObservedObject var readiness: EngagePlatformViewReadiness
  let content: () -> Content

  init(readiness: EngagePlatformViewReadiness, @ViewBuilder content: @escaping () -> Content) {
    self.readiness = readiness
    self.content = content
  }

  @ViewBuilder var body: some View {
    if readiness.isReady { content() }
  }
}

private final class EngageHostingContainerView: UIView {
  private let controller: UIViewController
  private weak var attachedParent: UIViewController?

  init<Content: View>(frame: CGRect, content: Content) {
    controller = UIHostingController(rootView: content)
    super.init(frame: frame)
    controller.view.backgroundColor = .clear
    controller.view.translatesAutoresizingMaskIntoConstraints = false
    addSubview(controller.view)
    NSLayoutConstraint.activate([
      controller.view.leadingAnchor.constraint(equalTo: leadingAnchor),
      controller.view.trailingAnchor.constraint(equalTo: trailingAnchor),
      controller.view.topAnchor.constraint(equalTo: topAnchor),
      controller.view.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      detachController()
    } else {
      attachControllerIfNeeded()
    }
  }

  private func attachControllerIfNeeded() {
    guard attachedParent == nil else { return }
    var responder: UIResponder? = self
    while let current = responder {
      if let parent = current as? UIViewController {
        parent.addChild(controller)
        controller.didMove(toParent: parent)
        attachedParent = parent
        return
      }
      responder = current.next
    }
  }

  private func detachController() {
    guard attachedParent != nil else { return }
    controller.willMove(toParent: nil)
    controller.removeFromParent()
    attachedParent = nil
  }
}

private struct MessageCenterEnvironment {
  let colorScheme: ColorScheme
  let locale: Locale
  let materialTheme: MessageCenterMaterialTheme
  let layout: MessageCenterViewLayout
}

private func inboxSortOrder(_ args: Any?) -> InboxSortOrder {
  let arguments = args as? FlutterMap ?? [:]
  return arguments["sortOrder"] as? String == "OLDEST_FIRST" ? .oldestFirst : .newestFirst
}

private func messageCenterEnvironment(_ args: Any?) -> MessageCenterEnvironment {
  let arguments = args as? FlutterMap ?? [:]
  let material = arguments["material3"] as? FlutterMap ?? [:]
  let layout = arguments["layout"] as? FlutterMap ?? [:]
  func color(_ key: String, fallback: Color) -> Color {
    guard let number = material[key] as? NSNumber else { return fallback }
    let argb = UInt32(truncating: number)
    return Color(
      red: Double((argb >> 16) & 0xFF) / 255,
      green: Double((argb >> 8) & 0xFF) / 255,
      blue: Double(argb & 0xFF) / 255,
      opacity: Double((argb >> 24) & 0xFF) / 255
    )
  }
  func dimension(_ key: String, fallback: CGFloat) -> CGFloat {
    (layout[key] as? NSNumber).map(CGFloat.init(truncating:)) ?? fallback
  }
  let defaultTheme = MessageCenterMaterialTheme.system
  let defaultLayout = MessageCenterViewLayout.default
  return MessageCenterEnvironment(
    colorScheme: (arguments["appearance"] as? String) == "DARK" ? .dark : .light,
    locale: Locale(identifier: arguments["locale"] as? String ?? Locale.current.identifier),
    materialTheme: MessageCenterMaterialTheme(
      primary: color("primary", fallback: defaultTheme.primary),
      onPrimary: color("onPrimary", fallback: defaultTheme.onPrimary),
      primaryContainer: color("primaryContainer", fallback: defaultTheme.primaryContainer),
      surface: color("surface", fallback: defaultTheme.surface),
      surfaceContainerLow: color("surfaceContainerLow", fallback: defaultTheme.surfaceContainerLow),
      surfaceContainer: color("surfaceContainer", fallback: defaultTheme.surfaceContainer),
      onSurface: color("onSurface", fallback: defaultTheme.onSurface),
      onSurfaceVariant: color("onSurfaceVariant", fallback: defaultTheme.onSurfaceVariant),
      outlineVariant: color("outlineVariant", fallback: defaultTheme.outlineVariant),
      error: color("error", fallback: defaultTheme.error),
      onError: color("onError", fallback: defaultTheme.onError)
    ),
    layout: MessageCenterViewLayout(
      horizontalPadding: dimension("horizontalPadding", fallback: defaultLayout.horizontalPadding),
      itemSpacing: dimension("itemSpacing", fallback: defaultLayout.itemSpacing),
      itemCornerRadius: dimension("itemCornerRadius", fallback: defaultLayout.itemCornerRadius)
    )
  )
}

@MainActor
private func preferenceCenterMaterialTheme(_ arguments: FlutterMap) -> PreferenceCenterMaterialTheme {
  let material = arguments["material3"] as? FlutterMap ?? [:]
  let defaults = PreferenceCenterMaterialTheme.system
  func color(_ key: String, fallback: UIColor) -> UIColor {
    guard let number = material[key] as? NSNumber else { return fallback }
    let argb = UInt32(truncating: number)
    return UIColor(
      red: CGFloat((argb >> 16) & 0xFF) / 255,
      green: CGFloat((argb >> 8) & 0xFF) / 255,
      blue: CGFloat(argb & 0xFF) / 255,
      alpha: CGFloat((argb >> 24) & 0xFF) / 255
    )
  }
  return PreferenceCenterMaterialTheme(
    primary: color("primary", fallback: defaults.primary),
    onPrimary: color("onPrimary", fallback: defaults.onPrimary),
    primaryContainer: color("primaryContainer", fallback: defaults.primaryContainer),
    onPrimaryContainer: color("onPrimaryContainer", fallback: defaults.onPrimaryContainer),
    surface: color("surface", fallback: defaults.surface),
    surfaceContainerLow: color("surfaceContainerLow", fallback: defaults.surfaceContainerLow),
    onSurface: color("onSurface", fallback: defaults.onSurface),
    onSurfaceVariant: color("onSurfaceVariant", fallback: defaults.onSurfaceVariant),
    outlineVariant: color("outlineVariant", fallback: defaults.outlineVariant)
  )
}

private func flutterMessageCenterError(_ error: MessageCenterViewError) -> FlutterMap {
  [
    "code": error.code == .inbox ? "INBOX" : "RENDERING",
    "message": error.message,
    "isRetryable": error.isRetryable,
  ]
}
