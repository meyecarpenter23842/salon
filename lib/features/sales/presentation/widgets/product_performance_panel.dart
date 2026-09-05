import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/repository_providers.dart';
import '../../../../core/repositories/catalog_detail_repository.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/premium_workspace.dart';

final productDetailRepositoryProvider = Provider<ProductDetailRepository?>((
  ref,
) {
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
      height: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
      decoration: BoxDecoration(
        color: AppColors.featureSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: state.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
              message:
                  'Backend demo không có lịch sử giao dịch thật cho sản phẩm.',
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
    final allHistory = _mapList(detail['history']);
    final history = allHistory.take(3).toList(growable: false);
    final metrics = [
      ('Doanh thu tháng', detail['monthRevenue']?.toString() ?? '0đ'),
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
        const SizedBox(height: 8),
        Row(
          children: [
            for (var index = 0; index < metrics.length; index++) ...[
              Expanded(
                child: _MetricInline(
                  label: metrics[index].$1,
                  value: metrics[index].$2,
                ),
              ),
              if (index < metrics.length - 1)
                Container(width: 1, height: 34, color: AppColors.cardBorder),
            ],
          ],
        ),
        const SizedBox(height: 8),
        const PremiumDivider(),
        const SizedBox(height: 5),
        Row(
          children: [
            Icon(Icons.history_rounded, size: 17, color: AppColors.copper),
            const SizedBox(width: 7),
            const Expanded(
              child: Text(
                'Bán gần đây',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            TextButton(
              onPressed: allHistory.isEmpty
                  ? null
                  : () => _showHistory(context, allHistory),
              child: Text('Xem tất cả (${allHistory.length})'),
            ),
          ],
        ),
        if (history.isEmpty)
          Text(
            'Chưa có sản phẩm đã thanh toán.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
          )
        else
          for (var index = 0; index < history.length; index++) ...[
            _HistoryRow(row: history[index]),
            if (index < history.length - 1) const PremiumDivider(),
          ],
        const Spacer(),
        Text(
          detail['dataNote']?.toString() ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: AppColors.textMuted, fontSize: 9),
        ),
      ],
    );
  }

  Future<void> _showHistory(
    BuildContext context,
    List<Map<String, Object?>> history,
  ) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lịch sử bán sản phẩm'),
        content: SizedBox(
          width: 760,
          height: 480,
          child: ListView.separated(
            itemCount: history.length,
            separatorBuilder: (_, _) => const PremiumDivider(),
            itemBuilder: (_, index) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: _HistoryRow(row: history[index]),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }
}

class _MetricInline extends StatelessWidget {
  const _MetricInline({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
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
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: AppColors.textMuted, fontSize: 9),
          ),
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
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              '${row['dateLabel'] ?? ''} ${row['timeLabel'] ?? ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.textMuted, fontSize: 9.5),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${row['customerName'] ?? 'Khách'} • x${_toInt(row['quantity'])}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            row['total']?.toString() ?? '0đ',
            style: TextStyle(
              color: AppColors.copper,
              fontWeight: FontWeight.w900,
            ),
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
              Text(
                message,
                style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
              ),
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
