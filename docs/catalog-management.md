
# Danh mục và đơn vị tính — lô #105

Sản phẩm, Dịch vụ và Kho hàng có tab **Thiết lập**. Danh mục được dùng chung: nhóm sản phẩm, thương hiệu, nhóm dịch vụ, đơn vị tính. Thêm/đổi tên/ngừng sử dụng/bật lại; tìm tên và bật “Hiện mục ngừng sử dụng” để quản lý các mục đã ẩn.

Đơn vị tính là đơn vị đếm (chai, hộp, cái...). Quy cách 500 ml vẫn là trường riêng, không tự đổi tồn sang ml. Sản phẩm cũ chưa biết đơn vị hiển thị chưa thiết lập; chỉnh sản phẩm để chọn đúng đơn vị. Số lượng tồn tiếp tục là số nguyên.

Schema 18 thêm ID liên kết và trạng thái danh mục. Đổi tên cập nhật bản ghi sản phẩm/dịch vụ hiện hành, không sửa snapshot hóa đơn, lịch hoặc biến động kho. Ngừng dùng không xóa liên kết: bản ghi cũ vẫn mở/lưu được, bản ghi mới không được gán danh mục đã ngừng. Mục mặc định được lưu thật nên đổi tên/ngừng dùng không bị sinh lại sau restart.

Vai trò/chức danh nhân viên hiện thuộc employees.role và bộ chọn ở employees_page.dart; không chung với PhoneWriteRole là quyền truy cập API. Quản trị danh mục nhân sự tiếp tục #112.

Kiểm chứng migration, ID, rename/archive/restart và giao diện trong CI; không chạy migration dữ liệu production hoặc build/test app local. Phiếu nhập/xuất âm tiếp tục #106/#107; UX mobile tiếp tục #108/#109.
