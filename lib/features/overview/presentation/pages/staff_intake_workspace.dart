import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../appointments/presentation/pages/appointments_page.dart';
import 'staff_window_workspace.dart';

class StaffIntakeWorkspace extends ConsumerWidget {
  const StaffIntakeWorkspace({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Container(
          key: const Key('staff-intake-bar'),
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.workspaceTopBarSurface,
            border: Border(
              bottom: BorderSide(color: AppColors.workspaceDivider),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                key: const Key('staff-add-appointment'),
                onPressed: () => openAppointmentEditor(context, ref),
                icon: const Icon(Icons.event_available_outlined, size: 18),
                label: const Text('Thêm lịch'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                key: const Key('staff-receive-customer'),
                onPressed: () {
                  final now = DateTime.now();
                  openAppointmentEditor(
                    context,
                    ref,
                    initialDayLabel: 'Hôm nay',
                    initialTimeLabel: DateFormat('HH:mm').format(now),
                  );
                },
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('Nhận khách'),
              ),
            ],
          ),
        ),
        const Expanded(child: StaffWindowWorkspace()),
      ],
    );
  }
}
