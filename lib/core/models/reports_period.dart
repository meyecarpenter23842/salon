enum ReportsPeriod { today, last7Days, last30Days, thisMonth }

extension ReportsPeriodX on ReportsPeriod {
  String get label {
    switch (this) {
      case ReportsPeriod.today:
        return 'Hôm nay';
      case ReportsPeriod.last7Days:
        return '7 ngày';
      case ReportsPeriod.last30Days:
        return '30 ngày';
      case ReportsPeriod.thisMonth:
        return 'Tháng này';
    }
  }
}
