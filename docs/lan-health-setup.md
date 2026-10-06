# Kết nối điện thoại ngay trong desktop

Mở app desktop đã có license → **Cài đặt → Kết nối điện thoại**.
Chọn mạng máy salon đang dùng cùng điện thoại và bấm **Bật kết nối điện thoại**.
Nếu đã bật bảo vệ Owner, app yêu cầu PIN Owner như các thao tác sửa Cài đặt khác.

App tự tạo TLS identity, lưu cấu hình riêng của máy và mở HTTPS health ngay.
Không cần PowerShell 7, OpenSSL, tự nhập IP hoặc khởi động lại app. Sau khi tự
kiểm tra HTTPS bằng client pin giống Android, app hiển thị **Địa chỉ máy salon**
và **Mã xác minh máy salon** cùng nút sao chép. Nhập hai giá trị này vào điện thoại.

Nếu không thấy mạng, kết nối Wi-Fi hoặc dây mạng rồi bấm **Tìm lại mạng**.
Sau khi đổi mạng/IP, chọn mạng mới và bấm **Áp dụng mạng đã chọn**; app giữ
nguyên certificate/private key để mã xác minh không tự đổi. Cấu hình lần trước,
bao gồm cấu hình tạo bằng script cũ, được tự mở lại khi main desktop khởi động.

## Mạng và tường lửa

Giữ máy salon và app chính mở; thử điện thoại cùng Wi-Fi trước.
Nếu Windows hỏi quyền, cho phép Salon trên mạng riêng. Khi cần chỉnh thủ công
Tường lửa Windows, chỉ cho phép ứng dụng/cổng TCP đã cấu hình (mặc định 8743)
trên Private profile và LocalSubnet. Luồng bật kết nối không tự thay đổi firewall,
router hoặc mở cổng ra Internet. 4G/mạng khác cần mạng riêng/tunnel được thiết lập
riêng. Self-check trên desktop không thay thế kiểm tra qua điện thoại thật.

## Lưu trữ và lifecycle

Identity/cấu hình nằm trong %APPDATA%/HairSpaManager/lan; private key ở thư mục
identity riêng, bỏ quyền kế thừa và cấp quyền cho tài khoản Windows hiện tại
trước khi ghi key. Tạo RSA 2048 và certificate SHA-256 bằng basic_utils trong
isolate; thời hạn một năm, thời gian bắt đầu lùi 5 phút. Điện thoại tin đúng
certificate DER qua pin, không cài certificate vào trust store và không dùng
trust-all. Cấu hình JSON chỉ trỏ đường dẫn, không chứa private key.

Setup lock OS + guard trong process bảo vệ việc tạo/lưu identity; config được
ghi file tạm rồi rename sau khi PEM/key đã được kiểm tra. Retry/đổi IP không
xoay identity. Identity lỗi không bị tự ghi đè. Gia hạn identity khi hết hạn là
thao tác bảo trì riêng cần cập nhật pin điện thoại, không diễn ra âm thầm.

Chỉ main sau license có callback bật và sở hữu host; Staff/Android không có.
Controller serialize thao tác, dừng khi main dispose/mất license/thoát; lỗi bind,
setup hoặc TLS health giữ desktop dùng được và không hiển thị giá trị stale.
Backend.lock được giải phóng bằng đóng OS handle; không xóa lock đang sống.

Health không đọc dữ liệu nghiệp vụ. Sau health, chủ salon duyệt từng điện thoại và cấp quyền xem/vai trò ghi; khách hàng, lịch, bill và checkout dùng SQLite của desktop qua API HTTPS. Xem [hướng dẫn vận hành](salon-operations.md) và [mẫu nghiệm thu](salon-qa-acceptance.md).



## QR và đổi mạng (#110)

Khi backend HTTPS sẵn sàng, desktop hiển thị QR gồm đúng kind/version/url/pin. QR không có mã ghép, token hoặc quyền. Android: Quét QR máy salon → đối chiếu địa chỉ/mã trên desktop → Dùng thông tin này → Kiểm tra kết nối → yêu cầu truy cập → chủ salon duyệt. Camera dùng mobile_scanner 7.4.2 với ML Kit đóng gói; từ chối camera thì dán thông tin QR hoặc nhập thủ công. Không cần tải mô hình qua Internet khi quét. [Tài liệu thư viện](https://pub.dev/packages/mobile_scanner).

Hai máy phải cùng mạng LAN, kể cả PC nối dây và điện thoại Wi-Fi. Tránh mạng khách/AP isolation. Windows Firewall: cho phép app salon trên hồ sơ Riêng tư và cổng TCP trong địa chỉ hiện tại (mặc định 8743); kiểm tra đúng app/port và hồ sơ mạng. Không mở cổng router, mạng Công cộng, hay tắt tường lửa; app chỉ hướng dẫn, không tự sửa firewall.

IP desktop đổi: Tìm lại mạng → chọn Wi-Fi/dây mạng → Áp dụng mạng đã chọn → quét QR mới → kiểm tra kết nối. Chứng chỉ và danh tính đã duyệt được giữ nếu vẫn cùng máy salon. Nếu chứng chỉ đổi, đối chiếu lại và ghép quyền lại; QR khác mã bị chặn khi còn lệnh chưa rõ kết quả. Không tự phát lại lệnh cũ.

Trạng thái foreground mất Wi-Fi giữ màn hình và nhập nháp nhưng khóa ghi. Kết nối lại kiểm tra quyền + watermark trước, tải lại dữ liệu xem; biểu mẫu cũ giữ nội dung và yêu cầu tải snapshot mới trước khi lưu. Background/thu hồi quyền vẫn đóng dữ liệu riêng tư. Restart backend đổi epoch; dữ liệu cũ được resync, kết quả lệnh chưa rõ chỉ được kiểm tra khi người dùng bấm.

Camera thật, Wi-Fi thật, sleep/restart và firewall của máy salon chưa được xác nhận bằng CI; xem checklist #111.
