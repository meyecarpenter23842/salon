# Công nợ nhà cung cấp — #138

Schema 26 bổ sung sổ phải trả nhà cung cấp và tái sử dụng danh mục NCC/phiếu
nhập của #107. Sổ này không tạo công nợ khách hàng, không tính thuế, chiết khấu,
giá vốn hay lợi nhuận.

## Nguồn nghĩa vụ

Từ thời điểm schema 26 hoạt động, khi một phiếu nhập mới được **ghi kho** và có
nhà cung cấp cùng tổng tiền lớn hơn 0, nghĩa vụ phải trả được tạo trong **cùng
SQLite transaction** với biến động tồn kho và trạng thái posted. Nếu ghi công nợ
thất bại thì toàn bộ ghi kho rollback. Phiếu nhập không có NCC hoặc tổng bằng 0
không sinh nợ.

Phiếu đã posted từ trước schema 26 không được backfill tự động. Owner đưa nợ cũ
vào bằng **số dư đầu kỳ**, bắt buộc NCC, ngày, số tiền và lý do. Việc nâng schema,
backup/restore hoặc retry một phiếu cũ không được suy ra rằng phiếu đó còn nợ hay
đã trả.

## Thanh toán và phân bổ

Mỗi chứng từ thanh toán có một hoặc nhiều phân bổ vào nghĩa vụ cụ thể. Tổng
chứng từ chính là tổng phân bổ. Mỗi phân bổ được kiểm tra trên số dư mới nhất
trong transaction; không cho trả vượt nợ và không hỗ trợ ứng trước trong lô này.

Tiền mặt chỉ được ghi khi có ca thu ngân đang mở. Cash movement và receipt thanh
toán được ghi cùng transaction; retry đúng requestId không tạo movement thứ hai.
Chuyển khoản chỉ ghi nhận giao dịch đã thực hiện bên ngoài và bắt buộc mã tham
chiếu. Mã tham chiếu mới không được trùng với chứng từ NCC, chi phí, lương hoặc
hoa hồng đã có.

Request tiền dùng requestId + signature + pending/replay. Kết quả không rõ sau
restart phải tra đúng requestId trước khi thực hiện lại. Cùng requestId nhưng
payload khác bị từ chối. RequestId thanh toán NCC và chi phí cũng không được dùng
lẫn nhau.

## Đảo và hủy phiếu nhập

Chứng từ tiền đã ghi là bất biến. Đảo thanh toán tạo receipt mới và phân bổ âm;
đảo tiền mặt tạo movement **in** ở ca đang mở hiện tại, không sửa ca lịch sử.
Đảo chuyển khoản cần mã đối soát mới.

Phiếu nhập có phân bổ thanh toán ròng khác 0 không được hủy. Owner phải đảo/hoàn
hết chứng từ tiền trước. Khi số đã phân bổ về 0, hủy PN sẽ đảo nghĩa vụ công nợ
trong cùng transaction với việc đảo tồn kho. PN cũ không có nghĩa vụ schema 26
vẫn hủy theo quy tắc kho cũ và không bị tạo công nợ giả.

Số dư đầu kỳ sửa sai bằng chứng từ đảo có lý do và chỉ được đảo khi chưa còn
phân bổ thanh toán. Nghĩa vụ, receipt, allocation và event journal đều bất biến.

## Quyền và vận hành

Đọc/ghi sổ NCC yêu cầu Owner/PIN khi bảo vệ đã được cấu hình. NCC ngừng dùng vẫn
giữ snapshot lịch sử và vẫn có thể thanh toán nghĩa vụ đã tồn tại; chỉ việc tạo
nguồn nợ mới yêu cầu NCC đang hoạt động.

Backup schema 26 phải có đủ obligation, payment, allocation và event journal.
Migration idempotent/dở dang chỉ tạo cấu trúc còn thiếu; tuyệt đối không backfill
sự kiện tài chính từ ghi chú, cash movement hay PN cũ.

UI, PDF, lọc/đối soát màn hình và QA viewport tiếp tục ở #139.
