import '../domain/models.dart';

InboxEntry decodeInboxEntry(Object? value) {
  final map = messageCenterMap(value);
  return InboxEntry(
    id: InboxEntryId(map['id']! as String),
    key: map['key']! as String,
    payload: messageCenterMap(map['payload']),
    sentAt: DateTime.parse(map['sentAt']! as String),
    expiresAt: _nullableDate(map['expiresAt']),
    readAt: _nullableDate(map['readAt']),
  );
}

JsonMap messageCenterMap(Object? value) {
  if (value is! Map) {
    throw FormatException(
      'Expected a Message Center map, got ${value.runtimeType}',
    );
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}

DateTime? _nullableDate(Object? value) =>
    value == null ? null : DateTime.parse(value as String);
