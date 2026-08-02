import Flutter
import UIKit
import EngageSDK

public final class EngageFlutterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let methods: FlutterMethodChannel
  private var eventSink: FlutterEventSink?
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
  }

  init(methods: FlutterMethodChannel) {
    self.methods = methods
    super.init()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    Task { @MainActor in
      do {
        let arguments = call.arguments as? FlutterMap ?? [:]
        switch call.method {
        case "start":
          Engage.start(config: try engageConfig(arguments))
          startObserversIfNeeded()
          result(nil)
        case "installation.issueBindingCode":
          result(try await Engage.installation.issueBindingCode())
        case "installation.editAttributes":
          Engage.installation.editAttributes { try? applyAttributes(arguments, editor: &$0) }
          result(nil)
        case "installation.editSubscriptions":
          Engage.installation.editSubscriptions {
            applyInstallationSubscriptions(arguments, editor: &$0)
          }
          result(nil)
        case "profile.editAttributes":
          Engage.profile.editAttributes { try? applyAttributes(arguments, editor: &$0) }
          result(nil)
        case "profile.editTags":
          Engage.profile.editTags { applyTags(arguments, editor: &$0) }
          result(nil)
        case "profile.editSubscriptions":
          Engage.profile.editSubscriptions { applyProfileSubscriptions(arguments, editor: &$0) }
          result(nil)
        case "events.track":
          Engage.events.track(try arguments.string("name")) {
            try? applyEvent(arguments, editor: &$0)
          }
          result(nil)
        case "events.trackScreen":
          Engage.events.trackScreen(try arguments.string("screenKey"))
          result(nil)
        case "events.clearScreen":
          Engage.events.clearScreen()
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
        case "preferenceCenter.display":
          Engage.preferenceCenter.display(arguments["key"] as? String)
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
        case "messageCenter.display":
          Engage.messageCenter.display()
          result(nil)
        case "messageCenter.pager.create":
          createPager(
            id: try arguments.string("pagerId"),
            pageSize: (arguments["pageSize"] as? NSNumber)?.intValue ?? 20
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
          result(FlutterMethodNotImplemented)
        }
      } catch {
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
    eventSink = events
    if started { emitCurrentState() }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  public func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    guard started else { return }
    Engage.push.didRegisterForRemoteNotifications(deviceToken: deviceToken)
  }

  public func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    guard started else { return }
    Engage.push.didFailToRegisterForRemoteNotifications(error: error)
  }

  private func startObserversIfNeeded() {
    guard !started else { return }
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
  }

  private func emitCurrentState() {
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
  }

  private func observePreferenceCenter(_ key: String?) {
    let scope = key ?? ""
    guard centerTasks[scope] == nil else { return }
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
    guard placementTasks[key] == nil else { return }
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

  private func createPager(id: String, pageSize: Int) {
    guard pagers[id] == nil else { return }
    let inboxPager = Engage.messageCenter.inbox.pager(pageSize: pageSize)
    let task = Task { [weak self] in
      for await value in inboxPager.state.updates {
        self?.emit(key: "messageCenter.pager", value: flutterPagerState(value), scope: id)
      }
    }
    pagers[id] = PagerRegistration(pager: inboxPager, task: task)
  }

  private func closePager(_ id: String) {
    pagers.removeValue(forKey: id)?.close()
  }

  private func pager(_ arguments: FlutterMap) throws -> PagerRegistration {
    let id = try arguments.string("pagerId")
    guard let pager = pagers[id] else {
      throw EngageFlutterCodecError.invalidArgument("Unknown Inbox pager: \(id)")
    }
    return pager
  }

  private func registerAction(_ name: String) {
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
  }

  private func unregisterAction(_ name: String) {
    actions.removeValue(forKey: name)?.cancel()
  }

  private func requestOverlayDecision(key: String, candidate: InAppContent) {
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
    }
  }

  private func invokeDart(method: String, arguments: Any?) async -> Any? {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async { [methods] in
        methods.invokeMethod(method, arguments: arguments) { value in
          continuation.resume(returning: value)
        }
      }
    }
  }

  private func emit(key: String, value: Any?, scope: String? = nil) {
    let sink = eventSink
    guard let sink else { return }
    var envelope: FlutterMap = ["key": key, "value": value ?? NSNull()]
    if let scope { envelope["scope"] = scope }
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
  for case let key as String in arguments.list("remove") { editor.remove(key) }
}

private func applyTags(_ arguments: FlutterMap, editor: inout TagEditor) {
  for case let tag as String in arguments.list("add") { editor.add(tag) }
  for case let tag as String in arguments.list("remove") { editor.remove(tag) }
}

private func applyInstallationSubscriptions(
  _ arguments: FlutterMap,
  editor: inout InstallationSubscriptionEditor
) {
  for case let change as FlutterMap in arguments.list("changes") {
    guard let list = change["list"] as? String else { continue }
    if change["subscribed"] as? Bool == true { editor.subscribe(list) }
    else { editor.unsubscribe(list) }
  }
}

private func applyProfileSubscriptions(
  _ arguments: FlutterMap,
  editor: inout ProfileSubscriptionEditor
) {
  for case let change as FlutterMap in arguments.list("changes") {
    guard let list = change["list"] as? String,
          let rawChannel = change["channel"] as? String,
          let channel = Channel(rawValue: rawChannel) else { continue }
    if change["subscribed"] as? Bool == true {
      editor.subscribe(list, channels: [channel])
    } else {
      editor.unsubscribe(list, channels: [channel])
    }
  }
}

private func applyEvent(_ arguments: FlutterMap, editor: inout EventEditor) throws {
  let properties = try arguments.map("properties")
  for (key, value) in properties { editor.set(key, try jsonValue(value)) }
  editor.setValue((arguments["value"] as? NSNumber)?.doubleValue)
  editor.setTransactionId(arguments["transactionId"] as? String)
}

private final class EngageInAppViewFactory: NSObject, FlutterPlatformViewFactory {
  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    EngageInAppPlatformView(
      frame: frame,
      key: (args as? FlutterMap)?["key"] as? String ?? ""
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
