# Vận hành desktop và Android trong LAN V1

Theo #104/#111. Desktop chính giữ backend HTTPS và SQLite; Staff dùng cùng SQLite qua process riêng; Android gọi dữ liệu desktop, không giữ database salon. Nguồn hiện tại 1.8.6+18, schema 20. Cùng version không bảo đảm cùng commit: luôn ghi SHA và hash file. Không dùng CI/emulator thay nghiệm thu điện thoại thật. Checklist: [salon-qa-acceptance.md](salon-qa-acceptance.md).

## Chọn bản để nghiệm thu

1. Mở PR của lô đã merge; xác nhận toàn bộ Flutter CI xanh đúng **head SHA cuối**, gồm Linux analyze/tests, Windows tests/release/Staff/installer/updater/NSIS và Android APK. Không dùng artifact của head cũ hoặc run thất bại.
2. Trong run đó tải artifact **salon-companion-debug-apk**. Giữ link PR/run, artifact ID và ZIP digest. Giải nén lấy app-debug.apk cùng qa-provenance.json. Artifact hết hạn thì cần CI mới trên đúng nguồn được chọn; không dùng APK cũ chỉ vì cùng version.
3. Đối chiếu source_head_sha với PR head; tested_checkout_sha có thể là commit merge tạm của CI, tested_tree_sha là tree thực sự được build. Sau merge, đối chiếu tree main nếu muốn khẳng định cùng nguồn. Ghi version desktop **đang chạy** và nguồn/file đã cài; đồng bộ Git local không cập nhật exe đang chạy.
4. Băm **file APK sau giải nén** bằng PowerShell: `Get-FileHash -Algorithm SHA256 -LiteralPath 'C:\QA\app-debug.apk'`. So với apk_sha256 trong manifest. ZIP digest và APK hash là hai giá trị khác nhau. Ghi cả hai, không suy ra APK hash từ ZIP.
5. Đây là APK debug để kiểm tra, không phải bản phát hành/store. Việc cài APK/bộ desktop mới và thao tác trên dữ liệu production cần yêu cầu riêng của owner theo #104. Nếu chữ ký bản cũ không tương thích, dừng và lập phương án; không tự gỡ app vì có thể mất credential hoặc command chưa rõ kết quả.

Manifest là thông tin nguồn/hash do CI tạo, không phải chứng thực thiết bị thật. Hướng dẫn này không cài app, phát hành hoặc thay cấu hình máy.

## Bắt đầu ca và ghép điện thoại

- Mở desktop chính đã có license; giữ PC thức và app chính mở. Staff không thay main để phục vụ điện thoại.
- Desktop: **Cài đặt → Kết nối điện thoại** → chọn mạng LAN/Wi-Fi/dây → **Bật kết nối điện thoại**. Chỉ dùng thông tin khi host tự kiểm tra thành công.
- Điện thoại cùng LAN: quét QR hoặc dán/nhập địa chỉ và mã xác minh; đối chiếu trực tiếp trên PC rồi **Kiểm tra kết nối**. Camera bị từ chối thì nhập/dán; có thể cấp lại Camera trong cài đặt Android.
- QR chỉ chứa địa chỉ HTTPS và pin chứng chỉ, không có token/mã ghép. Health thành công chưa cấp quyền.
- Desktop tạo mã ghép một lần, hạn 5 phút; Android nhập tên/mã và yêu cầu. Chủ salon đối chiếu tên và mã thiết bị trên hai màn hình rồi duyệt. Cấp quyền xem salon và vai trò ghi phù hợp nhu cầu; không coi tên điện thoại là danh tính nhân viên.
- Desktop xem/thu hồi từng thiết bị. Thu hồi có hiệu lực ở API; Android đóng dữ liệu riêng tư khi nhận trạng thái. Background cũng đóng route/dialog riêng tư; resume xác minh lại.

Chi tiết: [pairing](phone-pairing.md), [quyền và ghi](android-write-workflows.md), [bill/thanh toán](mobile-billing.md).

