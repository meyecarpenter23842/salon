# LAN V1: cập nhật và kết nối lại
Desktop và Staff tiếp tục dùng chung SQLite, hai process/cửa sổ như #55. Mỗi UI process kiểm tra data_version và total_changes thay vì dựa vào kích thước/mtime DB/WAL. Provider danh sách, bill, catalog và lịch sử được làm mới khi đổi; không thay selected bill hoặc text controller đang nhập.

API GET /api/staff/v1/changes yêu cầu HTTPS pin và điện thoại approved/canReadSalon, kiểm tra quyền trước và sau probe. Response v1 chỉ epoch/cursor/reset/changed, không có dữ liệu khách, token, giá hay đường dẫn DB. Poll 5 giây khi app foreground; probe một lần, không long-poll/SSE, tối đa 600 request/phút cùng giới hạn 32 request đang chạy. Client giới hạn 2048 byte và 8 giây; không theo redirect.

Cursor báo cần đọc lại toàn bộ vùng đang xem, không phải event nghiệp vụ được phát lại. Mất/trùng/thứ tự cursor và epoch mới không được làm dữ liệu quay về bản cũ. Khi mất Wi-Fi, giữ màn/nháp trong foreground với cảnh báo dữ liệu cũ và khóa ghi. Nối lại kiểm tra quyền rồi lấy watermark; danh sách/detail đọc lại, form đang nhập giữ nội dung nhưng phải đối chiếu/tải lại snapshot trước khi lưu. Background/revoke vẫn tháo route/dialog riêng tư. Không tự replay mutation hay tự thu tiền sau reconnect; commandId còn chờ được giữ trong Keystore, người dùng chọn Kiểm tra kết quả trước khi retry cùng commandId.

CI kiểm chứng SQLite connection riêng (Staff), pinned HTTPS/quyền/revoke trong request, lost/duplicate/out-of-order cursor/restart, giữ input offline và chặn lưu snapshot cũ. Điện thoại thật, sleep/Wi-Fi/firewall trên máy salon vẫn cần ghi bằng chứng ở #111.
