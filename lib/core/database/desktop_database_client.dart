import 'database_bootstrap.dart';
import 'database_client.dart';
import 'salon_database.dart';

class DesktopDatabaseClient implements DatabaseClient {
  bool _initialized = false;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    await DatabaseBootstrap.ensureInitialized();
    await SalonDatabase.instance.initialize();
    _initialized = true;
  }

  @override
  Future<void> close() async {
    await SalonDatabase.instance.close();
    _initialized = false;
  }
}