## Mạng, sleep và đổi IP

Hai máy cùng mạng kể cả PC nối dây. Tránh Wi-Fi khách/AP isolation. Windows cần hồ sơ Riêng tư và rule đúng ứng dụng/cổng TCP cấu hình (mặc định 8743), phạm vi LocalSubnet. Chủ máy/quản trị viên kiểm tra rule; app không tự sửa firewall. Không tắt toàn bộ tường lửa hoặc mở cổng router/Public để chữa LAN. Mạng khác/4G chưa nghiệm thu và thuộc #112.

Đổi IP: **Tìm lại mạng → chọn mạng → Áp dụng mạng đã chọn → QR mới → Kiểm tra kết nối**. Cùng pin giữ danh tính đã duyệt. Nếu pin đổi, đối chiếu với owner và ghép lại; dừng khi còn yêu cầu chưa rõ kết quả. Chứng chỉ tự tạo hạn một năm; gia hạn là bảo trì riêng, không tự bỏ kiểm tra pin.

Mất Wi-Fi/sleep/main thoát: Android cảnh báo offline và khóa ghi; giữ nháp trong foreground. Sau kết nối lại, kiểm tra quyền/resync và tải snapshot mới trước lưu. Desktop khởi động lại đổi epoch. Không ghi dữ liệu từ bản cũ; các danh sách cập nhật theo poll khoảng 5 giây cộng thời gian mạng, không phải cam kết tức thời.

## Khi ghi hoặc thanh toán chưa rõ kết quả

Không tạo bill/yêu cầu thanh toán mới để thử lại. Giữ màn hình phục hồi và commandId; bấm **Kiểm tra kết quả**, đối chiếu hóa đơn/thanh toán/tồn trên desktop. Chỉ retry theo luồng hiện có với cùng commandId khi đã xác định trạng thái; app không tự replay khi reconnect. Không xóa dữ liệu ứng dụng/Keystore, đổi máy salon hoặc áp stash để xử lý một giao dịch chưa rõ. Ghi mã yêu cầu trong biên bản riêng có kiểm soát; không đăng token/PIN/dữ liệu khách lên issue.

Hai thiết bị sửa cùng bản: thiết bị sau phải gặp conflict, đọc lại và đối chiếu; không lặp lưu bản cũ. [Resync](lan-resync.md).

## Kho và kết ca

Phiếu nhập/xuất/kiểm kê lưu nháp chưa đổi tồn; xác nhận mới ghi toàn phiếu và lịch sử. Phiếu đã xác nhận giữ snapshot tên/đơn vị/NCC/giá nhập; hủy có lý do tạo chuyển động đảo trên tồn hiện tại. Giá nhập không tự đổi giá bán, tạo chi tiền/công nợ hoặc tính giá vốn. Xuất/bán có thể âm; đỏ là cảnh báo cần đối chiếu/nhập bù, không tự nâng tồn về 0. Lưu PDF, đối chiếu số phiếu/dòng/tổng và lịch sử trước kết ca. [Chứng từ kho](stock-documents.md), [tồn âm](negative-stock.md).

## Sao lưu và phục hồi

Desktop: **Cài đặt → Backup & Restore**; xem đường dẫn thực tế hiển thị trong app. Trên Windows thông thường:
- Dữ liệu: `%APPDATA%\HairSpaManager\data\.salon_manager\salon_manager.db`.
- Backup: `%APPDATA%\HairSpaManager\data\backups`.

**Tạo sao lưu** dùng VACUUM INTO để lấy snapshot SQLite nhất quán khi mở; kiểm tra integrity, liên kết và schema. Không chỉ copy file .db đang mở vì có thể bỏ WAL. Giữ backup trước bảo trì và cuối ca; owner chọn nơi lưu bản sao ngoài máy có kiểm soát truy cập, ghi ngày/hash và giữ nhiều mốc. App không tự cung cấp retention/offsite backup.

