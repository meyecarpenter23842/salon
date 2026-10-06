# Hair Spa Manager

Hair Spa Manager là ứng dụng Flutter desktop-first để quản lý vận hành salon tóc trên Windows, tập trung vào lịch hẹn, khách hàng, dịch vụ, nhân sự, hóa đơn và thiết lập cục bộ.

## Vận hành và nghiệm thu desktop–Android LAN

- [Hướng dẫn vận hành](docs/salon-operations.md): APK đúng nguồn/hash, QR/ghép quyền, reconnect, kho, backup và rollback.
- [Biên bản nghiệm thu điện thoại thật](docs/salon-qa-acceptance.md): model/OS/bản đã cài, từng ca và bằng chứng.
- [Contract LAN hiện hành](docs/lan-companion-v1.md), [roadmap #104](https://github.com/meyecarpenter23842/salon/issues/104) và [QA #111](https://github.com/meyecarpenter23842/salon/issues/111).

Android đã có khách/lịch/bill/thanh toán theo quyền và reconnect; **chưa nghiệm thu điện thoại thật**. CI/emulator không thay gate này. Quy trình dự án hiện tại không chạy app/build/test local hoặc cài/migrate production khi chưa có yêu cầu riêng; các lệnh dev bên dưới chỉ cho môi trường phát triển được cho phép.

[Audit nhân sự và lộ trình hoa hồng/chấm công/payroll](docs/personnel-audit.md) thuộc #112. Hoa hồng hiện chỉ là ước tính, chưa có sổ chốt/chi trả.

## Phạm vi MVP hiện tại

- Chạy tốt theo hướng desktop-first cho Windows.
- Dữ liệu runtime chính đang lưu bằng SQLite cục bộ.
- Các màn hình Khách hàng, Lịch hẹn, Dịch vụ, Nhân sự, Hóa đơn và Thiết lập đã có luồng thao tác chính.
- Lịch hẹn hỗ trợ nhiều dịch vụ trong một booking và hóa đơn có thể prefill từ toàn bộ dịch vụ của lịch hẹn.
- Lịch đã thanh toán được khóa khỏi các thay đổi nghiệp vụ có thể làm lệch hóa đơn; lịch hủy không còn được tính như lịch active/upcoming.
- POS lưu bền bill dở, bảo vệ checkout trùng, ghi nhận nhân viên theo dòng dịch vụ, hỗ trợ refund/void, nối tồn kho thật, chốt ca thu ngân, split payment và Owner PIN + audit bất biến cho thao tác nhạy cảm.
- Overview đã tổng hợp KPI và khối tổng quan từ SQLite runtime.
- Reports đọc dữ liệu thật từ SQLite runtime; database mới/rỗng giữ trạng thái rỗng và không tự seed dữ liệu mẫu.
- Reports period selector đã nối query thật theo kỳ: Hôm nay, 7 ngày, 30 ngày, Tháng này.
- Doanh thu Reports/hiệu suất nhân viên dùng cùng cơ sở doanh thu thực thu sau giảm giá toàn bill; phần giảm toàn bill được phân bổ xuống dòng theo quy tắc deterministic.
- Đã có tab Bán hàng để quản lý sản phẩm bán lẻ và cấu hình ẩn/hiện cho cửa sổ nhân viên.
- Backup/Restore dữ liệu SQLite đã được tích hợp trong màn hình Cài đặt.
- Windows release dùng NSIS installer và updater online qua public Cloudflare R2 feed.

## Nhiều bill trên desktop

POS SQLite có danh sách bill đang mở và nút **Bill mới** để tạo bill khách vãng lai.
Mở tính tiền từ lịch hẹn/Bàn nhân viên chọn billing session của đúng lịch; bill khác được giữ nguyên.
Mỗi lịch có tối đa một session active; bill dở và bill legacy được lưu trong SQLite và có thể chọn lại sau khi mở app.
Danh sách có nút tải lại để cập nhật bill từ cửa sổ khác. Sau checkout, bill đã chốt rời danh sách active; phiếu và lịch sử vẫn mở được.
Lựa chọn bill thuộc từng cửa sổ, không thay đổi lựa chọn của cửa sổ khác. Khi mở lại app, dùng danh sách để chọn bill cần tiếp tục.
Backend fake/demo vẫn giữ luồng một bill cũ.

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
2. Chọn **Backup & Restore**.
3. Nhấn **Tạo bản sao lưu** — file `.db` sẽ được tạo tự động với tên có timestamp, ví dụ: `salon_manager_backup_2026-05-05_2130.db`.
4. File được lưu vào thư mục backup mặc định phía trên.

### Cách phục hồi dữ liệu

> ⚠️ **Cảnh báo**: Phục hồi sẽ thay thế hoàn toàn dữ liệu hiện tại. Ứng dụng tự tạo bản sao lưu dự phòng `pre_restore` trước khi ghi đè.

1. Mở màn hình **Cài đặt → Backup & Restore**.
2. Nhấn **Phục hồi từ bản sao lưu**.
3. Chọn tệp `.db` từ danh sách backup có sẵn, hoặc nhập đường dẫn tùy chỉnh.
4. Xác nhận cảnh báo rồi nhấn **Phục hồi**.
5. Đối chiếu dữ liệu sau phục hồi trước mở lại Staff/điện thoại; theo [quy trình restore](docs/salon-operations.md). Dừng ghi và đóng Staff trước restore.

### Khuyến nghị

- **Luôn tạo bản sao lưu trước khi dùng dữ liệu thật hoặc trước khi cập nhật ứng dụng.**
- Copy thư mục backup ra ổ ngoài hoặc mạng nội bộ định kỳ để tránh mất dữ liệu khi hỏng máy.

## Công nghệ

- Flutter Windows native
- Riverpod
- SQLite với `sqflite` và `sqflite_common_ffi`
- SharedPreferences cho thiết lập cục bộ
- NSIS cho Windows installer
- Cloudflare R2 public feed cho updater

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

PR vào `main` còn có gate Windows tự động: chạy toàn bộ `flutter test` trên `windows-latest`, build `flutter build windows --release`, smoke main + Staff process, đóng gói NSIS để verify và kiểm tra contract updater. CI không publish/upload release.

## Build phát hành Windows

Build Flutter thuần:

```bash
flutter build windows --release
```

Output Flutter nằm dưới:

- `build/windows/x64/runner/Release/`

Tạo installer NSIS có thể chọn ổ/thư mục:

```powershell
npm run package:installer
```

Tạo installer + metadata updater:

```powershell
npm run package:update
```

Bản phát hành chính thức có code signing:

```powershell
$env:SALON_SIGNING_THUMBPRINT = '<certificate-thumbprint>'
npm run package:update:signed
npm run verify:installer:signed
```

Certificate/private key chỉ nằm trên máy release, không commit vào repo.

Output release local:

- `dist/windows-release/Salon-Setup-x.x.x.exe`
- `dist/windows-release/latest.json`

Các bundle portable/test kiểu `dist/salonmanager-windows-test-*` là artifact sinh ra, không phải source và không được commit. Nếu thanh tiêu đề còn hiện chuỗi tiếng Việt lỗi kiểu `Quáº...`, máy đang mở binary cũ; phải build/cài lại từ release hiện tại thay vì chạy bundle test cũ.

Hướng dẫn đầy đủ: `WINDOWS_RELEASE.md`.

## Dữ liệu cục bộ và backup

SQLite file trên Windows được tạo theo APPDATA của user:

- `%APPDATA%/HairSpaManager/data/.salon_manager/salon_manager.db`

Khuyến nghị vận hành:

1. Đóng ứng dụng trước khi backup.
2. Sao chép toàn bộ thư mục `%APPDATA%/HairSpaManager/data/.salon_manager` sang nơi an toàn.
3. Khi restore, ghi đè lại thư mục `%APPDATA%/HairSpaManager/data/.salon_manager` của user đang chạy app.

Lưu ý:

- Trên Windows, đường dẫn database không phụ thuộc thư mục chạy exe vì app resolve theo APPDATA.
- Installer/update chỉ thay application payload trong thư mục cài đặt; không xóa/migrate runtime data AppData.
- Không có logic scan/copy/adopt data từ portable hoặc ứng dụng cũ bên ngoài.
- Thiết lập cục bộ như tên salon, tiền tệ, nhắc lịch đang lưu qua SharedPreferences trên máy người dùng.

## Trạng thái dữ liệu thật và dữ liệu demo

- Appointments, Customers, Services, Employees, Sales, Invoices: dùng runtime repository SQLite.
- Overview: KPI, khách nổi bật, quick checkout và biểu đồ doanh thu tổng hợp từ SQLite runtime cục bộ.
- Reports: dùng SQLite runtime và trả trạng thái zero/empty khi chưa có dữ liệu thật.
- Database production mới không tự tạo customer/service/employee/appointment/invoice mẫu.
- Fake data chỉ thuộc backend fake được chọn rõ ràng trong test/demo; không được dùng để bootstrap SQLite production.
- Invoice draft chưa chọn khách không tạo customer/invoice nghiệp vụ giả; khi bill dở có thay đổi, trạng thái draft được lưu bền trong SQLite và được khôi phục sau khi mở lại app.
- Settings: đang dùng SettingsRepository dựa trên LocalSettingsStore (SharedPreferences), không lưu vào SQLite.

Có thể dùng Overview và Reports để đọc nhanh số liệu vận hành cục bộ của máy đang chạy app. Với máy mới chưa phát sinh dữ liệu, các màn này hiển thị số 0/empty state thay vì số liệu mẫu.

## Chẩn đoán & hỗ trợ

Trong **Cài đặt → Chẩn đoán & Hỗ trợ**, Hair Spa Manager có thể hiển thị version/build, Windows version, database schema, đường dẫn dữ liệu/backup/log và kênh cập nhật.

Có thể tạo file chẩn đoán kỹ thuật trong thư mục `%APPDATA%\HairSpaManager\logs`. File này chỉ lấy tối đa 200 dòng cuối của các log hỗ trợ đã biết (`startup_failure.log`, `update_audit.log`, `self_update_helper.log`), tự redact path người dùng và các giá trị nhạy cảm dạng token/password/license key/email. Không đóng gói SQLite database, file backup hoặc dữ liệu khách hàng.

## Startup hardening

Từ bản hiện tại, ứng dụng sẽ hiển thị màn hình lỗi khởi động nếu không thể tạo môi trường SQLite hoặc mở database, thay vì thoát im lặng. Khi gặp lỗi này, kiểm tra:

1. Quyền ghi của `%APPDATA%/HairSpaManager/data/.salon_manager`.
2. Sự tồn tại và khả năng truy cập của `%APPDATA%/HairSpaManager/data/.salon_manager/salon_manager.db`.
3. Việc ứng dụng có đang bị chặn bởi antivirus hoặc chạy từ thư mục chỉ đọc hay không.
4. Log khởi động tại `%APPDATA%\HairSpaManager\logs\startup_failure.log` nếu app ghi được log trước khi hiển thị màn lỗi.

## Checklist preview trước publish

1. Mở app trên Windows và kiểm tra khởi động mới với database trống; xác nhận không có dữ liệu khách/dịch vụ/nhân viên/lịch/hóa đơn mẫu tự xuất hiện.
2. Tạo khách hàng, dịch vụ, lịch hẹn nhiều dịch vụ, rồi xuất hóa đơn từ lịch đó.
3. Thêm hoặc sửa nhân sự, đổi trạng thái và mở lại app để xác nhận dữ liệu còn giữ.
4. Sửa tên salon, tiền tệ, nhắc lịch trong Thiết lập và mở lại app để xác nhận persistence.
5. Mở Overview và Reports để xác nhận số liệu thay đổi theo dữ liệu runtime trên máy.
6. Xác nhận PR CI xanh cả **Analyze and test** và **Windows regression smoke** trên đúng head SHA.
7. Chạy `package:update`, verify installer/updater artifact và test upgrade thực tế qua R2 trước khi phát hành cho máy salon.
8. Trước publish thực tế vẫn chạy một lượt tương tác Windows thủ công cho PDF/CSV/backup-restore và các đường dẫn local phụ thuộc OS.

## Hạn chế còn lại

- Owner PIN hiện bảo vệ giảm giá, sửa giá bill, refund/void và các save settings qua runtime repository; chưa có đăng nhập/phân quyền nhiều actor theo nhân viên.
- Chưa có payroll/chấm công hoàn chỉnh.
- Release tooling hỗ trợ Authenticode code signing. Bản phát hành chính thức phải dùng certificate hợp lệ và package với `-RequireCodeSigning`; source/CI không chứa private key.

## Windows auto update qua R2

Public feed:

```text
https://pub-3f0aad8b18e146eb9eb09b9529063295.r2.dev
```

App chỉ chứa public URL. Không chứa Account ID, S3 endpoint, Access Key hay Secret.

Luồng UI:

```text
Kiểm tra cập nhật
→ phát hiện bản mới
→ tải và hiện %
→ xác minh SHA-256
→ Khởi động lại & cập nhật
→ app mở lại
→ chỉ báo thành công nếu version sau restart đúng target
```

Release được build local. Upload R2 thủ công theo thứ tự installer trước và `latest.json` cuối cùng. Xem `WINDOWS_RELEASE.md` để biết quy trình chi tiết.

