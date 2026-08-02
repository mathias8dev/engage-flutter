import Foundation
import UserNotifications
import EngageSDK

typealias FlutterMap = [String: Any]

enum EngageFlutterCodecError: Error {
  case invalidArgument(String)
}

extension Dictionary where Key == String, Value == Any {
  func string(_ key: String) throws -> String {
    guard let value = self[key] as? String else {
      throw EngageFlutterCodecError.invalidArgument("Missing string: \(key)")
    }
    return value
  }

  func bool(_ key: String) throws -> Bool {
    guard let value = self[key] as? Bool else {
      throw EngageFlutterCodecError.invalidArgument("Missing boolean: \(key)")
    }
    return value
  }

  func map(_ key: String) throws -> FlutterMap {
    guard let value = self[key] as? FlutterMap else {
      throw EngageFlutterCodecError.invalidArgument("Missing map: \(key)")
    }
    return value
  }

  func list(_ key: String) -> [Any] { self[key] as? [Any] ?? [] }
}

func engageConfig(_ value: FlutterMap) throws -> EngageConfig {
  let push = try value.map("push")
  let foreground = ForegroundPresentation(rawFlutter: try push.string("foregroundPresentation"))
  let ios = push["ios"] as? FlutterMap
  let categories = try Set((ios?.list("categories") ?? []).map(notificationCategory))
  let endpointValue = try value.string("endpoint")
  guard let endpoint = URL(string: endpointValue),
        let scheme = endpoint.scheme?.lowercased(),
        ["http", "https"].contains(scheme),
        endpoint.host != nil else {
    throw EngageFlutterCodecError.invalidArgument("Invalid HTTP(S) endpoint: \(endpointValue)")
  }
  return EngageConfig(
    appKey: try value.string("appKey"),
    endpoint: endpoint,
    push: PushConfig(
      foregroundPresentation: foreground,
      notificationCategories: categories
    )
  )
}

private func notificationCategory(_ value: Any) throws -> UNNotificationCategory {
  guard let category = value as? FlutterMap else {
    throw EngageFlutterCodecError.invalidArgument("Invalid iOS notification category")
  }
  let actions = try category.list("actions").map(notificationAction)
  return UNNotificationCategory(
    identifier: try category.string("key"),
    actions: actions,
    intentIdentifiers: [],
    hiddenPreviewsBodyPlaceholder: category["hiddenPreviewsBodyPlaceholder"] as? String,
    options: []
  )
}

private func notificationAction(_ value: Any) throws -> UNNotificationAction {
  guard let action = value as? FlutterMap else {
    throw EngageFlutterCodecError.invalidArgument("Invalid iOS notification action")
  }
  var options: UNNotificationActionOptions = []
  if (action["foreground"] as? Bool) == true { options.insert(.foreground) }
  if (action["destructive"] as? Bool) == true { options.insert(.destructive) }
  if (action["authenticationRequired"] as? Bool) == true {
    options.insert(.authenticationRequired)
  }
  return UNNotificationAction(
    identifier: try action.string("key"),
    title: try action.string("title"),
    options: options
  )
}

private extension ForegroundPresentation {
  init(rawFlutter: String) {
    self = rawFlutter == "SILENT" ? .silent : .show
  }
}

func jsonValue(_ value: Any?) throws -> JSONValue {
  switch value {
  case nil, is NSNull: return .null
  case let value as Bool: return .bool(value)
  case let value as Int: return .integer(Int64(value))
  case let value as Int64: return .integer(value)
  case let value as NSNumber:
    let double = value.doubleValue
    guard double.isFinite else {
      throw EngageFlutterCodecError.invalidArgument("JSON numbers must be finite")
    }
    return .number(double)
  case let value as String: return .string(value)
  case let value as [Any]: return .array(try value.map(jsonValue))
  case let value as FlutterMap:
    return .object(try value.mapValues(jsonValue))
  default:
    throw EngageFlutterCodecError.invalidArgument("Unsupported JSON value: \(type(of: value))")
  }
}

func flutterValue(_ value: JSONValue) -> Any {
  switch value {
  case .null: return NSNull()
  case let .bool(value): return value
  case let .integer(value): return value
  case let .number(value): return value
  case let .string(value): return value
  case let .array(value): return value.map(flutterValue)
  case let .object(value): return value.mapValues(flutterValue)
  }
}

private func flutterOptional<T>(_ value: T?) -> Any {
  guard let value else { return NSNull() }
  return value
}

