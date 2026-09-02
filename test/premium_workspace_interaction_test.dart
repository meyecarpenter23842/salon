import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/theme/app_motion.dart';
import 'package:salonmanager/shared/widgets/premium_workspace.dart';

void main() {
  testWidgets('workspace surface uses shared motion and handles taps', (
    WidgetTester tester,
  ) async {
    var taps = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: PremiumInteractiveSurface(
            selected: true,
            onTap: () => taps++,
            child: const Text('row'),
          ),
        ),
      ),
    );

    final animatedFinder = find.descendant(
      of: find.byType(PremiumInteractiveSurface),
      matching: find.byType(AnimatedContainer),
    );
    final animated = tester.widget<AnimatedContainer>(animatedFinder);

    expect(animated.duration, AppMotion.quick);
    await tester.tap(find.text('row'));
    expect(taps, 1);
  });

  testWidgets('workspace interaction removes nonessential motion when requested', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Column(
            children: [
              PremiumInteractiveSurface(
                selected: false,
                onTap: null,
                child: Text('row'),
              ),
              PremiumAnimatedDetail(
                transitionKey: ValueKey('detail'),
                child: Text('detail'),
              ),
            ],
          ),
        ),
      ),
    );

    final animatedFinder = find.descendant(
      of: find.byType(PremiumInteractiveSurface),
      matching: find.byType(AnimatedContainer),
    );
    final animated = tester.widget<AnimatedContainer>(animatedFinder);

    expect(animated.duration, Duration.zero);
    expect(find.byType(AnimatedSwitcher), findsNothing);
    expect(find.text('detail'), findsOneWidget);
  });

  testWidgets('detail panel uses the shared switcher when motion is enabled', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: PremiumAnimatedDetail(
          transitionKey: ValueKey('detail'),
          child: Text('detail'),
        ),
      ),
    );

    expect(find.byType(AnimatedSwitcher), findsOneWidget);
    expect(find.text('detail'), findsOneWidget);
  });
}
