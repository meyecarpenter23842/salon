# Offline Update

Tài liệu này chốt phương án update offline cho Quản Lý Salon Tóc.

## Mục tiêu

- Không cần cloud hay API server.
- Admin quản trị update từ một nguồn cục bộ.
- App chỉ cần đọc manifest để biết có bản mới hay không.
- Khi user đồng ý cập nhật, app mở bộ cài `.exe` tương ứng.

## Nguồn update chuẩn

Ưu tiên dùng một thư mục mạng nội bộ chung.

Ví dụ:

```text
\\SERVER-PC\salon-update\
  version.json
  SalonManagerSetup-1.0.2.exe
  release-notes-1.0.2.txt
```

Nếu không có LAN, có thể dùng thư mục cục bộ do admin copy vào máy:

```text
D:\salon-update\
  version.json
  SalonManagerSetup-1.0.2.exe
  release-notes-1.0.2.txt
```

Ngoài ra có thể dùng manifest URL nếu muốn tách quyền update khỏi app và nối về Web Tổng sau này.

Ví dụ:

```text
https://www.ungdungthongminh.shop/api/v1/app-updates/hair-spa-manager/manifest
```

App hiện nên hỗ trợ cả 2 kiểu nguồn:

- thư mục/file local hoặc LAN
- URL manifest từ Web Tổng

## Cách admin quản trị update

1. Build bản installer mới.
2. Chép file installer vào thư mục update chung.
3. Cập nhật `version.json` với version mới, nội dung thông báo và đường dẫn file cài.
4. Nếu cần, cập nhật thêm file ghi chú phát hành.
5. Các máy client mở app sẽ đọc manifest và biết có bản mới.

## App sẽ hiển thị thông báo như thế nào

Đề xuất UI:

1. Banner nhẹ ở đầu app:
   - `Có bản cập nhật 1.0.2`
   - nút `Xem chi tiết`
   - nút `Cập nhật ngay`
   - nút `Để sau`

2. Dialog chi tiết:
   - phiên bản mới
   - mô tả thay đổi
   - bản này có bắt buộc hay không
   - đường dẫn nguồn cài đặt

## Luồng hoạt động

1. App biết đường dẫn thư mục update offline.
2. App đọc `version.json` trong thư mục đó.
3. App so sánh `latestVersion` với version đang chạy.
4. Nếu có bản mới, app hiện thông báo.
5. Khi user bấm cập nhật, app mở file installer `.exe` từ `downloadPath`.
6. User xác nhận cài đặt và đóng app để hoàn tất update.

## Điểm cần chốt trong app ở phase triển khai

- Thêm cấu hình `offlineUpdatePath` trong settings.
- Thêm cờ `autoCheckOfflineUpdate`.
- Thêm service đọc manifest local.
- Thêm banner hoặc dialog thông báo update.
- Thêm nút `Mở bộ cài` thay vì cố tự ghi đè exe đang chạy.

## Vì sao không dùng zip portable cho update

- Khó đảm bảo user giải nén đúng chỗ.
- Khó ghi đè file khi app đang mở.
- Khó tạo trải nghiệm cập nhật rõ ràng cho người dùng cuối.

Vì vậy kênh update chuẩn nên là installer `.exe`.

## Quy ước phát hành

- Tên installer nên chứa version rõ ràng.
- Mỗi lần phát hành chỉ cần sửa một manifest trung tâm.
- Có thể thêm checksum nếu muốn kiểm tra toàn vẹn file.

Ví dụ tên file:

- `SalonManagerSetup-1.0.2.exe`
- `release-notes-1.0.2.txt`
