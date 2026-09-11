import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/services/diagnostic_support_service.dart';

void main() {
  test('diagnostic sanitizer redacts user paths, secrets and direct email PII', () {
    final raw = [
      r'Database: C:\Users\Alice\AppData\Roaming\HairSpaManager\data\salon_manager.db',
      r'User: C:\Users\Alice\Desktop',
      'licenseKey=super-secret-license',
      '{"token":"token-123","email":"owner@example.com","phone":"0912345678"}',
    ].join('\n');

    final sanitized = sanitizeDiagnosticText(
      raw,
      environment: const {
        'APPDATA': r'C:\Users\Alice\AppData\Roaming',
        'USERPROFILE': r'C:\Users\Alice',
      },
    );

    expect(sanitized, contains('%APPDATA%'));
    expect(sanitized, contains('%USERPROFILE%'));
    expect(sanitized, isNot(contains('Alice\\AppData')));
    expect(sanitized, isNot(contains('super-secret-license')));
    expect(sanitized, isNot(contains('token-123')));
    expect(sanitized, isNot(contains('owner@example.com')));
    expect(sanitized, isNot(contains('0912345678')));
    expect(sanitized, contains('[REDACTED]'));
  });

  test('diagnostic report exports only approved bounded support log sections', () {
    final snapshot = DiagnosticSnapshot(
      collectedAtUtc: DateTime.utc(2026, 9, 11, 12, 30),
      appVersion: '1.8.0',
      buildNumber: '18',
      operatingSystem: 'Windows',
      operatingSystemVersion: 'Windows 11',
      schemaVersion: 12,
      databasePath:
          r'C:\Users\Alice\AppData\Roaming\HairSpaManager\data\.salon_manager\salon_manager.db',
      backupDirectory:
          r'C:\Users\Alice\AppData\Roaming\HairSpaManager\data\backups',
      logsDirectory:
          r'C:\Users\Alice\AppData\Roaming\HairSpaManager\logs',
      updateFeed: 'https://updates.example.test',
    );

    final report = composeDiagnosticReport(
      snapshot: snapshot,
      logs: const {
        'startup_failure.log': 'email=owner@example.com',
        'update_audit.log': 'token=runtime-token',
        'self_update_helper.log': 'installer_success_restart',
        'customer_dump.log': 'SHOULD_NOT_EXPORT',
      },
      environment: const {
        'APPDATA': r'C:\Users\Alice\AppData\Roaming',
        'USERPROFILE': r'C:\Users\Alice',
      },
    );

    expect(report, contains('Hair Spa Manager - Diagnostic Support Report'));
    expect(report, contains('Version: 1.8.0+18'));
    expect(report, contains('Database schema: 12'));
    expect(report, contains('[Log: startup_failure.log]'));
    expect(report, contains('[Log: update_audit.log]'));
    expect(report, contains('[Log: self_update_helper.log]'));
    expect(report, isNot(contains('customer_dump.log')));
    expect(report, isNot(contains('SHOULD_NOT_EXPORT')));
    expect(report, isNot(contains('owner@example.com')));
    expect(report, isNot(contains('runtime-token')));
    expect(report, contains('%APPDATA%'));
    expect(
      report,
      contains(
        'SQLite databases, backups, customer records, credentials and license secrets are not attached.',
      ),
    );
  });
}
