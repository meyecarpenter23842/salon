import 'package:uuid/uuid.dart';

/// Generates collision-resistant IDs for newly created business records.
///
/// IDs stay TEXT in SQLite and keep a short entity prefix for diagnostics while
/// the unique portion is UUID v4. Existing IDs are never rewritten.
class EntityId {
  const EntityId._();

  static const Uuid _uuid = Uuid();

  static String create(String prefix) {
    final normalized = prefix.trim().toLowerCase();
    if (normalized.isEmpty || !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(normalized)) {
      throw ArgumentError.value(
        prefix,
        'prefix',
        'Use a non-empty lowercase entity prefix containing letters, numbers, or underscores.',
      );
    }

    return '$normalized-${_uuid.v4()}';
  }
}
