# Chức danh nhân viên (#135)

Trong **Nhân viên → Thiết lập**, thêm/đổi tên chức danh hoặc ngừng sử dụng/bật lại.
Hồ sơ chọn chức danh từ danh mục và có nút thêm nhanh; bộ lọc dùng các chức danh
thực tế của nhân viên, kể cả chức danh đã ngừng dùng.

Đổi tên cập nhật hồ sơ hiện tại qua ID liên kết ổn định. Không sửa bản sao lịch sử
chấm công, bảng lương, hoa hồng, hóa đơn hoặc lịch hẹn đã ghi. Ngừng dùng không xóa
chức danh của nhân viên cũ, nhưng không cho gán vào nhân viên mới/chuyển từ mục khác.
Muốn dùng lại hãy bật lại. Tên trùng sau chuẩn hóa khoảng trắng và hoa/thường không tạo mục mới.

Schema 24 nhập các chức danh hiện có, giữ nguyên text, ID và thời điểm cập nhật
nhân viên; không thay giá trị lạ bằng chức danh mặc định. Hồ sơ cũ chưa có chức danh
được giữ trống khi migration, cần chọn danh mục khi bổ sung chức danh.
Migration có thể chạy lại; không suy luận lương, tỷ lệ hoa hồng hoặc quyền truy cập.

Quản lý và đổi chức danh cần quyền Owner nếu máy đã đặt PIN; các thay đổi có audit
trước/sau. Thiết lập PIN Owner trong Cài đặt nếu chưa có. Chức danh “Quản lý”, “Owner”
hay “Chủ salon” chỉ là vị trí công việc, không tạo phiên Owner và không cấp quyền điện thoại.
Quyền điện thoại và PIN Owner tiếp tục được quản lý ở phần bảo mật hiện có.

Nếu hồ sơ hoặc tên/chức danh đã thay đổi trong lúc biểu mẫu mở, tải lại biểu mẫu thay vì tự tạo
lại tên cũ. Các client cũ truyền tên không có ID tiếp tục được hỗ trợ qua thao tác
gán chức danh có quyền Owner; tên được nhập vào cùng danh mục, kiểm tra trạng thái ngừng dùng.

Backup trước schema24 được nâng cấp khi phục hồi. Backup schema24 phải có cột liên
kết chức danh; phục hồi giữ cả trạng thái ngừng dùng, danh mục và liên kết hồ sơ.
Nguồn/fixture được kiểm tra trên CI; không dùng DB salon để chạy test/migration thử.
Bộ cài trên máy cần build riêng để nhận nguồn mới. #111 nghiệm thu thiết bị thật vẫn chờ.
