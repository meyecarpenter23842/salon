part of 'invoices_pos_page.dart';

Future<void> _catalogMutationQueue = Future<void>.value();

Future<void> _queueCatalogMutation(Future<void> Function() operation) {
  final next = _catalogMutationQueue.then((_) => operation());
  _catalogMutationQueue = next.then<void>(
    (_) {},
    onError: (Object _, StackTrace _) {},
  );
  return next;
}

class _CatalogPanel extends ConsumerStatefulWidget {
  const _CatalogPanel({
    required this.draft,
    required this.servicesState,
    required this.productsState,
    required this.dense,
  });

  final InvoiceDraft draft;
  final AsyncValue<List<ServiceCatalogItem>> servicesState;
  final AsyncValue<List<RetailProductItem>> productsState;
  final bool dense;

  @override
  ConsumerState<_CatalogPanel> createState() => _CatalogPanelState();
}

class _CatalogPanelState extends ConsumerState<_CatalogPanel> {
  late final TextEditingController _queryController;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(
      text: ref.read(_invoiceCatalogQueryProvider),
    );
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;
    final dense = widget.dense;
    final kind = ref.watch(_invoiceCatalogKindProvider);
    final query = ref.watch(_invoiceCatalogQueryProvider).trim().toLowerCase();

    return PremiumSectionCard(
      key: const Key('billing-pos-catalog'),
      icon: Icons.grid_view_rounded,
      title: 'Dịch vụ / Sản phẩm',
      subtitle: draft.isPaid ? 'Bill đã khóa' : 'Chạm một lần để thêm vào bill',
      padding: EdgeInsets.all(dense ? 12 : 14),
      trailing: kind == _PosCatalogKind.products && !draft.isPaid
          ? IconButton(
              tooltip: 'Tạo sản phẩm bán lẻ',
              onPressed: () => _createProductAndAdd(context, ref),
              icon: const Icon(Icons.add_box_outlined, size: 19),
            )
          : null,
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<_PosCatalogKind>(
              segments: const [
                ButtonSegment(
                  value: _PosCatalogKind.services,
                  icon: Icon(Icons.content_cut_rounded, size: 16),
                  label: Text('Dịch vụ'),
                ),
                ButtonSegment(
                  value: _PosCatalogKind.products,
                  icon: Icon(Icons.shopping_bag_outlined, size: 16),
                  label: Text('Sản phẩm'),
                ),
              ],
              selected: {kind},
              showSelectedIcon: false,
              onSelectionChanged: (value) {
                ref.read(_invoiceCatalogKindProvider.notifier).state = value.first;
                _queryController.clear();
                ref.read(_invoiceCatalogQueryProvider.notifier).state = '';
              },
              style: ButtonStyle(
                visualDensity:
                    dense ? VisualDensity.compact : VisualDensity.standard,
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _queryController,
            onChanged: (value) =>
                ref.read(_invoiceCatalogQueryProvider.notifier).state = value,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              hintText: kind == _PosCatalogKind.services
                  ? 'Tìm dịch vụ…'
                  : 'Tìm sản phẩm…',
              isDense: true,
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Xóa tìm kiếm',
                      onPressed: () {
                        _queryController.clear();
                        ref.read(_invoiceCatalogQueryProvider.notifier).state = '';
                      },
                      icon: const Icon(Icons.close_rounded, size: 17),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: kind == _PosCatalogKind.services
                ? _ServiceCatalogList(
                    draft: draft,
                    state: widget.servicesState,
                    query: query,
                  )
                : _ProductCatalogList(
                    draft: draft,
                    state: widget.productsState,
                    query: query,
                  ),
          ),
        ],
      ),
    );
  }
}

class _ServiceCatalogList extends ConsumerWidget {
  const _ServiceCatalogList({
    required this.draft,
    required this.state,
    required this.query,
  });

