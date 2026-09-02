import 'package:sqflite/sqflite.dart';

/// Legacy compatibility shim for the SQLite repositories.
///
/// Production SQLite must never populate business tables from demo/fake data.
/// Fake data belongs to the explicit fake backend used by tests/demo only.
/// The methods remain temporarily so DB-1 can remove production seeding without
/// mixing a broad repository-constructor refactor into the same batch.
class SalonDatabaseSeed {
  const SalonDatabaseSeed([Object? _]);

  Future<void> seedCustomersIfNeeded(Database _) async {}

  Future<void> seedEmployeesIfNeeded(Database _) async {}

  Future<void> seedAppointmentsIfNeeded(Database _) async {}

  Future<void> seedServicesIfNeeded(Database _) async {}

  Future<void> seedInvoiceDraftIfNeeded(Database _) async {}
}
