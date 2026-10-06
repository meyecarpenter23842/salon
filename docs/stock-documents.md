# Chứng từ kho — #107, phần 3A

Schema 20 thêm nhà cung cấp, phiếu và dòng phiếu. Phiếu PN/PX/KK có mã SQLite duy nhất, ngày, người lập, chứng từ ngoài, ghi chú, snapshot NCC/tên sản phẩm/đơn vị/giá nhập và tổng nguyên. Nháp không thay tồn; xác nhận ghi toàn bộ tồn, movement và audit trong một transaction. Tạo nháp cùng id và dữ liệu, xác nhận lại, hủy lại cùng lý do đều không ghi lặp. Sửa nháp yêu cầu revision hiện tại.

Owner dùng cơ chế PIN/phiên hiện có; chưa cấu hình PIN thì áp dụng Owner mặc định như phần bảo vệ hiện tại. API điện thoại không có lệnh tạo/xác nhận/hủy chứng từ kho trong lô này. Mọi mutation nhà cung cấp/phiếu qua repository đều kiểm tra Owner trước transaction. Audit thành công nằm cùng transaction nghiệp vụ; từ chối quyền được ghi audit riêng.

Phiếu đã ghi kho không sửa/xóa header hoặc dòng. Hủy cần lý do, ghi bút toán đảo theo delta gốc trên tồn hiện tại, được phép âm. Kiểm kê dùng tồn thực tế không âm, phiếu nhập/xuất dùng số lượng dương. Ngừng NCC/sản phẩm hoặc đổi đơn vị sau lưu nháp buộc người dùng sửa nháp trước xác nhận.

Giá nhập chỉ nằm trong chứng từ; không đổi giá bán, ghi chi tiền/công nợ hay giá vốn bình quân. Hoàn tiền hóa đơn giữ nghiệp vụ tài chính hiện có. Lịch sử kho trước schema 20 giữ nguyên delta/trước/sau/note/ngày và đánh dấu legacy, không bịa chứng từ, NCC hoặc giá.

Phần 3B tiếp tục giao diện 5 tab, lập/chỉnh nháp, xác nhận/hủy, quản trị NCC, tra cứu/đối chiếu và bản in. Chưa chạy migration production hoặc thử điện thoại thật.