  final InvoiceDraft draft;
  final AsyncValue<List<ServiceCatalogItem>> state;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return state.when(
      data: (services) {
        final visible = services.where((service) {
          if (!service.isActive) return false;
          if (query.isEmpty) return true;
          return service.name.toLowerCase().contains(query) ||
              service.category.toLowerCase().contains(query);
        }).toList(growable: false);

        if (visible.isEmpty) {
          return const PremiumEmptyState(
            icon: Icons.content_cut_rounded,
            title: 'Không có dịch vụ phù hợp',
            message: 'Thử từ khóa khác hoặc kiểm tra danh mục dịch vụ.',
          );
        }

        return ListView.separated(
          primary: false,
          itemCount: visible.length,
          separatorBuilder: (_, _) => const PremiumDivider(indent: 38),
          itemBuilder: (context, index) {
            final service = visible[index];
            final quantity = _serviceQuantityInDraft(draft, service.id);
            return _CatalogItemRow(
              icon: Icons.content_cut_rounded,
              title: service.name,
              meta: '${service.category} · ${service.durationLabel}',
              price: service.priceLabel,
              quantityInBill: quantity,
              locked: draft.isPaid,
              tooltip: draft.isPaid
                  ? 'Hóa đơn đã khóa'
                  : 'Thêm ${service.name} vào bill',
              onTap: draft.isPaid
                  ? null
                  : () => _queueCatalogMutation(
                        () => _addInvoiceService(context, ref, service),
                      ),
            );
          },
        );
      },
      loading: () => const PremiumLoadingState(label: 'Đang tải dịch vụ…'),
      error: (error, _) => PremiumErrorState(
        title: 'Không tải được dịch vụ',
        message: '$error',
        onRetry: () => ref.invalidate(servicesViewProvider),
      ),
    );
  }
}

class _ProductCatalogList extends ConsumerWidget {
  const _ProductCatalogList({
    required this.draft,
    required this.state,
    required this.query,
  });

  final InvoiceDraft draft;
  final AsyncValue<List<RetailProductItem>> state;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return state.when(
      data: (products) {
        final visible = products.where((product) {
          if (!product.isActive) return false;
          if (query.isEmpty) return true;
          return product.name.toLowerCase().contains(query) ||
              product.brand.toLowerCase().contains(query) ||
              product.productType.toLowerCase().contains(query);
        }).toList(growable: false);

        if (visible.isEmpty) {
          return PremiumEmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'Không có sản phẩm phù hợp',
            message: query.isEmpty
                ? 'Tạo sản phẩm bán lẻ để bắt đầu.'
                : 'Thử từ khóa khác.',
          );
        }

        return ListView.separated(
          primary: false,
          itemCount: visible.length,
          separatorBuilder: (_, _) => const PremiumDivider(indent: 38),
          itemBuilder: (context, index) {
            final product = visible[index];
            final quantity = _productQuantityInDraft(draft, product.id);
            final metaParts = <String>[
              product.productType,
              if (product.brand.isNotEmpty) product.brand,
              if (product.volumeLabel.isNotEmpty) product.volumeLabel,
            ];
            return _CatalogItemRow(
              icon: Icons.shopping_bag_outlined,
              title: product.name,
              meta: metaParts.join(' · '),
              price: product.salePriceLabel,
              quantityInBill: quantity,
              locked: draft.isPaid,
              tone: AppColors.info,
              tooltip: draft.isPaid
                  ? 'Hóa đơn đã khóa'
                  : 'Thêm ${product.name} vào bill',
              onTap: draft.isPaid
                  ? null
                  : () => _queueCatalogMutation(
                        () => _addInvoiceProduct(context, ref, product),
                      ),
            );
          },
        );
      },
      loading: () => const PremiumLoadingState(label: 'Đang tải sản phẩm…'),
      error: (error, _) => PremiumErrorState(
        title: 'Không tải được sản phẩm',
        message: '$error',
        onRetry: () => ref.invalidate(retailProductsViewProvider),
      ),
    );
  }
}

class _CatalogItemRow extends StatelessWidget {
  const _CatalogItemRow({
    required this.icon,
    required this.title,
    required this.meta,
    required this.price,
    required this.quantityInBill,
    required this.locked,
    required this.tooltip,
    this.tone,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String meta;
  final String price;
  final int quantityInBill;
  final bool locked;
  final String tooltip;
  final Color? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = PremiumInteractiveSurface(
      selected: quantityInBill > 0,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Row(
        children: [
          PremiumIconBadge(icon: icon, size: 31, tone: tone),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 9.8, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                price,
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.copper,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              if (quantityInBill > 0)
                Text(
                  'Trong bill ×$quantityInBill',
                  style: TextStyle(
                    fontSize: 9.5,
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                  ),
                )
              else
                Icon(
                  locked
                      ? Icons.lock_outline_rounded
                      : Icons.add_circle_outline_rounded,
                  size: 16,
                  color: AppColors.textMuted,
                ),
            ],
          ),
        ],
      ),
    );

    return Tooltip(message: tooltip, child: row);
  }
}

int _serviceQuantityInDraft(InvoiceDraft draft, String serviceId) {
  var quantity = 0;
  for (final line in draft.lines) {
    if (line.serviceId == serviceId) quantity += line.quantity;
  }
  return quantity;
}

int _productQuantityInDraft(InvoiceDraft draft, String productId) {
  var quantity = 0;
  for (final line in draft.lines) {
    if (line.productId == productId) quantity += line.quantity;
  }
  return quantity;
}
