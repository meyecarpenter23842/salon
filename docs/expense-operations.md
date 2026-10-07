# Sổ chi phí vận hành — #137

Schema 25 bổ sung sổ chi phí vận hành tách biệt với chứng từ đã thanh toán.
Khoản chi phí là nghĩa vụ; tiền đã trả là chứng từ riêng. Một khoản có thể ở trạng
thái chưa trả, trả một phần hoặc đã trả. Không suy chi phí từ cash_movements,
phiếu nhập kho, lương hoặc hoa hồng cũ.

Danh mục khoản chi có thêm, đổi tên, ngừng dùng và bật lại. Chứng từ chi phí giữ
snapshot tên danh mục tại thời điểm lập, nên đổi tên sau đó không sửa lịch sử.
Khoản chi và chứng từ tiền đã ghi không sửa/xóa. Sai thì đảo chứng từ thanh toán
trước, sau đó đảo khoản chi với lý do; lịch sử gốc vẫn còn.

Tiền mặt chỉ được ghi khi có ca thu ngân đang mở và tạo đúng một cash_movement
trong cùng transaction. Đảo tiền mặt tạo movement thu lại quỹ. Chuyển khoản chỉ
ghi nhận giao dịch đã thực hiện bên ngoài, bắt buộc mã tham chiếu; ứng dụng không
tự chuyển tiền. Mã chuyển khoản được đối chiếu với sổ chi phí, hoa hồng và bảng
lương để tránh dùng lại cùng bằng chứng.

Mỗi thay đổi tiền dùng requestId + signature. Trước khi thay đổi tiền, yêu cầu
được lưu vào pending; transaction thành công ghi receipt và xóa pending cùng lúc.
Nếu ứng dụng mất kết quả, phải đối chiếu receipt bằng đúng requestId trước khi
thực hiện lại. Exact replay trả về chứng từ cũ; cùng requestId nhưng payload khác
bị từ chối. Lỗi validation/rollback đã biết sẽ dọn pending nếu chưa có receipt.

Owner/PIN bảo vệ đọc và ghi theo cơ chế bảo mật hiện có. Audit thành công được ghi
cùng transaction nghiệp vụ. Backup schema 25 phải chứa đủ danh mục, nghĩa vụ,
chứng từ thanh toán và event journal; migration không backfill tiền hoặc nghĩa vụ
từ dữ liệu cũ.

Lô này không tính giá vốn, thuế hay lợi nhuận; phiếu nhập/NCC vẫn thuộc domain kho.
Công nợ nhà cung cấp tiếp tục #138 và UI/PDF/đối soát tổng hợp tiếp tục #139.
