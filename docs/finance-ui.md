# Chi phí & công nợ — #139

Mở **Chi phí & công nợ** trong menu Theo dõi. Owner/PIN bảo vệ cả đọc và ghi;
khóa/hết phiên/chuyển nền tháo dữ liệu và các dialog. Đọc sổ và PDF từ một snapshot
SQLite transaction; tải lại để xem thay đổi mới. Trang danh sách có 20 khoản,
tổng/PDF dùng toàn bộ kết quả lọc, không chỉ trang đang thấy.

## Khởi đầu

- Thêm loại chi phí trước khi lập khoản chi. Đổi tên/ngừng dùng giữ tên lịch sử;
  bật lại loại cũ thay vì tạo trùng. Lập khoản chi **chưa chi tiền**.
- Nợ cũ đối chiếu ngoài ứng dụng rồi nhập **Số dư đầu kỳ** với NCC/ngày/lý do.
  PN trước schema26 không backfill. PN mới có NCC/tổng >0 sinh nợ khi ghi kho;
  không nhập lại PN đó thành số dư đầu kỳ. Quản lý NCC/PN tại Kho hàng hiện có.
- NCC ngừng dùng vẫn có lịch sử và vẫn trả nợ cũ; không lập nợ mới cho NCC đó.

## Trả một phần, phân bổ và hoàn tiền

Mở Ghi trả/phân bổ: hiển thị số còn phải trả và từng phân bổ. NCC có thể phân bổ
một chứng từ cho nhiều khoản cùng NCC; khoản chi phí thanh toán riêng từng khoản.
Không trả vượt/ứng trước. Form đọc số dư mới lúc mở; transaction kiểm tra số dư
mới nhất khi ghi. Nếu số dư thay đổi, đóng editor, tải lại và đối chiếu tiền thật.

Cash yêu cầu ca đang mở; receipt tạo đúng một cash movement trong cùng transaction.
Không ghi thêm thu/chi ca tay cho giao dịch đó. Ngoài ca dùng chuyển khoản đã
thực hiện bên ngoài, bắt buộc tham chiếu mới không trùng NCC/chi phí/lương/hoa hồng.
Checkbox xác nhận tiền thật và phân bổ trước ghi. Ứng dụng không chuyển tiền.

Chi tiết/lịch sử giữ requestId, gốc/đảo, mã cash movement và toàn bộ phân bổ.
Biên nhận PDF ghi chứng từ có dấu, người ghi và mã đối soát. Đảo/hoàn phải nhận
tiền hoàn thật trước khi ghi; cash thu lại ca hiện tại, transfer cần mã đối soát
mới. Đảo hết tiền trước khi đảo khoản chi/số dư đầu kỳ hoặc hủy PN ở Kho hàng.

## Kết quả không rõ, restart và restore

Không lập chứng từ mới khi chưa biết yêu cầu trước đã ghi hay chưa. Mở thẻ pending,
**Đối chiếu đúng requestId**. Nếu đã ghi: đóng editor và xem receipt. Nếu chưa ghi:
kiểm tra tiền thật rồi retry cùng ID/payload đã khóa hoặc đóng/tải lại. Double tap
bị khóa khi busy; retry không đổi allocation/mã/nguồn của yêu cầu gốc. Lỗi đối
chiếu giữ pending và không cho retry. Restart đọc pending từ SQLite, không tự replay.

Sau restore, snapshot chỉ thể hiện dữ liệu tại mốc backup; có thể thiếu giao dịch
đã thực hiện sau mốc đó. Đối chiếu ngân hàng/quỹ/chứng từ và requestId trước ghi
lại; receipt trong backup không có nghĩa là tiền đã được hoàn. Không tự replay.

## Hiểu tổng và ngày

- Nghĩa vụ lọc **ngày nguồn** và trạng thái hiện tại; đã trả ròng tính mọi ngày,
  còn phải trả là số dư hiện tại, không phải số dư tại cuối khoảng ngày.
- Dòng tiền lọc **ngày chứng từ**, giữ NCC/loại/nguồn/nội dung nhưng không lọc ngày
  hoặc trạng thái nghĩa vụ. Vì thế có thể thấy trả hôm nay cho nợ từ tháng trước.
- Phân bổ phù hợp được cộng đúng một lần; toàn chứng từ nhiều khoản chỉ là tham
  chiếu, không cộng thêm vào dòng tiền. Đảo/hoàn âm. Nghĩa vụ đã đảo giữ lịch sử
  và loại khỏi tổng hiệu lực.
- Không cộng nghĩa vụ với tiền thanh toán thành hai chi phí. Lương/hoa hồng giữ
  sổ riêng. Chưa có giá vốn nên không gọi doanh thu trừ nhập hàng là lợi nhuận.

## QA

CI render 800×600/1366×768 cho hai sổ, form khoản chi, payment/allocation, chi tiết
và khóa. Regression đối chiếu ngày khác nhau/partial/đảo/retry/restart/restore,
501 khoản và receipts vượt page cap, Owner và background. PDF mẫu và ảnh là dữ
liệu giả từ CI; phải rà artifact đúng head trước merge. CI/ảnh/PDF không tick
manual QA hoặc nghiệm thu điện thoại/in/quỹ/backup production. Không build/test
app local, cài/phát hành hay chạy migration production. Schema vẫn 26.
