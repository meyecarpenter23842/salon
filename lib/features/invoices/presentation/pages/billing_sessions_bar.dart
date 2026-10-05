part of 'invoices_pos_page.dart';

class _BillingSessionsBar extends ConsumerStatefulWidget {
  const _BillingSessionsBar({required this.draft, required this.customers});

  final InvoiceDraft draft;
  final List<CustomerProfile> customers;

  @override
  ConsumerState<_BillingSessionsBar> createState() => _BillingSessionsBarState();
}

class _BillingSessionsBarState extends ConsumerState<_BillingSessionsBar> {
  bool _changing = false;

  Future<void> _changeSession(String? sessionId) async {
    if (_changing || sessionId == null) return;
    setState(() => _changing = true);
    try {
      // Finish queued additions against their original bill before switching.
      await _catalogMutationQueue;
      if (!mounted) return;
      ref.read(selectedInvoiceSessionIdProvider.notifier).state = sessionId;
      ref.invalidate(invoiceDraftProvider);
  ref.invalidate(activeInvoiceSessionsProvider);
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  Future<void> _createWalkIn() async {
    if (_changing) return;
    setState(() => _changing = true);
    try {
      await _catalogMutationQueue;
      if (!mounted) return;
      final draft = await ref.read(billingSessionsRepositoryProvider)
          .createWalkInSession();
      if (!mounted) return;
      ref.read(selectedInvoiceSessionIdProvider.notifier).state = draft.id;
      ref.invalidate(invoiceDraftProvider);
      ref.invalidate(activeInvoiceSessionsProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không tạo được bill: ${_friendlyCheckoutError(error)}')),
      );
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  String _label(InvoiceDraft draft, int index) {
    String name = draft.id == SqliteInvoicesRepository.legacyDraftInvoiceId
        ? 'Bill ban đầu'
        : 'Khách vãng lai';
    for (final customer in widget.customers) {
      if (customer.id == draft.customerId) {
        name = customer.fullName;
        break;
      }
    }
    final kind = draft.appointmentId == null ? 'Tại quầy' : 'Lịch hẹn';
    return '${index + 1}. $name · $kind · ${_currency(draft.totalAmount)}';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(activeInvoiceSessionsProvider);
    final busy = _changing || ref.watch(_invoiceCheckoutBusyProvider);
    final drafts = {
      for (final draft in state.valueOrNull ?? <InvoiceDraft>[]) draft.id: draft,
      widget.draft.id: widget.draft,
    }.values.toList(growable: false);

    return SizedBox(
      key: const Key('billing-sessions-bar'),
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey('billing-session-selector-${widget.draft.id}'),
              initialValue: widget.draft.id,
              isExpanded: true,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                prefixIcon: Icon(Icons.receipt_long_outlined, size: 18),
                border: OutlineInputBorder(),
              ),
              items: [
                for (var i = 0; i < drafts.length; i++)
                  DropdownMenuItem(
                    value: drafts[i].id,
                    child: Text(
                      _label(drafts[i], i),
                      key: ValueKey('billing-session-choice-${drafts[i].id}'),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
              ],
              onChanged: busy ? null : _changeSession,
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            key: const Key('billing-new-walkin'),
            onPressed: busy ? null : _createWalkIn,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Bill mới'),
          ),
          IconButton(
            key: const Key('billing-refresh-sessions'),
            tooltip: state.hasError ? 'Tải lại danh sách bill bị lỗi' : 'Tải lại bill đang mở',
            onPressed: busy ? null : () => ref.invalidate(activeInvoiceSessionsProvider),
            icon: Icon(state.hasError ? Icons.error_outline : Icons.refresh, size: 18),
          ),
        ],
      ),
    );
  }
}
