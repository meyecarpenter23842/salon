# Ghép quyền điện thoại với máy salon

Theo dõi: #86, #89. Bước này triển khai quyền thiết bị và màn hình chính Android.
Có quyền xem riêng cho khách hàng/hóa đơn/lịch hẹn; xem [phone-data-read.md](phone-data-read.md).
Phân vai nghiệp vụ, ghi dữ liệu và xử lý sửa đồng thời còn ở bước sau.

1. Giữ app chính trên máy salon mở, kết nối hai máy cùng mạng.
2. Desktop: Cài đặt → Kết nối điện thoại → bật kết nối, sao chép địa chỉ và mã xác minh.
3. Android: nhập hai thông tin đó và kiểm tra kết nối.
4. Desktop: Tạo mã ghép điện thoại (8 chữ số, dùng một lần, hạn 5 phút).
5. Android: nhập tên điện thoại và mã ghép → Yêu cầu truy cập.
6. Desktop: đối chiếu tên và mã thiết bị 8 ký tự trên hai màn hình, rồi Duyệt hoặc Từ chối.
7. Android tự kiểm tra mỗi 5 giây khi mở app, vào Trang chính sau khi bootstrap được backend cho phép.
8. Desktop: Thu hồi quyền từng điện thoại. API từ chối ngay sau khi thu hồi được lưu;
   Android cập nhật sau lần kiểm tra tiếp theo (5 giây + thời gian mạng;
   mỗi request timeout 8 giây, lần vào Trang chính có thêm bootstrap).

Quyền đã duyệt và thu hồi tồn tại qua desktop restart. Yêu cầu đang chờ hết hạn sau 5 phút
hoặc khi host khởi động lại. Mã ghép mới thay mã cũ, dừng host hủy mã đang mở.
Muốn ghép lại điện thoại bị từ chối/thu hồi/hết hạn, xin mã mới và gửi yêu cầu mới.
Quên quyền trên Android chỉ xóa khóa ở điện thoại; để xóa quyền server hãy Thu hồi trên desktop.

## Boundary

HTTPS giữ nguyên certificate pin của cấu hình kết nối. Phone tạo token ngẫu nhiên 256 bit,
lưu trước khi gửi để có thể thử lại nếu mất phản hồi. Token ràng buộc với certificate pin,
được mã hóa AES-GCM bằng Android Keystore, không ghi vào SharedPreferences dạng plaintext
hoặc backup Android. [Android Keystore](https://developer.android.com/privacy-and-security/keystore)
và [AES-GCM KeyGenParameterSpec](https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec)
mô tả cơ chế khóa dùng ở đây. Không có dependency mới.

Desktop chỉ lưu SHA-256 token, tên, trạng thái và thời điểm trong APPDATA/HairSpaManager/lan/devices.json.
Thay đổi serialize, ghi file tạm rồi rename trước khi báo thành công; lỗi lưu không cấp quyền.
Store hỏng làm startup thất bại an toàn, không tự xóa/reset. Giới hạn 100 thiết bị bao gồm lịch sử.
Không thay schema/database nghiệp vụ. Backend OS lock giữ owner duy nhất.

POST /api/staff/v1/pair/exchange nhận đúng code/name/token, giới hạn 4096 byte,
timeout body 5 giây và 20 lần/phút trên cả host. GET /pair/status chỉ trả trạng thái
của Bearer token đó. GET /bootstrap cần token đã duyệt, có permission connection và
thêm customers.read/invoices.read/appointments.read nếu chủ salon đã bật quyền xem.
Status/bootstrap/read giới hạn chung 240 lần/phút; tối đa 32 device requests đồng thời.
Không có admin routes qua HTTP, không có role do client gửi, không có quyền Owner từ desktop session.
Thao tác tạo mã/duyệt/từ chối/thu hồi/bật hoặc tắt quyền xem dùng guard Owner và audit settings hiện có,
chỉ chứa ID hash, không token/PIN/mã ghép. Health anonymous vẫn đúng payload cũ và không đọc SQLite.

Khi mất Wi-Fi, app hiển thị mất kết nối; resume/restart xác minh lại server. Không queue ghi offline.
Tên thiết bị không chứng minh danh tính con người: chủ salon phải đối chiếu mã thiết bị.

## Gate kiểm tra điện thoại thật

CI kiểm thử registry, HTTPS với certificate thật, desktop panel, Android shell và build APK.
CI/emulator không chứng minh điện thoại thật. Chưa xác nhận gate điện thoại thật của #89.
Trên điện thoại thật cần kiểm tra: gửi yêu cầu → duyệt → Trang chính; hai điện thoại độc lập;
từ chối/hết hạn; revoke ngay khi online; mất Wi-Fi/resume; desktop restart giữ quyền;
đổi IP cùng certificate; pin sai; quyền lưu Android và khả năng khôi phục sau restart.
Không chạy build/test app trên máy owner trong quy trình này. Remote Wi-Fi/4G và QR còn ở bước sau.
