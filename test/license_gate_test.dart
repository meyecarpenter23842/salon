import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/license/license_coordinator.dart';
import 'package:salonmanager/core/license/license_gate.dart';
import 'package:salonmanager/core/license/license_models.dart';

void main() {
  testWidgets('unlicensed staff launch cannot bypass the shared gate', (
    tester,
  ) async {
    final controller = _FakeGateController(
      checkResult: const LicenseGateResult(
        status: LicenseAccessStatus.activationRequired,
      ),
    );

    await tester.pumpWidget(
      LicenseGate(
        controller: controller,
        launchStaffWindow: true,
        mainAppBuilder: (_) => const MaterialApp(home: Text('MAIN_APP')),
        staffAppBuilder: (_) => const MaterialApp(home: Text('STAFF_APP')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('license-key-field')), findsOneWidget);
    expect(find.text('STAFF_APP'), findsNothing);
    expect(find.text('MAIN_APP'), findsNothing);
    expect(controller.checkCalls, 1);
  });

  testWidgets('licensed staff launch opens staff app only after validation', (
    tester,
  ) async {
    final controller = _FakeGateController(
      checkResult: const LicenseGateResult(
        status: LicenseAccessStatus.allowedOnline,
      ),
    );

    await tester.pumpWidget(
      LicenseGate(
        controller: controller,
        launchStaffWindow: true,
        mainAppBuilder: (_) => const MaterialApp(home: Text('MAIN_APP')),
        staffAppBuilder: (_) => const MaterialApp(home: Text('STAFF_APP')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('STAFF_APP'), findsOneWidget);
    expect(find.text('MAIN_APP'), findsNothing);
    expect(find.byKey(const Key('license-key-field')), findsNothing);
  });

  testWidgets('licensed main launch opens main app without key prompt', (
    tester,
  ) async {
    final controller = _FakeGateController(
      checkResult: const LicenseGateResult(
        status: LicenseAccessStatus.allowedOnline,
      ),
    );

    await tester.pumpWidget(
      LicenseGate(
        controller: controller,
        launchStaffWindow: false,
        mainAppBuilder: (_) => const MaterialApp(home: Text('MAIN_APP')),
        staffAppBuilder: (_) => const MaterialApp(home: Text('STAFF_APP')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MAIN_APP'), findsOneWidget);
    expect(find.text('STAFF_APP'), findsNothing);
    expect(find.byKey(const Key('license-key-field')), findsNothing);
  });
}

class _FakeGateController implements LicenseGateController {
  _FakeGateController({required this.checkResult});

  final LicenseGateResult checkResult;
  int checkCalls = 0;

  @override
  Future<LicenseGateResult> check() async {
    checkCalls += 1;
    return checkResult;
  }

  @override
  Future<LicenseGateResult> activate(String licenseKey) async {
    return const LicenseGateResult(
      status: LicenseAccessStatus.allowedOnline,
    );
  }
}
