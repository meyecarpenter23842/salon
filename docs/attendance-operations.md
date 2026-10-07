
# Chấm công desktop — #126

Quy tắc được chủ salon chốt ngày 07/10/2026: xếp giờ bắt đầu/kết thúc theo ngày,
hỗ trợ ca qua đêm; giờ vào/ra và các lần nghỉ ghi riêng; nghỉ trừ khỏi giờ làm.
Chủ salon sửa ngay với lý do bắt buộc, lưu bản trước/sau. Chưa tính tăng ca,
phạt đi muộn, lương hoặc quy đổi giờ thành ngày công.

## Vận hành

1. Vào **Nhân viên → Chấm công**, chọn ngày và **Xếp ca**.
   Chọn nhân viên đang làm, tên ca, giờ bắt đầu/kết thúc.
   Ca qua đêm phải chọn ngày kết thúc tiếp theo. Hai ca cùng nhân viên không
   được trùng giờ; muốn đổi lịch thì hủy ca cũ có lý do rồi xếp ca mới.
2. Tại desktop, chọn đúng nhân viên/ca rồi **Vào ca**. Đây là ghi nhận của
   người vận hành máy salon, không phải chứng minh danh tính nhân viên.
   Lô này không có tài khoản tự chấm riêng, máy chấm công, GPS hoặc mobile.
3. **Bắt đầu nghỉ → Kết thúc nghỉ** cho mỗi lần nghỉ. Phải kết thúc nghỉ
   trước khi **Ra ca**. Giờ làm = giờ ra − giờ vào − tổng thời gian nghỉ.
   Ca chưa ra không góp giờ làm đã ghi.
4. Dùng **Sửa công / nghỉ ca** để bổ sung quên chấm, sửa giờ/nghỉ,
   ghi nghỉ toàn ca, hủy hoặc khôi phục trạng thái. Phải nhập lý do.
   Giờ thực tế không được trong tương lai, nghỉ phải ở trong giờ vào/ra,
   không chồng nhau; chỉ lần nghỉ cuối được để mở trong ca chưa ra.
   Chuyển sang nghỉ/hủy/chưa vào bỏ giờ hiện tại nhưng vẫn giữ bản trước.
5. **Lịch sử** hiển thị mọi lần xếp, chấm và sửa, người ghi, thời điểm, lý do,
   trạng thái, giờ và các lần nghỉ trước/sau. Không xóa lịch sử.
6. **Tải lại** sau thao tác tại cửa sổ khác. Nếu báo công đã đổi, tải lại
   và đối chiếu trước khi thực hiện lại. Ca đang mở luôn hiện qua ngày;
   giờ được tổng hợp theo ngày bắt đầu lịch ca.

## Quyền và dữ liệu

- Xếp ca/sửa công dùng quyền Owner và PIN hiện có; nếu salon chưa khóa PIN,
  cơ chế Owner mặc định hiện có vẫn áp dụng. Chấm giờ thực tế tại desktop
  không cần PIN; lịch sử ghi actor Máy salon. Không đưa API chấm công lên LAN.
- Một nhân viên chỉ có một ca đang mở. Revision chống ghi đè giữa cửa sổ;
  mã thao tác cho phép phát lại đúng nội dung mà không ghi công lần hai.
- Tạm nghỉ/nghỉ việc không nhận ca/vào ca mới; vẫn xem lịch sử và ra ca cũ.
- Không suy ra công từ lịch hẹn, hóa đơn, ca thu ngân hoặc text ca trong hồ sơ.
- Schema 22 thêm bảng attendance_shifts/attendance_events, FK giữ nhân viên
  có lịch sử, migration cài lại an toàn khi DDL đã tồn tại.
- Sao lưu SQLite giữ ca, nghỉ, revision và lịch sử. Phục hồi đưa giờ công về
  snapshot sao lưu như các dữ liệu khác; đối chiếu trước khi làm tiếp.
- Đồng hồ desktop là nguồn giờ; nếu đổi đồng hồ lùi, thao tác vi phạm thứ tự
  bị từ chối. Không dùng giờ kế hoạch để tự tạo giờ công.
- Payroll #127 tiếp tục chốt chính sách riêng, chưa tự tính lương từ giờ ở đây.

## Kiểm tra

CI: ca qua đêm/nhiều lần nghỉ, phát lại/xung đột, một ca mở,
trạng thái sai/giờ tương lai/nghỉ chồng, quyền Owner/lý do sửa,
rollback công khi ghi lịch sử lỗi, nhân viên nghỉ và giữ lịch sử,
migration 21→22 với DDL dở dang, backup/restore, UI 800×600/1366×768.
Không chạy migration production hoặc test/build ứng dụng local trong lô này.
Nghiệm thu vận hành thực tế chưa được thay thế bởi CI; #111 tiếp tục theo dõi.
