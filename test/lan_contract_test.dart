import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/lan/lan_backend_policy.dart';
import 'package:salonmanager/core/lan/lan_contract.dart';

void main() {
  test('command wire roundtrip retains explicit bill and revision', () {
    final command = LanCommand.fromJson({
      'commandId': 'command-123',
      'sessionId': 'invoice-draft-001',
      'expectedRevision': 0,
    });
    expect(command.toJson(), {
      'commandId': 'command-123',
      'sessionId': 'invoice-draft-001',
      'expectedRevision': 0,
    });
    expect(
      LanContract.sessionPath(command.sessionId),
      '/api/staff/v1/billing-sessions/invoice-draft-001',
    );
  });

  test('malformed commands cannot default to the selected desktop bill', () {
    for (final payload in <Map<String, Object?>>[
      {},
      {'commandId': 'x', 'sessionId': 'bill'},
      {'commandId': 'x', 'sessionId': 'bill', 'expectedRevision': '1'},
      {'commandId': 'x', 'sessionId': 'bill', 'expectedRevision': 1.0},
      {'commandId': 'x', 'sessionId': 'bill', 'expectedRevision': -1},
      {'commandId': '', 'sessionId': 'bill', 'expectedRevision': 0},
      {'commandId': 'x', 'sessionId': '../bill', 'expectedRevision': 0},
      {'commandId': 'x', 'sessionId': 'bill?x', 'expectedRevision': 0},
      {'commandId': 'x' * 129, 'sessionId': 'bill', 'expectedRevision': 0},
    ]) {
      expect(() => LanCommand.fromJson(payload), throwsFormatException);
    }
    expect(() => LanContract.sessionPath(''), throwsFormatException);
  });

  test('health and failures expose only version and stable codes', () {
    expect(const LanHealth().toJson(), {'apiVersion': 1, 'status': 'ok'});
    final payload = const LanFailure(
      LanErrorCode.revisionConflict,
      requestId: 'request-1',
    ).toJson();
    expect(jsonDecode(jsonEncode(payload)), {
      'apiVersion': 1,
      'requestId': 'request-1',
      'error': {'code': 'revision_conflict'},
    });
    expect(LanErrorCode.revisionConflict.httpStatus, 409);
    expect(LanErrorCode.unauthenticated.httpStatus, 401);
    expect(
      LanErrorCode.values.map((code) => code.wireName).toSet().length,
      LanErrorCode.values.length,
    );
  });

  test('only enabled licensed desktop main is eligible to serve', () {
    for (final role in LanRuntimeRole.values) {
      for (final enabled in [false, true]) {
        for (final authorized in [false, true]) {
          final policy = LanBackendPolicy(
            role: role,
            enabled: enabled,
            licenseAuthorized: authorized,
          );
          final eligible =
              role == LanRuntimeRole.desktopMain && enabled && authorized;
          expect(policy.mayOwnBackend, eligible);
          for (final state in LanBackendState.values) {
            expect(
              policy.shouldServe(state),
              eligible && state == LanBackendState.ready,
            );
          }
        }
      }
    }
  });
}
