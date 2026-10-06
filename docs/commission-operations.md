# Hoa hồng và chi trả desktop

Quy tắc owner đã chọn ngày 06/10/2026: tỷ lệ riêng của nhân viên × tiền dịch vụ sau giảm giá; chốt theo tháng; chưa tính bán sản phẩm; hoàn/hủy ghi giảm ở tháng sau tháng điều chỉnh.

## Cách dùng
Vào **Nhân viên → Hoa hồng và chi trả**. Tải lại sổ trước đối soát; chọn tháng và nhân viên để xem từng dòng.
- Phát sinh: toàn bộ khoản dịch vụ mới và khoản ghi giảm, gồm các tháng chưa chốt.
- Đã chốt: tổng các tháng đã kết thúc và được Owner xác nhận.
- Đã trả: tổng chứng từ chi trả thực tế.
- Còn phải trả / bù trừ = Đã chốt − Đã trả. Số âm là khoản cần bù trừ vào hoa hồng sau, không tự thu lại tiền nhân viên.

Chốt tháng theo thứ tự từ cũ đến mới; không chốt tháng đang diễn ra, không sửa tháng đã chốt và không tự chi tiền khi chốt.
Chọn nhân viên rồi **Trả / đối chiếu khoản chờ**. Có thể trả từng phần nhưng không vượt số còn phải trả đã chốt. Tiền mặt yêu cầu ca thu ngân đang mở và tạo phiếu chi liên kết; chuyển khoản yêu cầu mã giao dịch, chỉ ghi nhận tiền đã chuyển bên ngoài.

Nếu thao tác chưa xác nhận, giữ mã yêu cầu. Mở lại khoản chờ và đối chiếu cùng mã; cả khi khởi động lại app, mã và số tiền được giữ trong SQLite. **Kiểm tra sổ và bỏ yêu cầu** chỉ bỏ yêu cầu sau khi đọc được database hiện tại; không xóa chứng từ đã ghi. Không tạo lại khoản trả bằng mã khác khi chưa đối chiếu.

Owner/PIN theo cơ chế bảo vệ desktop hiện có; nếu chưa cấu hình PIN thì quyền Owner mặc định được ghi rõ trong audit. Chứng từ trả, phiếu chi liên kết và ledger không được sửa/xóa. Chưa có luồng sửa chứng từ trả nhầm; đối soát kỹ trước khi ghi nhận.

## Cách tính
Phân bổ giảm giá toàn hóa đơn xuống tất cả dòng (gồm sản phẩm) theo thuật toán doanh thu hiện có; chỉ dòng dịch vụ được gán nhân viên tạo hoa hồng. Snapshot nhân viên, tỷ lệ, cơ sở sau giảm giá và số tiền được ghi cùng transaction thanh toán desktop/Staff/LAN. Thiếu người làm thì không có hoa hồng; KPI cố định là tỷ lệ 0 và chưa có công thức KPI.

Tỷ lệ 0–100%, tối đa 2 chữ số thập phân; lưu tỷ lệ snapshot theo basis points. Mỗi dòng làm tròn VND gần nhất (0,5 làm tròn lên). Ví dụ cơ sở 90.000đ và tỷ lệ 10% → 9.000đ. Thay tỷ lệ hồ sơ chỉ áp dụng lần thanh toán tiếp theo; không tính lại dòng đã ghi. Một dòng chỉ có một nhân viên; tách dòng để phân công nhiều người.

Hoàn/hủy toàn hóa đơn giữ nguyên chứng từ phát sinh/chi trả và ghi một dòng âm bằng đúng snapshot ban đầu vào tháng sau tháng điều chỉnh (không sớm hơn tháng sau tháng phát sinh). Không tự giảm két, không tự tạo chứng từ thu lại hoa hồng. Không có hoàn từng phần trong nghiệp vụ hóa đơn hiện tại.

## Dữ liệu cũ và khôi phục
Schema 21 không tạo hoa hồng quá khứ từ tỷ lệ hiện tại, không suy ra tiền đã trả từ báo cáo ước tính. Kỳ đầu có thể là một tháng ghi nhận chưa đủ ngày; kiểm tra phạm vi giao dịch khi chốt. Hóa đơn cũ không có snapshot thì hoàn/hủy cũng không tạo khoản ghi giảm bịa đặt. Profile cũ vẫn hiển thị Hoa hồng ước tính, khác sổ phải trả.

Backup SQLite giữ sổ, chứng từ, audit và yêu cầu chi trả đang chờ. Khôi phục về quá khứ có thể bỏ chứng từ trả tiền đã diễn ra bên ngoài: đối chiếu chứng từ tiền thật, không chi lại chỉ vì bản backup cũ chưa ghi nhận. Tuân thủ [hướng dẫn vận hành](salon-operations.md) trước restore.

Chưa triển khai lương, thuế, chấm công, hoa hồng bán lẻ hay chuyển tiền ngân hàng tự động. Kiểm tra điện thoại thật vẫn chờ thiết bị trong #111; CI không thay thế nghiệm thu thực tế.

Thêm nhân viên hoặc đổi tỷ lệ yêu cầu quyền Owner; audit lưu tỷ lệ cũ/mới và thời điểm có hiệu lực. Tỷ lệ mới chỉ dùng cho lần thanh toán sau đó.

Mã chuyển khoản đã ghi cho cùng nhân viên không được dùng lần nữa (không phân biệt hoa/thường). Nếu mã từ nhiều ngân hàng có thể trùng, nhập thêm tên ngân hàng để chứng từ có tham chiếu duy nhất.
