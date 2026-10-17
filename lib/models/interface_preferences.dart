/// Copies JSON-compatible UI preferences without sharing mutable collections.
Object? copyInterfacePreference(Object? value, [int depth = 0]) {
  if (depth > 8) return null;
  if (value == null || value is bool || value is String) return value;
  if (value is num) return value.isFinite ? value : null;
  if (value is List) {
    return List<Object?>.unmodifiable(
      value.take(1000).map((item) => copyInterfacePreference(item, depth + 1)),
    );
  }
  if (value is Map) {
    return Map<String, Object?>.unmodifiable({
      for (final entry in value.entries.take(1000))
        if (entry.key is String)
          entry.key as String: copyInterfacePreference(entry.value, depth + 1),
    });
  }
  return null;
}

Map<String, Object?> readInterfacePreferences(Object? value) {
  final copied = copyInterfacePreference(value);
  return copied is Map<String, Object?> ? copied : const {};
}
