# Go-Live Checklist — Windows Installer + R2 Updater

## 1) Installer
- [ ] `npm run package:installer` tạo `Salon-Setup-x.x.x.exe`.
- [ ] Installer có trang chọn thư mục và thử cài ít nhất một lần ngoài ổ C (ví dụ D/E nếu máy có ổ đó).
- [ ] Desktop shortcut mở đúng Salon.
- [ ] Start Menu shortcut mở đúng Salon.
- [ ] Cài/update không xóa `%APPDATA%\HairSpaManager\data` hoặc backup hiện có.
- [ ] Không có logic scan/copy/adopt/migrate data từ portable/app cũ bên ngoài.

## 2) Kênh cập nhật
- [ ] Public feed đúng: `https://pub-3f0aad8b18e146eb9eb09b9529063295.r2.dev`.
- [ ] App/source không chứa Account ID, S3 endpoint, Access Key hoặc Secret.
- [ ] `npm run package:update` tạo installer và `latest.json` có SHA-256 hợp lệ.
- [ ] Upload installer lên R2 trước.
- [ ] Upload `latest.json` cuối cùng.
- [ ] Thử một lần SHA-256 sai để xác nhận app chặn gói không hợp lệ.

## 3) Luồng cập nhật thực tế
- [ ] Cài baseline Salon version N.
- [ ] Upload version N+1 lên R2 theo đúng thứ tự.
- [ ] Mở version N → `Kiểm tra cập nhật` → thấy N+1.
- [ ] `Tải bản cập nhật` → progress chạy và đạt 100%.
- [ ] Sau tải xong xuất hiện `Khởi động lại & cập nhật`.
- [ ] Installer silent ghi đè đúng thư mục Salon đang cài và tự mở app lại.
- [ ] Chỉ sau restart sang đúng N+1 mới hiện thông báo cập nhật thành công.
- [ ] Database, thiết lập và dữ liệu vận hành của version N vẫn còn nguyên sau update.

## 4) Gate kỹ thuật
- [ ] `npm run typecheck` / `flutter analyze` pass.
- [ ] `npm run unit` / `flutter test` pass.
- [ ] `npm run build` / Windows release build pass.
- [ ] `npm run smoke:windows` pass main + Staff process.
- [ ] `npm run verify:installer` pass.
- [ ] `npm run verify:updater` pass.
- [ ] PR CI xanh trên đúng head SHA.

## 5) Release discipline
- [ ] Version trong `pubspec.yaml` đã tăng so với bản đang phát hành.
- [ ] Build/release thực hiện ở máy local; CI chỉ test/verify.
- [ ] Không commit installer/generated `latest.json` vào source.
- [ ] Không upload R2 từ CI.
- [ ] Không merge PR nếu chưa có lệnh rõ ràng.

## Go / No-Go
- **Go:** các gate kỹ thuật xanh, installer/update test thực tế qua R2 thành công, data giữ nguyên.
- **No-Go:** bất kỳ gate nào đỏ, SHA/version sai, updater báo success trước restart, hoặc update làm mất/di chuyển data runtime.
