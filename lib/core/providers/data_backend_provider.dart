import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppDataBackend { sqlite, fake }

final appDataBackendProvider = Provider<AppDataBackend>(
  (ref) => AppDataBackend.sqlite,
);
