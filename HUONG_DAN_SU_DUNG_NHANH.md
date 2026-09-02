# Hướng Dẫn Sử Dụng Nhanh

Tài liệu này dùng để preview nhanh bản hiện tại của Quản Lý Salon Tóc và kiểm tra các điểm mới trước khi gửi tiếp cho GPT để dàn lại giao diện/tài liệu đẹp hơn.

## 1. Mở app

Khi mở ứng dụng, cần kiểm tra:

- App vào thẳng giao diện chính, không treo lúc khởi động.
- Nếu bootstrap lỗi, app không được tắt im lặng.
- Thay vào đó phải hiện màn hình lỗi khởi động với các nội dung:
  - Tiêu đề: `Không thể khởi động Quản Lý Salon Tóc`
  - Mô tả lỗi khởi tạo dữ liệu cục bộ
  - Gợi ý vị trí database mặc định: `.salon_manager/salon_manager.db`
  - Chi tiết lỗi kỹ thuật để copy khi cần debug

## 2. Kiểm tra màn hình Overview

Vào menu `Overview` và kiểm tra:

- Nếu đang chạy backend `SQLite runtime`, hero đầu trang phải có khối thông báo `Overview đang đọc dữ liệu runtime`.
- Nội dung phải nói rõ KPI, khách nổi bật, quick checkout và biểu đồ doanh thu đang được tổng hợp từ SQLite cục bộ.
- Nếu ép app sang fake backend, hero đầu trang mới hiển thị cảnh báo `Overview đang dùng dữ liệu demo`.
- Có badge nguồn chạy như:
  - `SQLite runtime` nếu đang dùng backend thật
  - `Fake runtime` nếu đang dùng backend giả

Mục tiêu của phần này là xác nhận Overview đã đọc dữ liệu thật và chỉ hiện cảnh báo demo khi đúng backend giả.

## 3. Kiểm tra màn hình Reports

Vào menu `Báo cáo` và kiểm tra:

- Nếu đang chạy backend `SQLite runtime`, hero đầu trang **không** hiển thị cảnh báo demo.
- Số liệu doanh thu, top dịch vụ, top nhân sự, xu hướng doanh thu và insights đang được tổng hợp từ SQLite cục bộ.
- Nếu ép app sang fake backend, hero đầu trang mới hiển thị cảnh báo `Báo cáo đang dùng dữ liệu demo`.
- Badge nguồn chạy:
  - `Runtime: SQLite` khi dùng backend thật — **không có** badge `Demo metrics`
  - `Runtime: Fake` kèm badge `Demo metrics` khi dùng backend giả

Mục tiêu của phần này là xác nhận Reports đã đọc dữ liệu thật và chỉ hiện cảnh báo demo khi đúng backend giả.

## 4. Cách ép lỗi startup để xem màn hình fallback

Làm theo các bước sau:

1. Đóng ứng dụng.
2. Đi tới thư mục chạy app.
3. Tạo một file thường có tên `.salon_manager`.
4. Mở lại ứng dụng.

Kết quả mong đợi:

- App không tạo được thư mục dữ liệu.
- App rơi vào màn hình fallback khởi động.
- Có thể kiểm tra trực tiếp giao diện lỗi thay vì phải sửa code.

Sau khi test xong:

1. Xóa file `.salon_manager`.
2. Mở lại app để hệ thống tạo đúng thư mục dữ liệu.

## 5. Checklist cực ngắn

- Mở app bình thường
- Overview hiển thị đúng thông báo theo backend đang chạy
- Reports hiển thị số liệu thật khi SQLite runtime, chỉ hiện cảnh báo demo khi fake
- Tạo lịch hẹn → checkout hóa đơn → kiểm tra Overview KPI và Reports top service cập nhật đúng
- Ép lỗi startup và thấy màn hình fallback
- Trả app về trạng thái chạy bình thường sau khi test

## 6. Gợi ý gửi tiếp cho GPT

Khi cần nhờ GPT dàn lại tài liệu hoặc thiết kế UI preview đẹp hơn, có thể đưa file này kèm yêu cầu như sau:

`Hãy chuyển tài liệu Markdown này thành bản hướng dẫn sử dụng đẹp, ngắn, dễ đọc, chia section rõ ràng, phù hợp cho demo nội bộ phần mềm quản lý salon tóc trên Windows.`