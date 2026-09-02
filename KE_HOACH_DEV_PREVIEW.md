# Kế Hoạch Dev Preview

Mục tiêu của đợt này là đưa bản preview tiến gần mức vận hành thật, đồng thời làm giao diện sắc và đồng bộ hơn. Không mở rộng scope sang cloud, payment gateway hay viết lại toàn bộ UI.

## Mục tiêu chính

- Đưa Overview từ dữ liệu demo sang dữ liệu SQLite thật.
- Đưa Reports từ dữ liệu demo sang dữ liệu SQLite thật.
- Làm lại lớp UI consistency cho button, badge, panel để app bớt thô.
- Giữ nguyên kiến trúc hiện tại: Flutter desktop-first, Riverpod, SQLite local-first.

## Hiện trạng đã xác nhận

- Appointments, Customers, Services, Employees, Invoices đã có runtime SQLite thật.
- Overview và Reports vẫn còn đang dùng fake repository.
- Nút và badge hiện chưa đồng bộ vì nhiều chỗ tự style inline thay vì dùng shared component.

## Checklist giao việc

### Dev 1 - UI foundation

- [x] Chuẩn hóa button theme trong `lib/core/theme/app_theme.dart`.
- [x] Tạo shared primitives trong `lib/shared/widgets/` cho badge và choice button.
- [x] Thay custom payment button ở `lib/features/invoices/presentation/pages/invoices_page.dart`.
- [x] Dọn hero badge và status badge ở Overview hoặc Reports để không còn mỗi nơi một style.
- [ ] Verify tay trên Windows: hover, selected, disabled, spacing.

### Dev 2 - Overview runtime

- [x] Tạo `sqlite_overview_repository.dart`.
- [x] Tính KPI thật từ appointments và invoices.
- [x] Tính revenue series 7 ngày từ invoices đã thanh toán.
- [x] Tính featured customers từ customers và invoice history.
- [x] Đọc draft invoice hiện tại để build quick checkout summary.
- [x] Đổi `overviewRepositoryProvider` sang switch backend.
- [x] Bỏ notice demo khi chạy SQLite runtime.

### Dev 3 - Reports runtime

- [x] Tạo `sqlite_reports_repository.dart`.
- [x] Tính doanh thu theo kỳ.
- [x] Tính fill rate.
- [x] Tính top service và top employee.
- [x] Sinh operational insights từ dữ liệu thật.
- [x] Đổi `reportsRepositoryProvider` sang switch backend.
- [x] Thêm test cho report aggregation.

### QA nhanh trước preview

- [ ] Tạo mới khách hàng, dịch vụ, nhân sự.
- [ ] Tạo lịch hẹn và checkout hóa đơn.
- [ ] Mở lại Overview để đối chiếu KPI và doanh thu.
- [ ] Mở lại Reports để đối chiếu top service và top employee.
- [x] Chạy `flutter analyze`.
- [x] Chạy `flutter test`.

## File cần tập trung

- `lib/core/providers/repository_providers.dart`
- `lib/core/repositories/repository_contracts.dart`
- `lib/core/repositories/fake_repositories.dart`
- `lib/core/repositories/sqlite_invoices_repository.dart`
- `lib/core/database/database_schema.dart`
- `lib/core/database/salon_database.dart`
- `lib/core/theme/app_theme.dart`
- `lib/core/theme/app_colors.dart`
- `lib/shared/widgets/`
- `lib/features/overview/presentation/pages/overview_page.dart`
- `lib/features/reports/presentation/pages/reports_page.dart`
- `lib/features/invoices/presentation/pages/invoices_page.dart`
- `README.md`
- `HUONG_DAN_SU_DUNG_NHANH.md`

## Thứ tự triển khai đề xuất

### Phase 1 - Shared UI foundation

Mục tiêu: làm lớp nền giao diện để nút và badge nhìn sắc hơn nhưng không phá layout hiện tại.

Việc cần làm:

- Chuẩn hóa radius, padding, state màu trong `app_theme.dart`.
- Bổ sung shared widget cho button.
- Bổ sung shared widget cho badge hoặc trạng thái.
- Nếu cần, thêm shared panel/card wrapper để giảm lặp decoration.
- Thay các custom button inline, ưu tiên bắt đầu từ module invoices.

Kỳ vọng:

