# Quản Lý Salon Tóc

Ứng dụng Flutter desktop-first để quản lý vận hành salon tóc trên Windows, tập trung vào lịch hẹn, khách hàng, dịch vụ, nhân sự, hóa đơn và thiết lập cục bộ.

## Phạm vi MVP hiện tại

- Chạy tốt theo hướng desktop-first cho Windows.
- Dữ liệu runtime chính đang lưu bằng SQLite cục bộ.
- Các màn hình Khách hàng, Lịch hẹn, Dịch vụ, Nhân sự, Hóa đơn và Thiết lập đã có luồng thao tác chính.
- Lịch hẹn hỗ trợ nhiều dịch vụ trong một booking và hóa đơn có thể prefill từ toàn bộ dịch vụ của lịch hẹn.
- Overview đã tổng hợp KPI và khối tổng quan từ SQLite runtime.
- Reports đang đọc dữ liệu từ SQLite runtime; nếu database trống thì repository sẽ seed dữ liệu mẫu ban đầu để tránh màn hình rỗng.
- Reports period selector đã nối query thật theo kỳ: Hôm nay, 7 ngày, 30 ngày, Tháng này.
- Đã có tab Bán hàng để quản lý sản phẩm bán lẻ và cấu hình ẩn/hiện cho cửa sổ nhân viên.
- Backup/Restore dữ liệu SQLite đã được tích hợp trong màn hình Cài đặt.

## Dữ liệu local và Backup/Restore

### Vị trí dữ liệu

| Hệ điều hành | Đường dẫn tệp dữ liệu |
|---|---|
| Windows | `%APPDATA%\HairSpaManager\data\.salon_manager\salon_manager.db` |
| Linux | `~/.local/share/hair_spa_manager/.salon_manager/salon_manager.db` |
| macOS | `~/Library/Application Support/HairSpaManager/.salon_manager/salon_manager.db` |