Backup SQLite gồm khách/lịch/bill/hóa đơn/phân bổ, kho/chứng từ/NCC, danh mục/đơn vị, audit, journal lệnh và cấu hình nghiệp vụ. Nó **không** sao lưu đầy đủ TLS/private key/quyền thiết bị tại `%APPDATA%\HairSpaManager\lan`, Android Keystore, license, SharedPreferences máy, máy in/logo hoặc file build/bộ cài. [Quyền sở hữu cấu hình](SETTINGS_OWNERSHIP.md). Đổi máy cần phương án riêng; không gửi private key/token/PIN qua chat.

Phục hồi chỉ khi owner yêu cầu và đã chọn mốc:
1. Dừng ghi trên Android; dừng kết nối điện thoại, đóng toàn bộ Staff, giữ main để dùng màn phục hồi. Chốt các yêu cầu chưa rõ trước; restore journal về mốc cũ có thể mất bằng chứng lệnh xảy ra sau backup.
2. Tạo/giữ backup hiện tại, ghi hash và thống kê đối chiếu. Phục hồi **quay dữ liệu về thời điểm backup**, không ghép dữ liệu mới phát sinh sau đó.
3. Chọn file .db hợp lệ; app kiểm tra trước, tạo `salon_manager_pre_restore_...`, kiểm tra bản tạm, thay file và mở/migrate tới schema hiện tại. Backup mới hơn app bị từ chối. Nếu mở/kiểm tra thất bại, app thử rollback; giữ file pre_restore và thông báo lỗi.
4. Đối chiếu khách/lịch, từng bill đang làm/legacy, hóa đơn/phân bổ, tồn âm, phiếu nháp/xác nhận/hủy, danh mục/đơn vị và lịch sử. Mở lại main/Staff sau đối chiếu, bật kết nối, yêu cầu điện thoại resync và đọc bản mới trước ghi.
5. Nếu cần hoàn tác lần restore, dùng pre_restore qua màn phục hồi theo cùng quy trình. Nếu rollback tự động thất bại, dừng ghi và giữ các file để hỗ trợ; không xóa sidecar hoặc chép đè SQLite thủ công khi process còn sống.

Rollback **dữ liệu** khác rollback **chương trình**. Không chạy exe schema cũ trên DB schema mới. Dùng bản chương trình tương thích và backup trước migration đã xác minh; downgrade/cài lại cần yêu cầu riêng, không tự sửa user_version. Hướng dẫn [Windows updater recovery](windows-updater-recovery.md) bổ sung cho lỗi bộ cài.

## Khi gặp lỗi

| Hiện tượng | Kiểm tra / hành động |
|---|---|
| Desktop không có QR | Host sẵn sàng chưa, đúng interface LAN chưa; đọc thông báo, không dùng địa chỉ cũ |
| Desktop self-check xanh, phone timeout | Wi-Fi/LAN, Private profile/rule app/port, AP isolation, PC thức và main mở |
| Pin/certificate lỗi | Đối chiếu mã trực tiếp, giờ máy/thời hạn chứng chỉ; không chấp nhận mã lạ |
| Chờ duyệt / không thấy dữ liệu | Mã còn hạn, owner duyệt đúng ID, bật quyền xem và vai trò phù hợp |
| Dữ liệu cũ / conflict | Nối lại, tải snapshot mới và đối chiếu nháp; không ghi đè bản cũ |
| Checkout chưa rõ | Giữ commandId, Kiểm tra kết quả và đối chiếu desktop; không thu/trừ kho lần hai |
| Restore báo lỗi | Dừng ghi; giữ pre_restore/thông báo; đối chiếu rollback trước mở lại thiết bị |

Gói chẩn đoán trong Cài đặt không kèm DB/backup. Khi báo lỗi ghi phiên bản/SHA, thời điểm, thao tác và thông báo đã che dữ liệu riêng tư. Không đăng database, private key, mã ghép, token, PIN, license hoặc thông tin khách lên GitHub.
