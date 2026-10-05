import 'dart:io';

import 'package:flutter/material.dart';

import 'desktop_main.dart' deferred as desktop;
import 'features/companion/companion_app.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    runApp(const SalonCompanionApp());
    return;
  }
  await desktop.loadLibrary();
  await desktop.runDesktop(args);
}
