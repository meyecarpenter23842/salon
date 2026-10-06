# Mobile navigation — #108

Phần 4A tách ghép máy khỏi giao diện vận hành: 5 mục Hôm nay/Lịch hẹn/Khách hàng/Hóa đơn/Thêm, danh sách và hồ sơ theo route. Danh sách giữ query/ngày/scroll trong phiên; refresh sau sửa giữ các trang đã tải. Back của Android đi qua navigator riêng. Không persist dữ liệu nghiệp vụ trên Android.

Access panel vẫn kiểm tra pairing/permission/foreground mỗi lần; workspace và tất cả route con bị gỡ khi mất mạng/quyền/foreground. Token, Keystore và command controller không đổi. Bill hiện có mở route riêng; thiết kế bill tiếp tục #109.

Phần 4B sẽ thay form khách/lịch bằng field validation, bộ chọn có tìm kiếm, date/time picker, xác nhận bỏ thay đổi và bổ sung render CI để review. Chưa kiểm tra điện thoại thật; không build/test app local.
