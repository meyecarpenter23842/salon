import 'dart:convert';
import 'dart:io';

import '../database/salon_database.dart';
import 'lan_contract.dart';
import 'lan_health_client.dart';
import 'lan_pairing.dart';

/// A bounded invalidation watermark, not a stream of private business records.
/// Missing intermediate notifications always cause a full read resync.
class LanChangeSnapshot {
  const LanChangeSnapshot(this.epoch, this.cursor, {required this.reset, required this.changed});
  final String epoch;
  final int cursor;
  final bool reset, changed;
  Map<String, Object> toJson() => {'apiVersion': 1, 'epoch': epoch, 'cursor': cursor,
    'reset': reset, 'changed': changed};
  factory LanChangeSnapshot.fromJson(Map<String, dynamic> json) {
    if (json.length != 5 || json['apiVersion'] != 1 || json['epoch'] is! String ||
        !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(json['epoch'] as String) ||
        json['cursor'] is! int || (json['cursor'] as int) < 1 ||
        (json['cursor'] as int) > 9007199254740991 ||
        json['reset'] is! bool || json['changed'] is! bool) {
      throw const FormatException('Invalid change snapshot');
    }
    return LanChangeSnapshot(json['epoch'] as String, json['cursor'] as int,
      reset: json['reset'] as bool, changed: json['changed'] as bool);
  }
}

abstract interface class LanChangeSource {
  Future<LanChangeSnapshot> read(String? epoch, int cursor);
}

/// Both same-connection writes and detached Staff-process commits are observed.
/// No timestamp/file-size heuristic and no database migration is required.
Future<String> sqliteChangeFingerprint(SalonDatabase database) async {
  final db = await database.database;
  final external = (await db.rawQuery('PRAGMA data_version')).single.values.single;
  final local = (await db.rawQuery('SELECT total_changes() AS n')).single['n'];
  return '${database.runtimeEpoch}:$external:$local';
}

class SqliteLanChanges implements LanChangeSource {
  SqliteLanChanges(this.database);
  final SalonDatabase database;
  String? _fingerprint;
  int _cursor = 0;
  Future<void> _tail = Future.value();
  @override Future<LanChangeSnapshot> read(String? epoch, int cursor) {
    // Serialize probes so concurrent phones cannot move a cursor backwards.
    final operation = _tail.then((_) async {
      final fingerprint = await sqliteChangeFingerprint(database);
      if (_fingerprint != fingerprint) { _fingerprint = fingerprint; _cursor++; }
      final currentEpoch = database.runtimeEpoch;
      final reset = epoch != currentEpoch || cursor < 1 || cursor > _cursor;
      return LanChangeSnapshot(currentEpoch, _cursor, reset: reset, changed: reset || cursor != _cursor);
    });
    _tail = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }
}

abstract interface class LanChangeClient {
  Future<LanChangeSnapshot> read(LanConnection connection, String token, String? epoch, int cursor);
}
class PinnedLanChangeClient implements LanChangeClient {
  const PinnedLanChangeClient({this.timeout = const Duration(seconds: 8)});
  final Duration timeout;
  @override Future<LanChangeSnapshot> read(LanConnection connection, String token, String? epoch, int cursor) async {
    final client = HttpClient(context: SecurityContext(withTrustedRoots: false));
    client.connectionTimeout = timeout; client.findProxy = (_) => 'DIRECT';
    client.badCertificateCallback = connection.matches;
    try {
      return await (() async {
        final uri = connection.apiUrl.replace(path: '${LanContract.basePath}/changes',
          queryParameters: {'cursor': '$cursor', 'epoch': ?epoch});
        final request = await client.getUrl(uri);
        request.followRedirects = false;
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        final response = await request.close();
        if (response.certificate == null || !connection.matches(response.certificate!,
            connection.apiUrl.host, connection.apiUrl.port)) { throw const FormatException('Certificate mismatch'); }
        final bytes = <int>[];
        await for (final chunk in response) {
          if (bytes.length + chunk.length > 2048) { throw const FormatException('Change response too large'); }
          bytes.addAll(chunk);
        }
        final json = jsonDecode(utf8.decode(bytes));
        if (json is! Map<String, dynamic> || json['apiVersion'] != 1) { throw const FormatException('Unsupported response'); }
        if (response.statusCode != HttpStatus.ok) {
          final error = json['error']; final name = error is Map ? error['code'] : null;
          throw PairingFailure(LanErrorCode.values.where((c) => c.wireName == name).firstOrNull ?? LanErrorCode.unavailable);
        }
        return LanChangeSnapshot.fromJson(json);
      })().timeout(timeout);
    } finally { client.close(force: true); }
  }
}