- Nút bấm rõ hierarchy hơn.
- Trạng thái selected, hover, pressed nhìn tinh hơn.
- Các màn hình không còn lệch style giữa từng module.

### Phase 2 - Overview SQLite runtime

Mục tiêu: thay phần Overview đang fake bằng dữ liệu tổng hợp từ SQLite.

Việc cần làm:

- Tạo SQLite Overview repository mới.
- Tính KPI từ appointments, invoices, invoice_items, customers.
- Tạo revenue series từ dữ liệu thanh toán thật.
- Tính featured customers từ tổng chi tiêu, số lượt hoặc lịch gần đây.
- Tính quick checkout summary từ dữ liệu runtime hoặc đổi wording nếu khối này không còn phù hợp.
- Đổi `overviewRepositoryProvider` sang switch theo `appDataBackendProvider` thay vì hardcode fake.
- Chỉ hiện notice dữ liệu demo khi app chạy fake backend.

Lưu ý:

- Giữ shape dữ liệu hiện tại để page không vỡ trong lúc thay repository.
- Không dùng số liệu giả trong runtime SQLite.

### Phase 3 - Reports SQLite runtime

Mục tiêu: thay Reports đang fake bằng báo cáo tổng hợp thật từ SQLite.

Việc cần làm:

- Tạo SQLite Reports repository mới.
- Tính doanh thu theo kỳ.
- Tính fill rate theo lịch hẹn và trạng thái.
- Tính service performance từ invoice_items và services.
- Tính employee performance từ appointment hoặc invoice linkage đang có.
- Sinh insight vận hành từ số liệu thật, không giữ wording kiểu demo.
- Đổi `reportsRepositoryProvider` sang switch theo backend.
- Chỉ giữ notice demo khi chạy fake backend.

Lưu ý:

- Nếu một metric chưa đủ dữ liệu để tính chuẩn, phải ghi rõ fallback hoặc loại bỏ metric đó khỏi preview.
- Không dựng báo cáo “cho đẹp” nhưng sai số liệu.

### Phase 4 - Page cleanup sau khi đã nối data thật

Mục tiêu: dọn lại copy, notice, action hierarchy và component dùng lại.

Việc cần làm:

- Overview: bỏ wording nói đang demo khi backend là SQLite.
- Reports: bỏ wording nói đang demo khi backend là SQLite.
- Invoices: thay `_PaymentButton` bằng shared button primitive.
- Chuẩn hóa badge hero, chip trạng thái và spacing ở các màn hình liên quan trực tiếp.

### Phase 5 - Test và tài liệu

Mục tiêu: tránh preview nhìn ổn nhưng số liệu hoặc hành vi bị sai.

Việc cần làm:

- Thêm test cho Overview runtime SQLite.
- Thêm test cho Reports runtime SQLite.
- Chạy `flutter analyze`.
- Chạy `flutter test`.
- Chạy manual flow trên Windows:
  - tạo khách hàng
  - tạo dịch vụ
  - tạo nhân sự
  - tạo lịch hẹn
  - checkout hóa đơn
  - mở lại Overview và Reports để đối chiếu số liệu
- Cập nhật `README.md` và `HUONG_DAN_SU_DUNG_NHANH.md` theo trạng thái mới.

## Definition of Done

- Overview không còn hardcode fake khi chạy SQLite.
- Reports không còn hardcode fake khi chạy SQLite.
- Button, badge, panel ở các màn hình chính nhìn đồng bộ và sắc hơn.
- `flutter analyze` sạch.
- `flutter test` pass.
- Manual preview flow trên Windows cho ra số liệu đúng với dữ liệu đã nhập.

## Ngoài scope đợt này

- Cloud sync.
- Payment gateway thật.
- Android-specific polish.
- Viết lại navigation shell.
- Viết lại toàn bộ giao diện từng module.

## Gợi ý triển khai thực tế

Thứ tự nên làm:

1. Shared UI foundation.
2. Overview SQLite repository.
3. Reports SQLite repository.
4. Cleanup page copy và component.
5. Test và cập nhật tài liệu.

Nếu cần cắt nhỏ để giao việc:

- Dev 1: shared UI + invoices button cleanup.
- Dev 2: Overview SQLite aggregation.
- Dev 3: Reports SQLite aggregation + test.