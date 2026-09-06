import 'package:flutter_test/flutter_test.dart';
import 'package:salonmanager/core/services/offline_update_service.dart';

void main() {
  group('Windows updater version contract', () {
    test('compares semantic versions and ignores build suffix', () {
      expect(compareSalonVersions('1.8.0', '1.7.5'), greaterThan(0));
      expect(compareSalonVersions('1.8.0+18', '1.8.0+17'), 0);
      expect(compareSalonVersions('1.8.0', '1.8.0'), 0);
      expect(compareSalonVersions('1.7.9', '1.8.0'), lessThan(0));
    });

    test('reports success only after restart into exact target version', () {
      expect(
        isExpectedInstalledVersion(
          currentVersion: '1.8.0',
          fromVersion: '1.7.5',
          targetVersion: '1.8.0',
        ),
        isTrue,
      );
      expect(
        isExpectedInstalledVersion(
          currentVersion: '1.7.5',
          fromVersion: '1.7.5',
          targetVersion: '1.8.0',
        ),
        isFalse,
      );
      expect(
        isExpectedInstalledVersion(
          currentVersion: '1.8.1',
          fromVersion: '1.7.5',
          targetVersion: '1.8.0',
        ),
        isFalse,
      );
    });
  });
}
