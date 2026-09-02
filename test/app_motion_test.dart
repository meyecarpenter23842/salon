import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/theme/app_motion.dart';
import 'package:salonmanager/shared/widgets/app_motion.dart';

void main() {
  testWidgets('motion policy uses shared durations when animations are enabled', (
    WidgetTester tester,
  ) async {
    late Duration resolvedDuration;
    late AnimationStyle dialogStyle;
    late AnimationStyle sheetStyle;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            resolvedDuration = AppMotion.duration(context, AppMotion.standard);
            dialogStyle = AppMotion.dialogStyle(context);
            sheetStyle = AppMotion.sheetStyle(context);
            return const AppMotionSwitcher(child: Text('motion'));
          },
        ),
      ),
    );

    expect(resolvedDuration, AppMotion.standard);
    expect(dialogStyle.duration, AppMotion.standard);
    expect(dialogStyle.reverseDuration, AppMotion.quick);
    expect(sheetStyle.duration, AppMotion.moderate);
    expect(sheetStyle.reverseDuration, AppMotion.standard);
    expect(find.byType(AnimatedSwitcher), findsOneWidget);
  });

  testWidgets('motion policy removes nonessential motion when requested', (
    WidgetTester tester,
  ) async {
    late Duration resolvedDuration;
    late AnimationStyle dialogStyle;
    late AnimationStyle sheetStyle;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              resolvedDuration = AppMotion.duration(context, AppMotion.standard);
              dialogStyle = AppMotion.dialogStyle(context);
              sheetStyle = AppMotion.sheetStyle(context);
              return const AppMotionSwitcher(child: Text('reduced motion'));
            },
          ),
        ),
      ),
    );

    expect(resolvedDuration, Duration.zero);
    expect(dialogStyle.duration, Duration.zero);
    expect(dialogStyle.reverseDuration, Duration.zero);
    expect(sheetStyle.duration, Duration.zero);
    expect(sheetStyle.reverseDuration, Duration.zero);
    expect(find.byType(AnimatedSwitcher), findsNothing);
    expect(find.text('reduced motion'), findsOneWidget);
  });
}
