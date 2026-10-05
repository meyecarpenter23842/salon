# Android ghi dữ liệu qua desktop

Tiếp tục roadmap #86 / Batch 2 #89. Desktop giữ SQLite; Android chỉ gửi thao tác khi có kết nối HTTPS đã xác minh và quyền thiết bị.

## Cấp quyền

Desktop → Cài đặt → Kết nối điện thoại: duyệt điện thoại, bật “Cho xem dữ liệu salon”, chọn quyền:
- Chỉ xem: không ghi.
- Nhân viên: thêm/sửa khách, lịch, trạng thái; tạo và sửa bill, thêm dịch vụ/sản phẩm, số lượng và nhân viên.
- Thu ngân: thêm phân bổ thanh toán và checkout.
- Chủ salon: thêm sửa đơn giá và giảm giá bill. Quyền này phải được cấp rõ ràng trên desktop; không dùng lại phiên PIN desktop.

## Android

Dữ liệu khách/lịch có nút sửa trong chi tiết và nút thêm trên trang chính. Các danh sách chọn khách/dịch vụ/sản phẩm/nhân viên phân trang 25 mục, tìm theo tên; không tải toàn bộ danh mục về điện thoại. Lịch dùng YYYY-MM-DD và HH:mm, các quy tắc trùng lịch/nhân viên/đã thanh toán của desktop.

“Bill đang làm” và “Tạo bill khách vãng lai” chọn chính xác session. Có thể chọn khách, thêm dịch vụ/sản phẩm, thay số lượng, bỏ dòng, gán nhân viên; chủ salon chỉnh đơn giá/giảm bill. Thu ngân nhập số tiền vào một hoặc nhiều phương thức (tổng phải bằng bill), lưu phân bổ rồi xác nhận checkout. Kết quả thanh toán là ID hóa đơn lưu trữ, không phải bill rỗng sau reset.

## Mất kết nối và xung đột

Mọi thao tác mang mã riêng, epoch desktop và revision resource; nghiệp vụ, revision, audit và kết quả cùng SQL transaction. Gửi lại đúng mã/payload trả lại kết quả cũ. Hai điện thoại dùng revision cũ không được ghi đè. Các thao tác ghi repository desktop đọc/kiểm tra/ghi cùng transaction với mobile, gồm kiểm tra hóa đơn lịch hẹn đã thanh toán.

Điện thoại lưu đúng một thao tác chưa rõ kết quả trong Android Keystore trước khi gửi, khóa thao tác mới và không tự gửi khi online lại. “Kiểm tra kết quả” tra nhật ký thuộc thiết bị. Nếu chưa có kết quả và epoch còn nguyên, người dùng có thể gửi lại đúng lệnh cũ; nếu epoch đã đổi, chỉ sau kiểm tra không có kết quả mới cho bỏ lệnh cũ và tải dữ liệu mới. Không quên/ghép lại điện thoại trong khi thao tác chưa rõ kết quả. Thất bại lưu/xóa Keystore giữ khóa an toàn.

Không lưu danh sách khách/lịch/hóa đơn vào DB hoặc preferences trên Android. Form/dữ liệu bị bỏ khi app về nền, mất kết nối, thu hồi quyền đọc hoặc role đổi. Thao tác chưa rõ kết quả vẫn được giữ mã hóa để đối chiếu. Không mở màn hình chứa dữ liệu qua route ngoài phạm vi quyền.

## Kiểm tra

CI kiểm tra SQLite nghiệp vụ và journal, checkout/stock/metrics/split payments/retry/restart/rollback, quyền và xung đột; HTTPS TLS pin/token/result theo thiết bị; controller mất phản hồi và lưu an toàn; widget phone hẹp và xác nhận checkout. Full Linux/Windows regression, Windows release/Staff/installer/updater/NSIS, Android APK đúng head.

**Chưa xác nhận trên điện thoại thật.** Chưa phát hành bộ cài mới, chưa chạy migration production và chưa hoàn thiện truy cập khác Wi-Fi/4G. Không dùng CI/emulator để thay bằng chứng đó. Không chạy build/test app local hoặc tạo clone/worktree.
