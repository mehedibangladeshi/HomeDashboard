import 'package:flutter/material.dart';

// Callers with controllers outside a route must wait until its closing
// animation has removed all dependent fields before disposing controllers.
Future<T?> showManagedDialog<T>(
    {required BuildContext context, required WidgetBuilder builder}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<T>(context: context, builder: builder);
  final value = await navigator.push(route);
  await route.completed;
  return value;
}

Future<T?> showManagedBottomSheet<T>(
    {required BuildContext context,
    required WidgetBuilder builder,
    bool isScrollControlled = true,
    bool showDragHandle = true}) async {
  final navigator = Navigator.of(context);
  final route = ModalBottomSheetRoute<T>(
      builder: builder,
      isScrollControlled: isScrollControlled,
      showDragHandle: showDragHandle,
      capturedThemes:
          InheritedTheme.capture(from: context, to: navigator.context));
  final value = await navigator.push(route);
  await route.completed;
  return value;
}
