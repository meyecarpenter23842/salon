class FakeSalonDataSource {
  const FakeSalonDataSource();

  Future<Map<String, Object?>> fetchOverviewSummary() async {
    return {
      'kpis': [
        {
          'title': 'Khách đặt lịch',
          'value': '18',
          'note': '12% so với hôm qua',
        },
        {'title': 'Khách đã làm', 'value': '12', 'note': '9% so với hôm qua'},
        {
          'title': 'Doanh thu hôm nay',
          'value': '8.250.000đ',
          'note': '15% so với hôm qua',
        },
        {
          'title': 'Lịch tiếp theo',
          'value': '14:30 - Chị Mai',
          'note': 'Phục hồi tóc',
        },
      ],
      'featuredCustomers': [
        {
          'initials': 'CL',
          'name': 'Chị Lan',
          'tier': 'VIP Gold',
          'service': 'Nhuộm nâu lạnh + phục hồi',
          'note': 'Đã quay lại 8 lần trong 60 ngày gần nhất.',
          'appointmentTime': '14:30 hôm nay',
          'spendLabel': '2.450.000đ tháng này',
        },
        {
          'initials': 'MH',
          'name': 'Chị Mai Hương',
          'tier': 'VIP Silver',
          'service': 'Uốn sóng lơi + phục hồi',
          'note': 'Ưu tiên stylist Hương và ghế gần cửa sổ.',
          'appointmentTime': '10:00 ngày mai',
          'spendLabel': '1.800.000đ tháng này',
        },
        {
          'initials': 'TA',
          'name': 'Anh Tuấn Anh',
          'tier': 'Member',
          'service': 'Cắt tóc layer',
          'note': 'Khách nam quay lại đều mỗi 3 tuần.',
          'appointmentTime': '17:00 thứ 6',
          'spendLabel': '650.000đ tháng này',
        },
      ],
      'quickCheckoutLines': [
        {
          'label': 'Nhuộm tóc',
          'qty': 1,
          'stylist': 'Hương',
          'amount': '1.200.000đ',
        },
        {
          'label': 'Phục hồi tóc',
          'qty': 1,
          'stylist': 'Linh',
          'amount': '500.000đ',
        },
        {
          'label': 'Gội đầu thư giãn',
          'qty': 1,
          'stylist': 'Nam',
          'amount': '150.000đ',
        },
      ],
      'quickCheckoutCustomer': 'Chị Lan',
      'quickCheckoutDiscount': '100.000đ',
      'quickCheckoutPaymentNote':
          'Khách chọn chuyển khoản, cần gửi hóa đơn Zalo.',
      'quickCheckoutTotal': '1.850.000đ',
      'revenueSeries': [
        {'label': 'Th 7', 'value': 5200000},
        {'label': 'CN', 'value': 4100000},
        {'label': 'Th 2', 'value': 6700000},
        {'label': 'Th 3', 'value': 7800000},
        {'label': 'Th 4', 'value': 6300000},
        {'label': 'Th 5', 'value': 9100000},
        {'label': 'Th 6', 'value': 8250000},
      ],
    };
  }

  Future<List<Map<String, Object?>>> fetchAppointmentsView({
    DateTime? day,
  }) async {
    return [
      {
        'id': 'apt-001',
        'dateLabel': 'Hôm nay',
        'time': '09:00',
        'customer': 'Chị Lan',
        'service': 'Nhuộm tóc',
        'staff': 'Hương',
        'status': 'Đã đặt',
        'duration': '150 phút',
        'phone': '0909 123 456',
        'slot': 'Ghế 02',
        'note': 'Đã xác nhận. Ưu tiên tone nâu lạnh và phục hồi sau nhuộm.',
      },
      {
        'id': 'apt-002',
        'dateLabel': 'Hôm nay',
        'time': '10:30',
        'customer': 'Anh Minh',
        'service': 'Cắt tóc',
        'staff': 'Nam',
        'status': 'Đang làm',
        'duration': '45 phút',
        'phone': '0938 111 444',
        'slot': 'Ghế 01',
        'note':
            'Khách quen. Muốn giữ side fade gọn và làm nhanh trong giờ nghỉ.',
      },
      {
        'id': 'apt-003',
        'dateLabel': 'Hôm nay',
        'time': '13:00',
        'customer': 'Chị Hoa',
        'service': 'Uốn tóc',
        'staff': 'Hương',
        'status': 'Hoàn thành',
        'duration': '180 phút',
        'phone': '0987 222 111',
        'slot': 'Ghế 03',
        'note': 'Đã hoàn thành. Khách hài lòng với độ xoăn tự nhiên.',
      },
      {
        'id': 'apt-004',
        'dateLabel': 'Hôm nay',
        'time': '15:00',
        'customer': 'Chị Mai',
        'service': 'Phục hồi tóc',
        'staff': 'Linh',
        'status': 'Đã đặt',
        'duration': '60 phút',
        'phone': '0912 555 222',
        'slot': 'Phòng chăm sóc',
        'note': 'Khách mới. Muốn tư vấn gói phục hồi định kỳ.',
      },
      {
        'id': 'apt-005',
        'dateLabel': 'Ngày mai',
        'time': '09:30',
        'customer': 'Chị Mai Hương',
        'service': 'Uốn sóng lơi',
        'staff': 'Hương',
        'status': 'Chờ xác nhận',
        'duration': '180 phút',
        'phone': '0912 888 999',
        'slot': 'Ghế 04',
        'note': 'Đặt online. Cần gọi xác nhận lại trước 20h.',
      },
      {
        'id': 'apt-006',
        'dateLabel': 'Ngày mai',
        'time': '16:30',
        'customer': 'Anh Tuấn Anh',
        'service': 'Cắt tóc layer',
        'staff': 'Nam',
        'status': 'Đã đặt',
        'duration': '50 phút',
        'phone': '0933 555 777',
        'slot': 'Ghế 01',
        'note': 'Khách muốn giữ texture tự nhiên, không quá ngắn.',
      },
    ];
  }

  Future<List<Map<String, Object?>>> fetchCustomersView({String? query}) async {
    final customers = [
      {
        'initials': 'CL',
        'name': 'Chị Lan',
        'phone': '0909 123 456',
        'visits': 14,
        'spent': '14.800.000đ',
        'tier': 'VIP Gold',
        'favoriteService': 'Nhuộm nâu lạnh + phục hồi',
        'lastVisit': '24/04/2026',
        'hairProfile': 'Tóc dày, đã nhuộm, ưu tiên tone lạnh',
        'note': 'Ưa lịch chiều, hay đặt trước 2-3 ngày.',
        'loyaltyPoints': 1480,
      },
      {
        'initials': 'MH',
        'name': 'Chị Mai Hương',
        'phone': '0912 888 999',
        'visits': 9,
        'spent': '11.250.000đ',
        'tier': 'VIP Silver',
        'favoriteService': 'Uốn sóng lơi + phục hồi',
        'lastVisit': '22/04/2026',
        'hairProfile': 'Tóc trung bình, dễ khô phần đuôi',
        'note': 'Ưu tiên stylist Hương.',
        'loyaltyPoints': 1125,
      },
      {
        'initials': 'TA',
        'name': 'Anh Tuấn Anh',
        'phone': '0933 555 777',
        'visits': 5,
        'spent': '2.350.000đ',
        'tier': 'Member',
        'favoriteService': 'Cắt tóc layer nam',
        'lastVisit': '20/04/2026',
        'hairProfile': 'Tóc cứng, cần giữ form gọn',
        'note': 'Hay ghé cuối tuần.',
        'loyaltyPoints': 235,
      },
      {
        'initials': 'CH',
        'name': 'Chị Hoa',
        'phone': '0987 222 111',
        'visits': 7,
        'spent': '6.900.000đ',
        'tier': 'VIP Silver',
        'favoriteService': 'Uốn tóc + hấp dầu',
        'lastVisit': '18/04/2026',
        'hairProfile': 'Tóc mảnh, cần tránh nhiệt cao',
        'note': 'Muốn tư vấn màu tối dễ chăm.',
        'loyaltyPoints': 690,
      },
    ];

    final normalizedQuery = query?.trim().toLowerCase();
    if (normalizedQuery == null || normalizedQuery.isEmpty) {
      return customers;
    }

    return customers.where((customer) {
      final haystacks = [
        customer['name'],
        customer['phone'],
        customer['tier'],
        customer['favoriteService'],
      ];

      return haystacks.any(
        (value) => value.toString().toLowerCase().contains(normalizedQuery),
      );
    }).toList();
  }

  Future<List<Map<String, Object?>>> fetchServicesView() async {
    return [
      {
        'id': 'svc-001',
        'name': 'Nhuộm tóc',
        'category': 'Nhuộm',
        'duration': '150 phút',
        'price': '1.200.000đ',
        'priceValue': 1200000,
        'popularity': 'Bán chạy',
        'status': 'Đang áp dụng',
        'description':
            'Gói nhuộm màu thời trang kèm tư vấn tone và bảo vệ tóc sau hóa chất.',
      },
      {
        'id': 'svc-002',
        'name': 'Phục hồi tóc',
        'category': 'Chăm sóc',
        'duration': '60 phút',
        'price': '500.000đ',
        'priceValue': 500000,
        'popularity': 'Ổn định',
        'status': 'Đang áp dụng',
        'description':
            'Liệu trình cấp ẩm và phục hồi tóc khô xơ sau uốn nhuộm.',
      },
      {
        'id': 'svc-003',
        'name': 'Cắt tóc nữ',
        'category': 'Cắt tóc',
        'duration': '45 phút',
        'price': '180.000đ',
        'priceValue': 180000,
        'popularity': 'Phổ biến',
        'status': 'Đang áp dụng',
        'description':
            'Cắt tạo kiểu cơ bản cho tóc nữ, phù hợp lịch nhanh trong ngày.',
      },
      {
        'id': 'svc-004',
        'name': 'Uốn sóng lơi',
        'category': 'Uốn',
        'duration': '180 phút',
        'price': '1.500.000đ',
        'priceValue': 1500000,
        'popularity': 'Bán chạy',
        'status': 'Đang áp dụng',
        'description':
            'Uốn form sóng lơi tự nhiên, ưu tiên giữ độ mềm và dễ chăm sóc.',
      },
      {
        'id': 'svc-005',
        'name': 'Gội đầu thư giãn',
        'category': 'Chăm sóc',
        'duration': '30 phút',
        'price': '150.000đ',
        'priceValue': 150000,
        'popularity': 'Phổ biến',
        'status': 'Đang áp dụng',
        'description': 'Gội đầu kết hợp massage thư giãn và sấy tạo nếp nhẹ.',
      },
      {
        'id': 'svc-006',
        'name': 'Duỗi tóc',
        'category': 'Duỗi',
        'duration': '180 phút',
        'price': '1.000.000đ',
        'priceValue': 1000000,
        'popularity': 'Ổn định',
        'status': 'Tạm ẩn',
        'description':
            'Duỗi mềm tự nhiên cho khách muốn kiểm soát độ phồng và xù tóc.',
      },
    ];
  }

  Future<List<Map<String, Object?>>> fetchEmployeesView() async {
    return [
      {
        'id': 'emp-001',
        'initials': 'HG',
        'name': 'Hương',
        'role': 'Stylist chính',
        'status': 'Đang làm việc',
        'phone': '0909 778 899',
        'shift': '09:00 - 18:00',
        'specialty': 'Nhuộm tone lạnh, phục hồi sau hóa chất',
        'commission': '18%',
        'todaySchedule': '5 lịch hôm nay',
        'servicesDone': 42,
        'monthlyRevenue': '68.500.000đ',
        'rating': '4.9',
        'note':
            'Stylist chủ lực của nhóm color. Ưu tiên khách VIP và các ca cần tư vấn tone màu.',
      },
      {
        'id': 'emp-002',
        'initials': 'NA',
        'name': 'Nam',
        'role': 'Barber',
        'status': 'Đang làm việc',
        'phone': '0938 110 445',
        'shift': '10:00 - 19:00',
        'specialty': 'Fade, cắt nam nhanh, tạo kiểu gọn',
        'commission': '15%',
        'todaySchedule': '4 lịch hôm nay',
        'servicesDone': 37,
        'monthlyRevenue': '39.200.000đ',
        'rating': '4.8',
        'note':
            'Phù hợp khách nam cần tốc độ xử lý nhanh trong khung giờ trưa và cuối ngày.',
      },
      {
        'id': 'emp-003',
        'initials': 'LN',
        'name': 'Linh',
        'role': 'Chăm sóc tóc',
        'status': 'Sắp có lịch',
        'phone': '0987 222 333',
        'shift': '08:30 - 17:30',
        'specialty': 'Phục hồi, gội dưỡng, chăm sóc da đầu',
        'commission': '12%',
        'todaySchedule': '2 lịch tiếp theo',
        'servicesDone': 28,
        'monthlyRevenue': '24.800.000đ',
        'rating': '4.7',
        'note':
            'Khách có xu hướng đặt thêm gói dưỡng sau khi tư vấn combo phục hồi.',
      },
      {
        'id': 'emp-004',
        'initials': 'TH',
        'name': 'Thảo',
        'role': 'Lễ tân',
        'status': 'Ca chiều',
        'phone': '0911 555 668',
        'shift': '13:00 - 21:00',
        'specialty': 'Điều phối lịch, chăm sóc khách sau dịch vụ',
        'commission': 'KPI cố định',
        'todaySchedule': 'Theo dõi 8 lịch',
        'servicesDone': 0,
        'monthlyRevenue': 'Hỗ trợ vận hành',
        'rating': '4.9',
        'note':
            'Phụ trách nhắc lịch, upsell combo chăm sóc và theo dõi phản hồi cuối ngày.',
      },
    ];
  }

  Future<List<Map<String, Object?>>> fetchInvoiceDraftView() async {
    return [
      {
        'id': 'line-001',
        'customerName': 'Nguyễn Thị Lan',
        'customerPhone': '0901 234 567',
        'customerInitials': 'NL',
        'staff': 'Hương',
        'label': 'Nhuộm tóc',
        'unitPrice': 1200000,
        'quantity': 1,
        'amount': '1.200.000đ',
      },
      {
        'id': 'line-002',
        'customerName': 'Nguyễn Thị Lan',
        'customerPhone': '0901 234 567',
        'customerInitials': 'NL',
        'staff': 'Hương',
        'label': 'Phục hồi tóc',
        'unitPrice': 500000,
        'quantity': 1,
        'amount': '500.000đ',
      },
      {
        'id': 'line-003',
        'customerName': 'Nguyễn Thị Lan',
        'customerPhone': '0901 234 567',
        'customerInitials': 'NL',
        'staff': 'Hương',
        'label': 'Gội đầu thư giãn',
        'unitPrice': 150000,
        'quantity': 1,
        'amount': '150.000đ',
      },
    ];
  }

  Future<Map<String, Object?>> fetchReportsSummary() async {
    return {
      'revenue': '52.400.000đ',
      'topService': 'Nhuộm tóc',
      'topEmployee': 'Hương',
      'fillRate': '82%',
      'periods': ['Hôm nay', '7 ngày', '30 ngày'],
      'defaultPeriod': '7 ngày',
      'revenueTrend': [
        {'label': 'T2', 'value': 6800000},
        {'label': 'T3', 'value': 7200000},
        {'label': 'T4', 'value': 7550000},
        {'label': 'T5', 'value': 8100000},
        {'label': 'T6', 'value': 7900000},
        {'label': 'T7', 'value': 9300000},
        {'label': 'CN', 'value': 8950000},
      ],
      'servicePerformance': [
        {
          'name': 'Nhuộm tóc',
          'revenue': '18.600.000đ',
          'bookings': 14,
          'share': '35%',
          'note': 'Dẫn đầu doanh thu tuần, mạnh ở nhóm khách VIP đổi tone.',
        },
        {
          'name': 'Uốn sóng lơi',
          'revenue': '13.500.000đ',
          'bookings': 9,
          'share': '26%',
          'note': 'Tỷ lệ chốt tốt vào cuối tuần, thường đi kèm phục hồi.',
        },
        {
          'name': 'Phục hồi tóc',
          'revenue': '8.400.000đ',
          'bookings': 16,
          'share': '16%',
          'note': 'Tần suất cao, phù hợp upsell sau nhuộm và uốn.',
        },
      ],
      'employeePerformance': [
        {
          'name': 'Hương',
          'role': 'Stylist chính',
          'revenue': '22.800.000đ',
          'clients': 18,
          'rating': '4.9',
          'focus': 'Mạnh về color và phục hồi sau hóa chất.',
        },
        {
          'name': 'Nam',
          'role': 'Barber',
          'revenue': '12.400.000đ',
          'clients': 23,
          'rating': '4.8',
          'focus': 'Xử lý nhanh lịch nam, hiệu suất cao giờ trưa.',
        },
        {
          'name': 'Linh',
          'role': 'Chăm sóc tóc',
          'revenue': '9.600.000đ',
          'clients': 15,
          'rating': '4.7',
          'focus': 'Tăng tỉ lệ gắn combo chăm sóc và phục hồi.',
        },
      ],
      'insights': [
        'Khung 15:00 - 18:00 đang tạo doanh thu tốt nhất trong 7 ngày gần đây.',
        'Gói nhuộm + phục hồi có biên lợi nhuận và tỉ lệ quay lại tốt hơn các nhóm khác.',
        'Hiệu suất nhân sự đang lệch về nhóm stylist chính, nên cân đối thêm ca chăm sóc.',
      ],
    };
  }

  Future<Map<String, Object?>> fetchLocalSettings() async {
    return {
      'salonName': 'Quản Lý Salon Tóc',
      'currency': 'VND',
      'appointmentReminder': 'Bật',
      'offlineUpdatePath': '',
      'autoCheckOfflineUpdate': 'Tắt',
      'licenseKey': '',
      'deviceId': '',
      'deviceName': 'Salon Windows',
      'themeDefault': 'Salon Emerald',
      'themeGoal':
          'Compact desktop dashboard, thong tin day du, de van hanh thuc te',
      'sampleData': 'Đang dùng fake in-memory data',
      'bankName': '',
      'accountNumber': '',
      'accountHolder': '',
      'uploadedQrPayload': '',
      'qrMode': 'both',
      'transferContentTemplate': 'Mã hóa đơn + SĐT khách',
    };
  }
}
