import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/database/salon_database.dart';
import 'package:salonmanager/core/models/catalog_option.dart';
import 'package:salonmanager/core/models/service_upsert_input.dart';
import 'package:salonmanager/core/repositories/catalog_options_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await SalonDatabase.instance.close();
  });

  tearDown(() async {
    await SalonDatabase.instance.close();
  });

  test('catalog options keep defaults and persist custom names without duplicates', () async {
    final repository = SqliteCatalogOptionsRepository(SalonDatabase.instance);

    final productGroups = await repository.fetchOptionNames(
      CatalogOptionKind.productGroup,
    );
    final serviceGroups = await repository.fetchOptionNames(
      CatalogOptionKind.serviceGroup,
    );
    final brands = await repository.fetchOptionNames(
      CatalogOptionKind.productBrand,
    );

    expect(productGroups, contains('Gội'));
    expect(serviceGroups, contains('Chăm sóc'));
    expect(brands, isEmpty);

    final brand = await repository.createOption(
      CatalogOptionKind.productBrand,
      "  L'Oréal  ",
    );
    final duplicateBrand = await repository.createOption(
      CatalogOptionKind.productBrand,
      "l'oréal",
    );
    final productGroup = await repository.createOption(
      CatalogOptionKind.productGroup,
      'Màu nhuộm chuyên nghiệp',
    );
    final serviceGroup = await repository.createOption(
      CatalogOptionKind.serviceGroup,
      'Phục hồi chuyên sâu',
    );

    expect(brand, "L'Oréal");
    expect(duplicateBrand, "L'Oréal");
    expect(productGroup, 'Màu nhuộm chuyên nghiệp');
    expect(serviceGroup, 'Phục hồi chuyên sâu');

    expect(
      await repository.fetchOptionNames(CatalogOptionKind.productBrand),
      ["L'Oréal"],
    );
    expect(
      await repository.fetchOptionNames(CatalogOptionKind.productGroup),
      contains('Màu nhuộm chuyên nghiệp'),
    );
    expect(
      await repository.fetchOptionNames(CatalogOptionKind.serviceGroup),
      contains('Phục hồi chuyên sâu'),
    );

    final database = await SalonDatabase.instance.database;
    final rows = await database.rawQuery(
      'SELECT kind, name FROM catalog_options ORDER BY kind, name',
    );
    expect(rows, hasLength(3));
  });

  test('custom service group survives service input normalization', () {
    final input = ServiceUpsertInput.normalized(
      name: 'Ủ phục hồi',
      category: 'Phục hồi chuyên sâu',
      durationMinutes: 60,
      price: 350000,
      description: 'Dịch vụ phục hồi tóc',
      isActive: true,
      popularityLabel: 'Ổn định',
    );

    expect(input.category, 'Phục hồi chuyên sâu');
  });
}
