import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/license/license_models.dart';
import 'package:salonmanager/features/settings/presentation/pages/license_status_panel.dart';

void main() {
  testWidgets('license dialog shows useful metadata without exposing full key', (
    tester,
  ) async {
    final state = StoredLicenseState(
      licenseKey: 'SALON-VERY-SECRET-ABCD',
      licenseId: 'license-1',
      applicationId: 'app-salon',
      deviceId: 'device-1234567890',
      licenseType: 'SUBSCRIPTION',
      licenseExpiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
      maxDevices: 3,
      deviceName: 'Salon PC',
      deviceActivatedAt: DateTime.utc(2026, 9, 1, 8),
      serverTimeAtSync: DateTime.utc(2026, 9, 10, 12),
      wallClockAtSync: DateTime.utc(2026, 9, 10, 12),
      trustedHighWater: DateTime.utc(2026, 9, 10, 12),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showLicenseStatusDialog(
                  context,
                  loader: () async => state,
                ),
                child: const Text('Mở bản quyền'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Mở bản quyền'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Bản quyền & thiết bị'), findsOneWidget);
    expect(find.text('Salon đã được kích hoạt'), findsOneWidget);
    expect(find.text('Theo thời hạn'), findsOneWidget);
    expect(find.text('Tối đa 3 thiết bị'), findsOneWidget);
    expect(find.text('Salon PC'), findsOneWidget);
    expect(find.text('•••• •••• ABCD'), findsOneWidget);
    expect(find.text('SALON-VERY-SECRET-ABCD'), findsNothing);
  });
}
