# Nền tảng lệnh ghi Android

Theo dõi #86/#89, tiếp nối phần xem #101. PR nền tảng chỉ thêm metadata/schema 17,
quyền thiết bị và command engine; chưa mở HTTP mutation hoặc nút ghi Android.
Các màn hình khách/lịch/bill sẽ nối vào engine trong PR tiếp theo.

## Quyền và actor

Cài đặt → Kết nối điện thoại: duyệt và bật quyền xem rồi chọn Chỉ xem/Nhân viên/Thu ngân/Chủ salon.
Mặc định và device cũ là Chỉ xem. Tắt quyền xem hoặc revoke xóa quyền ghi.

Nhân viên: tạo/sửa khách, lịch và dòng bill (giá từ catalog).
Thu ngân: thêm phương thức/phân bổ thanh toán và checkout.
Chủ salon: thêm giảm giá và sửa đơn giá. Không có API quản trị/PIN hoặc role do client tự gửi.
Quyền được kiểm ở backend theo device; không kế thừa phiên Owner đang mở của desktop.
Tạo mã/duyệt/bật quyền/chọn role dùng Owner guard/audit trên desktop.

Registry serialize quyền và lệnh đã nhận: revoke chờ transaction đã được nhận xong,
sau khi revoke được lưu thành công thì không lệnh mới nào dùng quyền cũ.
Stop host không nhận lệnh mới, drain lệnh đã được nhận trước khi thả OS lock.

## Atomic và xung đột

Schema 17 thêm lan_resource_revisions, lan_commands và triggers; giữ nguyên dòng nghiệp vụ.
Revisions theo customer/appointment/session, tăng cả khi code desktop hiện có sửa,
kể cả dòng invoice, payment, adjustment và draft JSON trong app_settings.
Revision không dùng updated_at; tombstone không bị reset khi resource bị xóa/tạo lại.

SalonDatabase.forTransaction là scope riêng dùng TransactionDatabase adapter.
Các repository/guard hiện có join cùng transaction mà không đổi desktop callers.
Business write, revision triggers, audit thành công và kết quả command commit/rollback cùng nhau.

Lệnh có commandId, operation, expectedEpoch, targetId, expectedRevision và payload.
Create không có target/revision; các lệnh khác luôn chỉ rõ target/revision.
Role/selected desktop session không được nhận từ payload.
Payload tối đa 16 KiB, nesting/list/string đều bị giới hạn.

Journal key là device hash + commandId, signature dùng JSON canonical.
Cùng lệnh trả kết quả đã lưu, kể cả sau restart; cùng ID nhưng payload/target khác báo command_conflict.
Tra journal trước epoch/revision; kết quả chỉ có ID/type/revision, không sao chép PII/notes/token vào journal.
Kết quả giữ lâu dài; capacity 100000 command, đầy sẽ từ chối, không purge làm mất idempotency.
Backup SQLite giữ cả journal. Không có offline replay tự động.

Sau reopen/restore SQLite, runtime epoch mới; lệnh chưa commit dùng snapshot cũ báo revision_conflict.
Journal có kết quả vẫn trả lại; journal không có và epoch đã đổi không tự ghi lại.

## Kiểm tra và rollout

CI kiểm transaction rollback, restart/retry, desktop→phone stale revision, hai device cùng sửa,
nested billing transaction/draft state, schema 16→17 giữ dữ liệu và thứ tự revoke.
Schema 17 chỉ được chạy khi bản app mới mở database. Quy trình này không mở/build/test
app local, không chạy migration trên dữ liệu máy salon, không thay bộ cài/build local.
Chưa xác nhận điện thoại thật. Quyền ghi đang là nền tảng, các workflow mobile còn tiếp tục.
