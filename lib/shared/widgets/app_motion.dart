import 'package:flutter/material.dart';

import '../../core/theme/app_motion.dart';

class AppMotionSwitcher extends StatelessWidget {
  const AppMotionSwitcher({
    super.key,
    required this.child,
    this.duration = AppMotion.standard,
    this.beginOffset = const Offset(0.012, 0),
  });

  final Widget child;
  final Duration duration;
  final Offset beginOffset;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.reduceMotion(context)) return child;

    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: AppMotion.quick,
      switchInCurve: AppMotion.standardCurve,
      switchOutCurve: AppMotion.exitCurve,
      transitionBuilder: (child, animation) {
        final fade = CurvedAnimation(
          parent: animation,
          curve: AppMotion.standardCurve,
          reverseCurve: AppMotion.exitCurve,
        );
        final slide = Tween<Offset>(
          begin: beginOffset,
          end: Offset.zero,
        ).animate(fade);
        return FadeTransition(
          opacity: fade,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: child,
    );
  }
}

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
  bool fullscreenDialog = false,
  bool? requestFocus,
}) {
  return showDialog<T>(
    context: context,
    builder: builder,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel,
    useSafeArea: useSafeArea,
    useRootNavigator: useRootNavigator,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    traversalEdgeBehavior: traversalEdgeBehavior,
    fullscreenDialog: fullscreenDialog,
    requestFocus: requestFocus,
    animationStyle: AppMotion.dialogStyle(context),
  );
}

Future<T?> showAppModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  String? barrierLabel,
  double? elevation,
  ShapeBorder? shape,
  Clip? clipBehavior,
  BoxConstraints? constraints,
  Color? barrierColor,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool? showDragHandle,
  bool useSafeArea = false,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  bool? requestFocus,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    backgroundColor: backgroundColor,
    barrierLabel: barrierLabel,
    elevation: elevation,
    shape: shape,
    clipBehavior: clipBehavior,
    constraints: constraints,
    barrierColor: barrierColor,
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    showDragHandle: showDragHandle,
    useSafeArea: useSafeArea,
    routeSettings: routeSettings,
    anchorPoint: anchorPoint,
    requestFocus: requestFocus,
    sheetAnimationStyle: AppMotion.sheetStyle(context),
  );
}
