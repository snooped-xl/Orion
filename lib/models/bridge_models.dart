import 'package:flutter/foundation.dart';

/// A player session, shared by every Orion interface.
@immutable
class BridgeClient {
  const BridgeClient({
    required this.identifier,
    required this.username,
    required this.transport,
    this.clientLabel = '',
    this.executorName = '',
    this.sessionId = '',
    this.pendingCount = 0,
  });
  final String identifier;

  /// Display name; `username` is retained as the original v2 wire key.
  final String username;
  String get displayName => username;
  final String transport;
  final String clientLabel;
  final String executorName;
  final String sessionId;
  final int pendingCount;
  Map<String, Object?> toJson() => {
    'identifier': identifier,
    'username': username,
    'transport': transport,
    'clientLabel': clientLabel,
    'executorName': executorName,
    'sessionId': sessionId,
    'pendingCount': pendingCount,
  };
  factory BridgeClient.fromJson(Map<String, dynamic> value) => BridgeClient(
    identifier: value['identifier']?.toString() ?? 'User1',
    username: value['username']?.toString() ?? 'Unknown',
    transport: value['transport']?.toString() ?? 'port',
    clientLabel: value['clientLabel']?.toString() ?? '',
    executorName: _executorName(value['executorName']),
    sessionId: value['sessionId']?.toString() ?? '',
    pendingCount: value['pendingCount'] is num
        ? (value['pendingCount'] as num).toInt()
        : 0,
  );
  static String _executorName(Object? value) {
    if (value is! String) return '';
    final clean = value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
    return clean.length <= 64 ? clean : clean.substring(0, 64);
  }
}

@immutable
class BridgeLogEntry {
  const BridgeLogEntry({
    required this.timestampUtc,
    required this.level,
    required this.message,
    this.identifier,
    this.executionId,
  });
  final DateTime timestampUtc;
  final String level;
  final String message;
  final String? identifier;
  final String? executionId;
  Map<String, Object?> toJson() => {
    'timestampUtc': timestampUtc.toIso8601String(),
    'level': level,
    'message': message,
    if (identifier != null) 'identifier': identifier,
    if (executionId != null) 'executionId': executionId,
  };
  factory BridgeLogEntry.fromJson(Map<String, dynamic> value) => BridgeLogEntry(
    timestampUtc:
        DateTime.tryParse(value['timestampUtc']?.toString() ?? '')?.toUtc() ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    level: value['level']?.toString() ?? 'info',
    message: value['message']?.toString() ?? '',
    identifier: value['identifier']?.toString(),
    executionId: value['executionId']?.toString(),
  );
}

/// Delivery means queued for an active client, not that its script succeeded.
@immutable
class BridgeExecutionReceipt {
  BridgeExecutionReceipt({required this.id, required Iterable<String> targets})
    : targetIdentifiers = List.unmodifiable(targets);
  final String id;
  final List<String> targetIdentifiers;
  int get deliveredCount => targetIdentifiers.length;
  int get queuedCount => deliveredCount;
}
