import 'models.dart';
import 'engage_logging.dart';

final RegExp _keyPattern = RegExp(r'^[a-z][a-z0-9_.-]{0,127}$');
final RegExp _eventPattern = RegExp(r'^[a-z][a-z0-9_]{1,63}$');

void validateProductKey(String key, {String label = 'Key'}) {
  if (!_keyPattern.hasMatch(key)) {
    throw ArgumentError.value(key, label, 'must be a lowercase product key');
  }
  EngageLog.verbose('Editor', 'product key validated label=$label key=$key');
}

void validateEventName(String name) {
  if (!_eventPattern.hasMatch(name)) {
    throw ArgumentError.value(
      name,
      'name',
      'must match ${_eventPattern.pattern}',
    );
  }
  EngageLog.verbose('Editor', 'event name validated name=$name');
}

Object? _wireValue(Object? value) {
  if (value == null || value is String || value is bool || value is int) {
    return value;
  }
  if (value is double) {
    if (!value.isFinite) {
      throw ArgumentError.value(value, 'value', 'must be finite');
    }
    return value;
  }
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is List) return value.map(_wireValue).toList(growable: false);
  if (value is Map<String, Object?>) {
    return value.map((key, item) => MapEntry(key, _wireValue(item)));
  }
  throw ArgumentError.value(
    value,
    'value',
    'must be JSON-compatible or a DateTime',
  );
}

final class AttributeEditor {
  final Map<String, Object?> _values = {};
  final Set<String> _removals = {};

  void set(String key, Object? value) {
    validateProductKey(key, label: 'attribute key');
    _removals.remove(key);
    _values[key] = _wireValue(value);
    EngageLog.verbose(
      'Editor',
      'attribute set key=$key type=${_valueType(value)}',
    );
  }

  void remove(String key) {
    validateProductKey(key, label: 'attribute key');
    _values.remove(key);
    _removals.add(key);
    EngageLog.verbose('Editor', 'attribute removed key=$key');
  }

  JsonMap toJson() => {
    'set': Map<String, Object?>.unmodifiable(_values),
    'remove': _removals.toList(growable: false),
  };

  bool get isEmpty => _values.isEmpty && _removals.isEmpty;
}

final class TagEditor {
  final Set<String> _additions = {};
  final Set<String> _removals = {};

  void add(String tag) {
    _validateTag(tag);
    _removals.remove(tag);
    _additions.add(tag);
    EngageLog.verbose('Editor', 'tag added length=${tag.length}');
  }

  void remove(String tag) {
    _validateTag(tag);
    _additions.remove(tag);
    _removals.add(tag);
    EngageLog.verbose('Editor', 'tag removed length=${tag.length}');
  }

  JsonMap toJson() => {
    'add': _additions.toList(growable: false),
    'remove': _removals.toList(growable: false),
  };

  bool get isEmpty => _additions.isEmpty && _removals.isEmpty;

  void _validateTag(String tag) {
    if (tag.trim().isEmpty || tag.length > 64) {
      throw ArgumentError.value(
        tag,
        'tag',
        'must contain between 1 and 64 characters',
      );
    }
  }
}

final class EventEditor {
  final Map<String, Object?> _properties = {};
  double? value;
  String? transactionId;

  void put(String key, Object? value) {
    validateProductKey(key, label: 'event property key');
    _properties[key] = _wireValue(value);
    EngageLog.verbose(
      'Editor',
      'event property set key=$key type=${_valueType(value)}',
    );
  }

  JsonMap toJson() {
    if (value?.isFinite == false) {
      throw ArgumentError.value(value, 'value', 'must be finite');
    }
    if ((transactionId?.length ?? 0) > 255) {
      throw ArgumentError.value(
        transactionId,
        'transactionId',
        'must contain at most 255 characters',
      );
    }
    return {
      'properties': Map<String, Object?>.unmodifiable(_properties),
      'value': ?value,
      'transactionId': ?transactionId,
    };
  }
}

final class ProfileSubscriptionEditor {
  final Map<String, JsonMap> _changes = {};

  void subscribe(String list, Set<Channel> channels) =>
      _edit(list, channels, subscribed: true);

  void unsubscribe(String list, Set<Channel> channels) =>
      _edit(list, channels, subscribed: false);

  List<JsonMap> toJson() => List.unmodifiable(_changes.values);
  bool get isEmpty => _changes.isEmpty;

  void _edit(String list, Set<Channel> channels, {required bool subscribed}) {
    validateProductKey(list, label: 'subscription list');
    if (channels.isEmpty) {
      throw ArgumentError('At least one channel is required');
    }
    for (final channel in channels) {
      _changes['$list\u{0}${channel.name}'] = {
        'list': list,
        'channel': _enumWire(channel),
        'subscribed': subscribed,
      };
      EngageLog.verbose(
        'Editor',
        'profile subscription list=$list channel=${channel.name} subscribed=$subscribed',
      );
    }
  }
}

final class InstallationSubscriptionEditor {
  final Map<String, bool> _changes = {};

  void subscribe(String list) => _edit(list, subscribed: true);
  void unsubscribe(String list) => _edit(list, subscribed: false);

  List<JsonMap> toJson() => _changes.entries
      .map(
        (entry) => <String, Object?>{
          'list': entry.key,
          'subscribed': entry.value,
        },
      )
      .toList(growable: false);
  bool get isEmpty => _changes.isEmpty;

  void _edit(String list, {required bool subscribed}) {
    validateProductKey(list, label: 'subscription list');
    _changes[list] = subscribed;
    EngageLog.verbose(
      'Editor',
      'installation subscription list=$list subscribed=$subscribed',
    );
  }
}

final class SdkFeatureEditor {
  SdkFeatureEditor(Set<SdkFeature> enabled) : _enabled = {...enabled};

  final Set<SdkFeature> _enabled;

  void enable(SdkFeature feature) {
    _enabled.add(feature);
    EngageLog.verbose('Editor', 'feature enabled feature=${feature.name}');
  }

  void disable(SdkFeature feature) {
    _enabled.remove(feature);
    EngageLog.verbose('Editor', 'feature disabled feature=${feature.name}');
  }

  Set<SdkFeature> build() => Set.unmodifiable(_enabled);
}

String enumWire(Enum value) => _enumWire(value);

String _enumWire(Enum value) {
  if (value == NotificationImportance.defaultImportance) return 'DEFAULT';
  final words = value.name.replaceAllMapped(
    RegExp('[A-Z]'),
    (match) => '_${match.group(0)}',
  );
  return words.toUpperCase();
}

String _valueType(Object? value) => switch (value) {
  null => 'null',
  bool() => 'boolean',
  int() => 'integer',
  double() => 'number',
  String() => 'string',
  DateTime() => 'date',
  List() => 'array',
  Map() => 'object',
  _ => value.runtimeType.toString(),
};