Thư mục chứa bản sao lưu (Windows): `%APPDATA%\HairSpaManager\data\backups\`

### Cách sao lưu dữ liệu

1. Mở màn hình **Cài đặt**.
2. Kéo xuống section **Sao lưu dữ liệu**.
3. Nhấn **Tạo bản sao lưu** — file `.db` sẽ được tạo tự động với tên có timestamp, ví dụ: `salon_manager_backup_2026-05-05_2130.db`.
4. File được lưu vào thư mục backup mặc định phía trên.

### Cách phục hồi dữ liệu

> ⚠️ **Cảnh báo**: Phục hồi sẽ thay thế hoàn toàn dữ liệu hiện tại. Ứng dụng tự tạo bản sao lưu dự phòng `pre_restore` trước khi ghi đè.

1. Mở màn hình **Cài đặt** → section **Sao lưu dữ liệu**.
2. Nhấn **Phục hồi từ bản sao lưu**.
3. Chọn tệp `.db` từ danh sách backup có sẵn, hoặc nhập đường dẫn tùy chỉnh.
4. Xác nhận cảnh báo rồi nhấn **Phục hồi**.
5. Dữ liệu trên màn hình tự cập nhật sau khi phục hồi thành công.

### Khuyến nghị

- **Luôn tạo bản sao lưu trước khi dùng dữ liệu thật hoặc trước khi cập nhật ứng dụng.**
- Copy thư mục backup ra ổ ngoài hoặc mạng nội bộ định kỳ để tránh mất dữ liệu khi hỏng máy.

## Công nghệ

- Flutter
- Riverpod
- SQLite với `sqflite` và `sqflite_common_ffi`
- SharedPreferences cho thiết lập cục bộ

## Chạy ứng dụng ở môi trường dev

Yêu cầu:

- Flutter SDK tương thích với cấu hình trong `pubspec.yaml`
- Windows desktop support đã bật trong Flutter

Lệnh cơ bản:

```bash
flutter pub get
flutter run -d windows
```

Kiểm tra chất lượng trước khi đóng gói:

```bash
flutter analyze
flutter test
```

## Build phát hành Windows

```bash
flutter build windows --release
```

Output phát hành nằm dưới:

- `build/windows/x64/runner/Release/`

## Dữ liệu cục bộ và backup

SQLite file trên Windows được tạo theo APPDATA của user:

- `%APPDATA%/HairSpaManager/data/.salon_manager/salon_manager.db`

Khuyến nghị vận hành:

1. Đóng ứng dụng trước khi backup.
2. Sao chép toàn bộ thư mục `%APPDATA%/HairSpaManager/data/.salon_manager` sang nơi an toàn.
3. Khi restore, ghi đè lại thư mục `%APPDATA%/HairSpaManager/data/.salon_manager` của user đang chạy app.

Lưu ý:

- Trên Windows, đường dẫn database không phụ thuộc thư mục chạy exe vì app resolve theo APPDATA.
- Thiết lập cục bộ như tên salon, tiền tệ, nhắc lịch đang lưu qua SharedPreferences trên máy người dùng.

## Trạng thái dữ liệu thật và dữ liệu demo

- Appointments, Customers, Services, Employees, Sales, Invoices: đã dùng runtime repository SQLite.
- Overview: KPI, khách nổi bật, quick checkout và biểu đồ doanh thu đã tổng hợp từ SQLite runtime cục bộ.
- Reports: đang dùng repository SQLite; có cơ chế seed dữ liệu mẫu ban đầu nếu database chưa có dữ liệu.
- Settings: đang dùng SettingsRepository dựa trên LocalSettingsStore (SharedPreferences), không lưu vào SQLite.

Có thể dùng Overview và Reports để đọc nhanh số liệu vận hành cục bộ của máy đang chạy app. Với máy mới chưa phát sinh dữ liệu, Reports có thể hiển thị dữ liệu seed ban đầu.

## Startup hardening

Từ bản hiện tại, ứng dụng sẽ hiển thị màn hình lỗi khởi động nếu không thể tạo môi trường SQLite hoặc mở database, thay vì thoát im lặng. Khi gặp lỗi này, kiểm tra:

1. Quyền ghi của `%APPDATA%/HairSpaManager/data/.salon_manager`.
2. Sự tồn tại và khả năng truy cập của `%APPDATA%/HairSpaManager/data/.salon_manager/salon_manager.db`.
3. Việc ứng dụng có đang bị chặn bởi antivirus hoặc chạy từ thư mục chỉ đọc hay không.

## Checklist preview trước publish

1. Mở app trên Windows và kiểm tra khởi động mới với database trống.
2. Tạo khách hàng, dịch vụ, lịch hẹn nhiều dịch vụ, rồi xuất hóa đơn từ lịch đó.
3. Thêm hoặc sửa nhân sự, đổi trạng thái và mở lại app để xác nhận dữ liệu còn giữ.
4. Sửa tên salon, tiền tệ, nhắc lịch trong Thiết lập và mở lại app để xác nhận persistence.
5. Mở Overview và Reports để xác nhận số liệu thay đổi theo dữ liệu runtime trên máy.
6. Chạy `flutter analyze`, `flutter test`, `flutter build windows --release`.

## Hạn chế còn lại

- Reports có thể hiển thị dữ liệu seed ở máy mới (khi chưa có dữ liệu phát sinh thực tế).
- Chưa có bộ test migration hoặc test riêng cho các error path khi bootstrap.
- README này mô tả publish nội bộ trên Windows, chưa bao gồm code signing hay installer chuyên biệt.

## Phương án update offline đã chốt

- Kênh update ưu tiên hiện tại là offline nội bộ, không phụ thuộc cloud.
- Admin publish một `version.json` và file installer `.exe` vào thư mục update chung.
- App ở phase tiếp theo chỉ cần đọc manifest này để hiện thông báo có bản mới và mở installer.

Tham khảo chi tiết tại:

- `offline_update/README.md`
- `offline_update/version.json.example`

