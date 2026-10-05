# Xem dữ liệu salon trên Android

Theo dõi #86, #89; nối tiếp ghép quyền #100. Không thay schema hoặc version nguồn.

## Sử dụng

1. Giữ app desktop chính có license mở; bật kết nối HTTPS và ghép quyền theo [phone-pairing.md](phone-pairing.md).
2. Desktop: Cài đặt → Kết nối điện thoại → tìm đúng điện thoại đã duyệt → bật **Cho xem dữ liệu salon**. Luồng dùng guard Owner/audit settings hiện có. Điện thoại đã duyệt ở bản trước chỉ giữ quyền kết nối cho tới khi chủ salon bật quyền xem.
3. Android kiểm tra trạng thái mỗi 5 giây khi mở app. Trang chính hiện trạng thái kết nối cùng ba mục:
   - **Khách hàng**: tìm tên/số điện thoại, danh sách và chi tiết hồ sơ.
   - **Hóa đơn**: chỉ hóa đơn đã thanh toán, mới nhất trước; chi tiết dòng, giảm giá, tổng tiền, phân bổ phương thức thanh toán và trạng thái hoàn tiền/hủy. Không đưa bill đang làm của desktop lên điện thoại.
   - **Lịch hẹn**: mặc định hôm nay trên máy salon, chọn ngày; xem khách, dịch vụ, nhân viên, thời gian và trạng thái.
4. Bấm mục để xem chi tiết, Trang tiếp để xem trang kế, Tải lại dữ liệu khi desktop thay đổi. Chưa có tự cập nhật qua event stream.
5. Desktop có thể tắt quyền xem hoặc thu hồi toàn bộ quyền của từng điện thoại. API chặn trước/sau đọc, kể cả lúc yêu cầu đang chờ dữ liệu; Android bỏ dữ liệu đang giữ sau lần kiểm tra trạng thái tiếp theo hoặc ngay khi API trả lỗi quyền.

## Hợp đồng đọc hiện tại

GET /api/staff/v1/customers, /invoices, /appointments cần Bearer token đã duyệt **và** canReadSalon. Các HTTP verb ghi không được hỗ trợ. Health không đọc SQLite.

Query danh sách: limit (1–25, mặc định 25), offset (0–100000), q (tối đa 80 ký tự, chỉ khách hàng), day (YYYY-MM-DD, chỉ lịch hẹn, mặc định ngày desktop). Query chi tiết dùng id; không phối hợp với q/day/offset khác 0. Các key không biết, lặp key, ngày không tồn tại hoặc page quá giới hạn bị từ chối. SQL dùng tham số; tìm kiếm %/_ là ký tự literal.

Response v1 gồm records {id,title,subtitle,fields}, salonDate, nextOffset. Đây là projection trình bày, không gửi raw database rows hay cấu hình máy. Ngày/giờ hiển thị là giờ máy salon; không diễn giải lại thành múi giờ điện thoại. Money dùng domain integer VND, hiển thị vi_VN. Note/profile dài trên 1000 ký tự được rút gọn có dấu “…”. Invoice/appointment trên 200 dòng hoặc response trên 256 KiB trả unavailable, không báo tổng tiền của một danh sách dòng bị cắt âm thầm.

Repository đọc trong transaction snapshot từ SQLite desktop, tái sử dụng CustomerMapper/AppointmentMapper/AppointmentServiceMapper/InvoiceDraftMapper/InvoiceMapper và InvoiceDraft totals/payment allocations. Không gọi seed, đồng bộ nhân viên, tạo draft hoặc ghi nghiệp vụ. Không phụ thuộc bill desktop đang chọn.

Pagination offset có thứ tự cố định, nhưng các trang tải ở thời điểm khác nhau có thể thay đổi nếu desktop thêm/xóa dữ liệu; tải lại từ đầu để xem mới nhất. Chưa có revision/event cursor hoặc đồng bộ offline.

HTTPS pin, không redirect, timeout client 8 giây; server read 5 giây; no-store. Status/bootstrap/read chung 240 lần/phút, tối đa 32 request đồng thời. Android chỉ giữ dữ liệu trong bộ nhớ, bỏ khi vào nền, mất kết nối hoặc mất quyền; không mở business SQLite, không lưu PII vào preferences. URL/pin và token Keystore giữ cơ chế ghép quyền hiện có.

## Kiểm tra trên điện thoại thật — còn mở

CI có kiểm tra SQLite không ghi, truy vấn/phân trang/chi tiết, HTTPS thật về quyền/pin/thu hồi khi đang đọc, UI màn hình hẹp và vòng đời. CI hoặc emulator không chứng minh điện thoại thật.

Cần thử điện thoại thật cùng Wi-Fi: ghép và bật quyền xem; so sánh ba danh sách/chi tiết với desktop; tìm tên/số điện thoại; chọn ngày; hóa đơn giảm giá/thanh toán nhiều phương thức/hoàn tiền; desktop sửa và Android tải lại; tắt quyền xem/thu hồi khi mở chi tiết; hai điện thoại có quyền khác nhau; ngắt Wi-Fi và resume; restart hai app. Chưa đánh dấu gate này hoàn tất.

Thêm/sửa dữ liệu, xử lý sửa đồng thời, QR và truy cập khác Wi-Fi/4G là các phần sau.
