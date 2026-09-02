import 'package:flutter/material.dart';

abstract final class AppMotion {
  static const Duration quick = Duration(milliseconds: 140);
  static const Duration standard = Duration(milliseconds: 180);
  static const Duration moderate = Duration(milliseconds: 220);

  static const Curve standardCurve = Curves.easeOutCubic;
  static const Curve exitCurve = Curves.easeInCubic;

  static bool reduceMotion(BuildContext context) {
    return MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  static Duration duration(BuildContext context, Duration preferred) {
    return reduceMotion(context) ? Duration.zero : preferred;
  }

  static AnimationStyle dialogStyle(BuildContext context) {
    if (reduceMotion(context)) return AnimationStyle.noAnimation;
    return const AnimationStyle(
      duration: standard,
      reverseDuration: quick,
      curve: standardCurve,
      reverseCurve: exitCurve,
    );
  }

  static AnimationStyle sheetStyle(BuildContext context) {
    if (reduceMotion(context)) return AnimationStyle.noAnimation;
    return const AnimationStyle(
      duration: moderate,
      reverseDuration: standard,
      curve: standardCurve,
      reverseCurve: exitCurve,
    );
  }
}
