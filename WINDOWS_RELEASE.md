# Windows installer + R2 updater

Hair Spa Manager vẫn là **Flutter Windows native**. NSIS chỉ đóng gói output `flutter build windows --release`; không có Electron/React runtime.

## 1. Installer

Chạy trên Windows:

```powershell
npm run package:installer
```

Hoặc chạy PowerShell trực tiếp:

```powershell
.\tools\windows\package-installer.ps1
```

Output:

```text
dist\windows-release\Salon-Setup-x.x.x.exe
```

Tên file `Salon-Setup-*` được giữ ổn định để tương thích updater hiện tại; tên sản phẩm hiển thị trong Windows/shortcut là **Hair Spa Manager**.

Installer dùng NSIS dạng wizard:

- có trang chọn thư mục cài đặt;
- có thể chọn ổ C/D/E hoặc thư mục khác;
- cài theo user hiện tại;
- tạo Desktop shortcut;
- tạo Start Menu shortcut;
- nhớ thư mục cài trong HKCU để lần cài thủ công sau vẫn trỏ đúng vị trí;
- dùng `icon.png` ở root repo làm nguồn icon cho installer/uninstaller; script package tự tạo ICO đa kích thước trước khi chạy NSIS.

Runtime data của Salon **không nằm trong thư mục cài**. Database vẫn ở `%APPDATA%\HairSpaManager\data\.salon_manager\salon_manager.db`, vì vậy update installer không xóa/move database hoặc backup.

Không có logic scan/copy/adopt/migrate dữ liệu từ portable hoặc app cũ bên ngoài.

### Code signing cho release chính thức

Release tooling ký cả `salonmanager.exe` và installer bằng Windows Authenticode khi có certificate trong Current User certificate store.

```powershell
$env:SALON_SIGNING_THUMBPRINT = '<SHA1-thumbprint-40-hex>'
# Tùy chọn; mặc định dùng DigiCert RFC3161 timestamp.
$env:SALON_TIMESTAMP_URL = 'http://timestamp.digicert.com'

npm run package:update:signed
npm run verify:installer:signed
```

`-RequireCodeSigning` làm package fail nếu thiếu certificate/signature. Không commit PFX, private key hoặc password vào repo/CI.

## 2. Tạo bản update

Version nguồn nằm trong `pubspec.yaml` và phải tăng trước mỗi release, ví dụ:

```text
1.8.0+18
1.8.1+19
1.8.2+20
```

Tạo bộ update:

```powershell
npm run package:update
```

Output:

```text
dist\windows-release\Salon-Setup-x.x.x.exe
dist\windows-release\latest.json
```

`latest.json` chứa version, tên installer và SHA-256. Script không upload file và không cần R2 credential.

## 3. Cloudflare R2

Public feed cố định trong app:

```text
https://pub-3f0aad8b18e146eb9eb09b9529063295.r2.dev
```

Bucket vận hành: `beauty-salon`.

App chỉ biết public URL ở trên. Không đưa Account ID, S3 endpoint, Access Key hoặc Secret vào source/runtime.

Upload thủ công theo đúng thứ tự:

1. `Salon-Setup-x.x.x.exe`
2. `latest.json` **cuối cùng**

`latest.json` là commit pointer của release. Chỉ khi file này được thay thế, client mới nhìn thấy version mới.

## 4. Luồng updater trong app

Trong **Cài đặt → Cập nhật Salon**:

```text
Kiểm tra cập nhật
  → phát hiện version mới
  → Tải bản cập nhật
  → hiện % tải
  → xác minh SHA-256
  → Khởi động lại & cập nhật
  → installer silent đóng các cửa sổ Salon
  → ghi đè binary đúng thư mục đang cài
  → mở Salon lại
  → app kiểm tra version sau restart
  → chỉ khi version == target mới báo cập nhật thành công
```

Marker update chỉ chứa `fromVersion`, `targetVersion`, `requestedAt` trong `%APPDATA%\HairSpaManager\updates\pending_update.json`. Marker không chứa business data.

## 5. Verify

```powershell
npm run typecheck
npm run unit
npm run build
npm run smoke:windows
npm run verify:installer
npm run verify:updater
```

Sau khi package update, verify cả artifact:

```powershell
.\tools\windows\verify-installer.ps1 -RequireArtifacts
.\tools\windows\verify-updater.ps1 -RequireArtifacts
```

`verify-installer -RequireArtifacts` kiểm tra cả icon shell 16x16 và 32x32 nhúng trong `Salon-Setup-x.x.x.exe` phải khớp ICO vừa sinh từ `icon.png`, để chặn NSIS quay về icon mặc định.

CI chạy analyze, unit, Windows build, native smoke, build NSIS để verify và kiểm tra artifact. CI **không upload R2, không tạo release, không deploy và không giữ private signing key**. Code signing thật được thực hiện trên máy release.

## 6. Test end-to-end release

Có thể dùng build override để dựng hai version từ cùng code updater khi test lần đầu:

```powershell
# Baseline có updater mới nhưng version thấp
.\tools\windows\package-installer.ps1 -BuildName 1.8.0 -BuildNumber 18

# Sau đó tăng pubspec hoặc build bản mới
.\tools\windows\package-update.ps1 -BuildName 1.8.1 -BuildNumber 19
```

Kịch bản acceptance:

```text
cài Salon 1.8.0
→ upload Salon-Setup-1.8.1.exe lên R2
→ upload latest.json cuối cùng
→ mở Salon 1.8.0
→ Kiểm tra cập nhật
→ Tải bản cập nhật (theo dõi %)
→ Khởi động lại & cập nhật
→ Salon tự mở lại
→ xác nhận UI báo đang chạy 1.8.1 và cập nhật thành công
```

Trước test với dữ liệu thật nên dùng chức năng Backup hiện có của Salon.
