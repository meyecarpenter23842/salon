# Bảng lương theo tháng (#127)

Mở **Nhân viên → Bảng lương** bằng quyền Owner. Nếu máy chưa thiết lập PIN,
hãy thiết lập PIN trong Cài đặt để bảo vệ dữ liệu lương. Khi khóa, hết phiên Owner
hoặc app chuyển sang nền, bảng lương và các hộp thoại lương được che lại.

## Thiết lập theo từng nhân viên

Chọn kỳ bắt đầu hiệu lực và một trong ba cách tính, nhập lý do:
- **Tháng cố định:** giữ nguyên lương tháng đã thỏa thuận, kể cả tháng không có công.
- **Tháng theo công chuẩn:** lương tháng × giờ thực làm / giờ chuẩn tháng,
  tối đa bằng lương tháng. Ví dụ 8.000.000 đ, chuẩn 200 giờ, làm 180 giờ → 7.200.000 đ;
  làm 220 giờ → 8.000.000 đ, hiển thị riêng 20 giờ vượt chuẩn.
- **Theo giờ:** đơn giá × giờ thực làm. Ví dụ 50.000 đ/giờ, làm 7,5 giờ → 375.000 đ.

Giờ thực làm lấy từ ca chấm công đã hoàn tất, trừ các lần nghỉ; ca qua đêm
thuộc tháng của ngày bắt đầu ca. Ca nghỉ/hủy không tạo giờ công.
Tính cả giây, làm tròn một lần đến đồng theo quy tắc nửa đồng trở lên làm tròn lên.
Mỗi lần đổi chính sách tạo phiên bản mới; kỳ đã chốt giữ chính sách cũ.
Không tự tính tăng ca, phạt đi muộn, thuế hay bảo hiểm.

## Lập và chốt kỳ

1. Chọn tháng rồi lập bảng lương cho từng nhân viên đã có chính sách hiệu lực.
2. Kiểm tra công, phụ cấp/thưởng và khấu trừ. Mỗi khoản phải có lý do.
   “Bỏ khoản” ghi một khoản đảo, giữ lịch sử gốc.
3. Chỉ chốt tháng đã kết thúc và tất cả ca đã hoàn tất/nghỉ/hủy.
   Phải tải lại nếu dữ liệu hoặc phiên bản thay đổi giữa lúc xem và chốt.
4. Chốt giữ bản sao chính sách, công, khoản điều chỉnh và thông tin hoa hồng
   tại thời điểm chốt; **không tự chi tiền**.
5. Nếu công/chính sách đổi sau chốt, tiền kỳ cũ giữ nguyên.
   Trong kỳ sau, chọn “Điều chỉnh kỳ đã chốt trước đó”, chọn kỳ gốc và ghi lý do.
   Không tự tính lại hoặc tự bù trừ kỳ đã chốt.

Khấu trừ vượt tổng lương không được chốt. Kiểm tra khoản nhập và thỏa thuận trước khi xử lý.
Đã ứng vượt lương được hiển thị “Đã trả vượt”; không tự thu lại hay trừ kỳ sau.

## Tạm ứng và chi trả

Tạm ứng ghi vào kỳ nháp; chi lương ghi vào kỳ đã chốt, có thể trả nhiều lần.
Tiền tạm ứng được tính vào “Đã ứng/trả” và giảm “Còn phải trả”.
Ví dụ lương chốt 8 triệu, ứng 2 triệu, trả thêm 3 triệu → còn 3 triệu.
Không cho chi lương quá số còn phải trả.

Chỉ ghi sau khi đã thực sự chi tiền/chuyển khoản. Chuyển khoản cần mã chứng từ;
app không thực hiện chuyển tiền ngân hàng. Tiền mặt cần ca thu ngân đang mở,
tạo đồng thời phiếu chi và chứng từ lương trong cùng giao dịch SQLite.

**Hoa hồng tiếp tục trả riêng** qua sổ hoa hồng. Số hoa hồng hiển thị ở bảng lương
chỉ để đối soát, không cộng vào lương phải trả. Cùng mã chuyển khoản (không phân biệt
hoa/thường) của một nhân viên không được ghi cả lương và hoa hồng.
Dùng mã đầy đủ gồm ngân hàng nếu các ngân hàng có mã giống nhau.

Nếu ghi trả lỗi hoặc mất phản hồi, yêu cầu được giữ lại trên máy. Mở khoản chờ,
đối chiếu chứng từ trước; “Thử lại cùng yêu cầu” giữ nguyên mã và nội dung để tránh
ghi trùng. “Đối chiếu sổ và bỏ yêu cầu” đọc sổ trước khi xóa yêu cầu đang chờ.
Không thực hiện chuyển tiền lần nữa chỉ vì app báo lỗi. Nếu thao tác ở cửa sổ khác
đã thay đổi phiên bản, bỏ yêu cầu sau đối chiếu rồi tải lại.

## Đối soát, phiếu lương và sao lưu

“Đối soát / lịch sử” hiển thị công và phiên bản dùng để tính, các khoản, chứng từ,
người chốt/ghi và lịch sử chính sách. “Phiếu lương” tạo PDF tiếng Việt có trạng thái
nháp/chốt, phải trả, đã ứng/trả và số còn lại. Phiếu đã xuất cần được bảo quản riêng.

Schema 23 thêm sổ lương, không suy đoán tiền lương/chi trả lịch sử.
Backup schema cũ còn hợp lệ được nâng cấp khi phục hồi; backup schema 23 phải đủ
cả năm bảng lương. Các bản ghi chính sách, khoản, chứng từ và sự kiện không sửa/xóa.
Chốt kỳ giữ bản sao bất biến. Không dùng database vận hành để chạy fixture/test.

QA nguồn được thực hiện qua CI Linux/Windows, gồm kiểm tra công thức, migration,
backup/restore, giao dịch lỗi, retry và đối soát. Kiểm tra UI trên CI không thay thế
nghiệm thu trên máy salon hoặc điện thoại thật; gate thiết bị thật của #111 vẫn chờ.
