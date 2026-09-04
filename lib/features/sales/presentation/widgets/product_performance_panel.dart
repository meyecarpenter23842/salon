import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/repository_providers.dart';
import '../../../../core/repositories/catalog_detail_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/premium_workspace.dart';

final productDetailRepositoryProvider = Provider<ProductDetailRepository?>((ref) {
  final repository = ref.watch(retailProductsRepositoryProvider);
  return repository is ProductDetailRepository
      ? repository as ProductDetailRepository
      : null;
});

final productDetailProvider = FutureProvider.autoDispose
    .family<Map<String, Object?>?, String>((ref, productId) async {
  final repository = ref.watch(productDetailRepositoryProvider);
  if (repository == null) return null;
  return repository.fetchProductDetail(productId);
});

class ProductPerformancePanel extends ConsumerWidget {
  const ProductPerformancePanel({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(productDetailProvider(productId));
    return Container(
      key: const Key('product-detail-performance'),
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.featureSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: state.when(
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: LinearProgressIndicator(minHeight: 2),
        ),
        error: (error, _) => _DetailMessage(
          icon: Icons.error_outline_rounded,
          title: 'Không tải được hiệu suất sản phẩm',
          message: '$error',
          onRetry: () => ref.invalidate(productDetailProvider(productId)),
        ),
        data: (detail) {
          if (detail == null) {
            return const _DetailMessage(
              icon: Icons.query_stats_outlined,
              title: 'Hiệu suất giao dịch',
              message: 'Backend demo không có lịch sử giao dịch thật cho sản phẩm.',
            );
          }
          return _ProductPerformanceBody(detail: detail);
        },
      ),
    );
  }
}

class _ProductPerformanceBody extends StatelessWidget {
  const _ProductPerformanceBody({required this.detail});

  final Map<String, Object?> detail;

  @override
  Widget build(BuildContext context) {
    final history = _mapList(detail['history']).take(6).toList(growable: false);
    final metrics = [
      ('Doanh thu dòng', detail['monthRevenue']?.toString() ?? '0đ'),
      ('SL bán tháng', '${_toInt(detail['monthQuantity'])}'),
      ('Khách tháng', '${_toInt(detail['monthCustomerCount'])}'),
      ('CK dòng', detail['monthLineDiscount']?.toString() ?? '0đ'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Hiệu suất tháng này',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            PremiumStatusPill(label: 'Dữ liệu thật', tone: AppColors.success),
          ],
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            const gap = 8.0;
            final width = (constraints.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final metric in metrics)
                  SizedBox(
                    width: width,
                    child: _MetricTile(label: metric.$1, value: metric.$2),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        const PremiumDivider(),
        const SizedBox(height: 10),
        Text(
          'Lịch sử bán gần đây',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        if (history.isEmpty)
          Text(
            'Chưa có sản phẩm đã thanh toán.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          )
        else
          for (var index = 0; index < history.length; index++) ...[
            _HistoryRow(row: history[index]),
            if (index < history.length - 1) const SizedBox(height: 6),
          ],
        const SizedBox(height: 10),
        Text(
          detail['dataNote']?.toString() ?? '',
          style: TextStyle(color: AppColors.textMuted, fontSize: 9.5, height: 1.35),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: AppColors.textMuted, fontSize: 9.5)),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.row});

  final Map<String, Object?> row;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['dateLabel']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10),
                ),
                Text(
                  row['timeLabel']?.toString() ?? '',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 9),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row['customerName']?.toString() ?? 'Khách',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10.5),
                ),
                Text(
                  'x${_toInt(row['quantity'])} · giá ${row['unitPrice'] ?? '0đ'}${_toInt(row['discountValue']) > 0 ? ' · CK ${row['discount']}' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppColors.textMuted, fontSize: 9.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            row['total']?.toString() ?? '0đ',
            style: TextStyle(color: AppColors.copper, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _DetailMessage extends StatelessWidget {
  const _DetailMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppColors.textMuted, size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(message, style: TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
            ],
          ),
        ),
        if (onRetry != null)
          IconButton(
            tooltip: 'Thử lại',
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
          ),
      ],
    );
  }
}

List<Map<String, Object?>> _mapList(Object? raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
      .toList(growable: false);
}

int _toInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