func flutterPushStatus(_ status: PushStatus) -> FlutterMap {
  [
    "permission": status.permission.rawValue,
    "subscription": status.subscription.rawValue,
    "tokenRegistered": status.tokenRegistered,
  ]
}

func flutterPushEvent(_ event: PushEvent) -> FlutterMap {
  switch event {
  case let .received(deliveryId, messageId, data):
    return ["type": "RECEIVED", "deliveryId": deliveryId, "messageId": messageId, "data": data]
  case let .opened(deliveryId, messageId, deepLink, data):
    return [
      "type": "OPENED", "deliveryId": deliveryId, "messageId": messageId,
      "deepLink": flutterOptional(deepLink?.absoluteString), "data": data,
    ]
  case let .dismissed(deliveryId, messageId):
    return ["type": "DISMISSED", "deliveryId": deliveryId, "messageId": messageId]
  case let .actionSelected(deliveryId, messageId, actionKey, data):
    return [
      "type": "ACTION_SELECTED", "deliveryId": deliveryId, "messageId": messageId,
      "actionKey": actionKey, "data": data,
    ]
  case let .registrationFailed(message):
    return ["type": "REGISTRATION_FAILED", "message": message]
  }
}

func flutterInAppContent(_ content: InAppContent) -> FlutterMap {
  [
    "experienceId": content.experienceId,
    "messageId": content.messageId,
    "variantId": flutterOptional(content.variantId),
    "type": content.type.rawValue,
    "payload": content.payload.mapValues(flutterValue),
    "presentation": flutterPresentation(content.presentation),
  ]
}

private func flutterPresentation(_ presentation: PresentationSpec) -> FlutterMap {
  switch presentation {
  case let .overlay(value):
    return [
      "kind": "OVERLAY", "format": value.format.rawValue,
      "position": flutterOptional(value.position?.rawValue), "backdrop": value.backdrop.rawValue,
      "dismissal": value.dismissal.rawValue, "animation": value.animation.rawValue,
      "autoDismissAfterSeconds": flutterOptional(value.autoDismissAfterSeconds),
    ]
  case let .embedded(value):
    return [
      "kind": "EMBEDDED", "placementKey": value.placementKey,
      "emptyState": value.emptyState.rawValue,
    ]
  }
}

func flutterPreferenceCenter(_ center: PreferenceCenterSnapshot) -> FlutterMap {
  [
    "key": center.key,
    "displayName": center.displayName,
    "description": flutterOptional(center.description),
    "sections": center.sections.map { section in
      [
        "key": section.key,
        "title": flutterOptional(section.title),
        "description": flutterOptional(section.description),
        "subscriptions": section.subscriptions.map { subscription in
          [
            "key": subscription.key,
            "displayName": subscription.displayName,
            "description": flutterOptional(subscription.description),
            "profileChoices": flutterOptional(subscription.profileChoices?.reduce(into: FlutterMap()) {
              $0[$1.key.rawValue] = $1.value
            }),
            "installationChoice": flutterOptional(subscription.installationChoice),
          ]
        },
      ] as FlutterMap
    },
  ]
}

func flutterPagerState(_ state: InboxPagerState) -> FlutterMap {
  [
    "entries": state.entries.map { entry in
      [
        "id": entry.id.value,
        "key": entry.key,
        "payload": entry.payload.mapValues(flutterValue),
        "sentAt": iso8601(entry.sentAt),
        "expiresAt": flutterOptional(entry.expiresAt.map(iso8601)),
        "readAt": flutterOptional(entry.readAt.map(iso8601)),
      ] as FlutterMap
    },
    "isRefreshing": state.isRefreshing,
    "isLoadingMore": state.isLoadingMore,
    "hasMore": state.hasMore,
    "error": flutterOptional(state.error.map { error in
      [
        "code": inboxErrorCode(error.code),
        "message": error.message,
        "isRetryable": error.isRetryable,
      ] as FlutterMap
    }),
  ]
}

private func inboxErrorCode(_ code: InboxErrorCode) -> String {
  switch code {
  case .network: return "NETWORK"
  case .unauthorized: return "UNAUTHORIZED"
  case .generationChanged: return "GENERATION_CHANGED"
  case .server: return "SERVER"
  case .invalidResponse: return "INVALID_RESPONSE"
  case .localPersistence: return "LOCAL_PERSISTENCE"
  }
}

private func iso8601(_ date: Date) -> String {
  ISO8601DateFormatter().string(from: date)
}
