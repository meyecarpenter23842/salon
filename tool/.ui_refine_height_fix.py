from pathlib import Path

# Temporary validation helper; final branch will keep only generated source/test changes.
path = Path('lib/features/employees/presentation/pages/employees_page.dart')
text = path.read_text()

def replace_block(source: str, start_marker: str, end_marker: str, replacement: str) -> str:
    start = source.index(start_marker)
    end = source.index(end_marker, start)
    return source[:start] + replacement + source[end:]

next_card = r'''  Widget _nextAppointmentCard(
    BuildContext context,
    Map<String, Object?>? next,
    List<Map<String, Object?>> appointments,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 96;
        if (compact) {
          final summary = next == null
              ? (profile['nextAppointmentLabel']?.toString() ??
                    'Chưa có lịch sắp tới')
              : '${next['timeRange']?.toString() ?? ''} · ${next['customerName']?.toString() ?? 'Khách'} · ${next['serviceName']?.toString() ?? 'Dịch vụ'}';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.featureSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.event_available_outlined,
                  size: 16,
                  color: AppColors.copper,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Lịch tiếp theo · $summary',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                    ),
                  ),
                ),
                if (appointments.isNotEmpty)
                  IconButton(
                    tooltip: 'Xem lịch',
                    onPressed: () => _showAppointments(context, appointments),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    icon: const Icon(Icons.open_in_new_rounded, size: 15),
                  ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.featureSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.event_available_outlined,
                    size: 18,
                    color: AppColors.copper,
                  ),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'Lịch tiếp theo',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  TextButton(
                    onPressed: appointments.isEmpty
                        ? null
                        : () => _showAppointments(context, appointments),
                    child: const Text('Xem lịch'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (next == null)
                Text(
                  profile['nextAppointmentLabel']?.toString() ??
                      'Chưa có lịch sắp tới.',
                  style: TextStyle(color: AppColors.textMuted),
                )
              else ...[
                Text(
                  next['timeRange']?.toString() ?? '',
                  style: TextStyle(
                    color: AppColors.copper,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  next['customerName']?.toString() ?? 'Khách',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  next['serviceName']?.toString() ?? 'Dịch vụ',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(height: 7),
                Align(
                  alignment: Alignment.centerLeft,
                  child: PremiumStatusPill(
                    label: next['status']?.toString() ?? '',
                    tone: _appointmentStatusTone(
                      next['status']?.toString() ?? '',
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

'''

top_services = r'''  Widget _topServicesCard(List<Map<String, Object?>> services) {
    final rows = services.take(3).toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 96;
        if (compact) {
          final summary = rows.isEmpty
              ? 'Chưa có dữ liệu'
              : '${rows.first['title']?.toString() ?? 'Dịch vụ'} · ${_intValue(rows.first['quantity'])} lượt';
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.featureSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.content_cut_rounded,
                  size: 16,
                  color: AppColors.copper,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Top dịch vụ · $summary',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 10.5,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.featureSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.content_cut_rounded,
                    size: 18,
                    color: AppColors.copper,
                  ),
                  const SizedBox(width: 7),
                  const Expanded(
                    child: Text(
                      'Top dịch vụ tháng này',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                Text(
                  'Chưa có dữ liệu dịch vụ.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10.5),
                )
              else
                for (var index = 0; index < rows.length; index++) ...[
                  Row(
                    children: [
                      SizedBox(
                        width: 24,
                        child: Text(
                          '${index + 1}.',
                          style: TextStyle(
                            color: AppColors.copper,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          rows[index]['title']?.toString() ?? 'Dịch vụ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${_intValue(rows[index]['quantity'])} lượt',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                  if (index < rows.length - 1) const SizedBox(height: 6),
                ],
            ],
          ),
        );
      },
    );
  }

'''

text = replace_block(text, '  Widget _nextAppointmentCard(', '  Widget _topServicesCard(', next_card)
text = replace_block(text, '  Widget _topServicesCard(', '  Widget _historyCard(', top_services)
path.write_text(text)
