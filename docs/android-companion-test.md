# Run Android connection shell

For the current QA batch use the APK from the exact green PR head following
[salon operations](salon-operations.md) and record results in
[physical QA acceptance](salon-qa-acceptance.md). Building/running on the owner
machine is excluded by #104. The developer-only instructions below apply to a
separately authorized development machine.

Open the Flutter project root (the directory with pubspec.yaml) in Android Studio,
choose an Android device/emulator and run lib/main.dart. Android enters the
companion shell before any Windows license, desktop settings or business SQLite
initialization. Windows keeps the existing desktop/license flow.

CI builds a debug APK under the artifact salon-companion-debug-apk on the PR's
Flutter CI run. This is a test build using the existing debug signing configuration;
it is not a store release. The artifact includes qa-provenance.json with the APK file SHA-256 and source/tested tree identifiers.

## Try connecting

1. Configure desktop HTTPS once following lan-health-setup.md and keep the licensed
   main app open.
2. Get the API URL from desktop Settings → Kết nối điện thoại.
3. Enter that URL on Android plus Mã xác minh máy salon copied from desktop Settings. Obtain this fingerprint directly from the owner PC,
   not from an unknown server. Do not copy the private key to the phone.
4. Tap Kiểm tra kết nối. Success means the desktop health endpoint responded with
   API version 1; it does not grant staff access or pair the device.

The Android shell remembers the successfully checked URL and fingerprint using
device preferences; it does not store salon business data. It forgets the success
indicator on app background/reopen or edited input, so it never promises continued
connectivity from a stale health check. Pairing and owner approval/revocation now follow the health check; see
[phone-pairing.md](phone-pairing.md). Read-only salon access requires a separate owner grant; see [phone-data-read.md](phone-data-read.md).

The client uses HTTPS, endpoint-specific certificate fingerprint and certificate
validity checks. It rejects redirects, different certificates, wrong API version,
oversized responses and timeouts. The fingerprint must still be verified even
with a certificate signed by a public CA. There is no accept-all TLS callback.

For a same-router phone use desktop's private LAN address. For an emulator use an
address it can reach; localhost refers to the emulator itself. Use the same
certificate pin for the desktop address verified by the owner. Wi-Fi client
isolation or a firewall may block even correct URL/pin. A 4G/other-network client
requires a separately configured reachable private network/HTTPS endpoint.

## Remaining evidence

Widget/client integration tests on Ubuntu/Windows and Android APK compilation do
not prove a real phone's network connection. The physical-phone gate transferred from #89 to #111 remains open until an Android
device runs the shell and reaches the owner desktop over the intended transport.
Owner reported health success on an emulator; this does not close the physical-phone gate.
Read-only customer/invoice/appointment routes are implemented. QR scan/paste, approved-role business writes, bill/checkout and reconnect/resync are implemented (#100–#110). Offline writes are blocked; uncertain commands require explicit result checking. Other-network/4G access remains #112. No business SQLite is opened on the phone.

## Người dùng lấy hai thông tin ở đâu?

Trên máy salon: **Cài đặt → Kết nối điện thoại** (hoặc nút Kết nối điện thoại trên
thanh trên cùng). Khi host đã mở, màn hình hiển thị **Địa chỉ máy salon** và
**Mã xác minh máy salon**, mỗi giá trị có nút sao chép. Nhập nguyên hai giá trị vào
các ô cùng tên trên Android. Địa chỉ trong ví dụ không phải địa chỉ máy người dùng.

Mã xác minh được app tính SHA-256 trên DER của chứng chỉ server (chứng chỉ đầu tiên
trong PEM), cùng cách Android kiểm tra. Không băm văn bản PEM hoặc private key,
không hiển thị private key. Chỉ hiển thị thông tin khi host đã khởi động và tự kiểm tra HTTPS thành công;
host chưa cấu hình/lỗi/dừng sẽ không cung cấp thông tin cũ để người dùng nhập.

Có thể xem thêm [hướng dẫn LAN](lan-health-setup.md).
Trong Cài đặt, chọn mạng và bấm **Bật kết nối điện thoại** để app tự tạo
identity và mở host ngay. Luồng này không tự thay đổi firewall.
Giữ máy salon/app mở; thử cùng Wi-Fi trước. 4G/mạng khác cần truy cập từ xa được
thiết lập riêng. Chủ salon bật **Cho xem dữ liệu salon** cho từng điện thoại đã duyệt để xem khách hàng, hóa đơn và lịch hẹn.



## Gate điện thoại thật sau #110 (chuyển #111, chưa thực hiện)

Ghi model/Android OS, ngày, phiên bản desktop, SHA nguồn/APK và ảnh/video cho từng bước; phân biệt emulator và CI.

- [ ] Camera quét QR thật, từ chối/cấp lại quyền camera, QR sai/cũ, dán và nhập thủ công; đối chiếu pin trên desktop. QR không tự cấp quyền.
- [ ] Health HTTPS/pin → yêu cầu/duyệt → xem khách/lịch/bill; đổi desktop/Staff được phản ánh trên điện thoại trong lần poll (khoảng 5 giây), giữ lọc/scroll.
- [ ] Hai máy cùng Wi-Fi và PC nối dây; mạng khách/AP isolation; hướng dẫn Private Firewall đúng port. Không thay firewall tự động.
- [ ] PC đổi IP → áp dụng mạng → quét QR mới, cùng pin giữ quyền; đổi pin cần kiểm tra/duyệt mới.
- [ ] Mất Wi-Fi khi nhập: giữ nháp, cảnh báo offline, khóa ghi; reconnect/resync không ghi dữ liệu cũ; sleep/restart đổi epoch.
- [ ] Mất mạng lúc checkout: kiểm tra ID yêu cầu để nhận hóa đơn, không tự gửi lại; đảm bảo chỉ một hóa đơn/trừ kho/thanh toán.
- [ ] Background/resume, revoke/đổi quyền lúc đang mở bill/dialog, hai điện thoại sửa đồng thời; dữ liệu riêng tư và quyền ghi đúng trạng thái.
- [ ] Bàn phím/back, 360 px/chữ lớn, scroll và tap; ảnh/video owner nghiệm thu.

CI chỉ chứng minh protocol/permission/reconnect/widget/APK compilation. Các ô điện thoại thật vẫn chưa đánh dấu.
