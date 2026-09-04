import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:salonmanager/core/repositories/catalog_detail_repository.dart';
import 'package:salonmanager/features/sales/presentation/widgets/product_performance_panel.dart';
import 'package:salonmanager/features/services/presentation/widgets/service_performance_panel.dart';

void main() {
  testWidgets('service detail refetches after leaving and returning', (tester) async {
    final repository = _RecordingServiceDetailRepository();
    final container = ProviderContainer(
      overrides: [
        serviceDetailRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await _pumpWithContainer(
      tester,
      container,
      const ServicePerformancePanel(serviceId: 'service-1'),
    );
    expect(repository.calls, 1);

    await _pumpWithContainer(tester, container, const SizedBox.shrink());
    await tester.pump();

    await _pumpWithContainer(
      tester,
      container,
      const ServicePerformancePanel(serviceId: 'service-1'),
    );
    expect(repository.calls, 2);
  });

  testWidgets('product detail refetches after leaving and returning', (tester) async {
    final repository = _RecordingProductDetailRepository();
    final container = ProviderContainer(
      overrides: [
        productDetailRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await _pumpWithContainer(
      tester,
      container,
      const ProductPerformancePanel(productId: 'product-1'),
    );
    expect(repository.calls, 1);

    await _pumpWithContainer(tester, container, const SizedBox.shrink());
    await tester.pump();

    await _pumpWithContainer(
      tester,
      container,
      const ProductPerformancePanel(productId: 'product-1'),
    );
    expect(repository.calls, 2);
  });
}

Future<void> _pumpWithContainer(
  WidgetTester tester,
  ProviderContainer container,
  Widget child,
) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 520, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

class _RecordingServiceDetailRepository implements ServiceDetailRepository {
  int calls = 0;

  @override
  Future<Map<String, Object?>> fetchServiceDetail(String serviceId) async {
    calls++;
    return {
      'monthRevenue': '0đ',
      'monthQuantity': 0,
      'monthCustomerCount': 0,
      'monthLineDiscount': '0đ',
      'topStaff': <Map<String, Object?>>[],
      'history': <Map<String, Object?>>[],
      'dataNote': '',
    };
  }
}

class _RecordingProductDetailRepository implements ProductDetailRepository {
  int calls = 0;

  @override
  Future<Map<String, Object?>> fetchProductDetail(String productId) async {
    calls++;
    return {
      'monthRevenue': '0đ',
      'monthQuantity': 0,
      'monthCustomerCount': 0,
      'monthLineDiscount': '0đ',
      'history': <Map<String, Object?>>[],
      'dataNote': '',
    };
  }
}
