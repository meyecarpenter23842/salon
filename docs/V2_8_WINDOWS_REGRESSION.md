# V2-8 — Windows Regression & Handover

## Baseline

- Repo: `meyecarpenter23842/salon`
- Base branch: `main`
- Base SHA: `05e0f4da7431d723a631416f60b689ee5fe7cca9`
- Logic audit issues `#40` → `#45` đã merge trước baseline này.
- Lô V2-8 chỉ làm regression/CI/tài liệu. Không đổi business logic nếu regression không phát hiện bug thật.

## Mục tiêu

V2-8 là gate hậu kiểm cho roadmap `#18` và master logic audit `#46`:

1. chạy lại regression toàn app sau các fix #40–#45;
2. có bằng chứng Windows từ build Release thật, không chỉ Ubuntu test;
3. đối chiếu phần còn mở của V2-2 và V2-3;
4. cập nhật tài liệu bàn giao cuối V2;
5. không deploy, không migration, không tự tạo release.

## Gate CI sau lô này

Mỗi PR vào `main` có hai job độc lập:

### Analyze and test — Ubuntu

```text
flutter pub get
flutter analyze
flutter test
```

Job này giữ gate static analysis + regression suite đang có.

### Windows regression smoke — Windows thật

Chạy trên `windows-latest`:

```text
flutter pub get
flutter test
flutter build windows --release
```

Sau build, CI mở trực tiếp:

```text
build/windows/x64/runner/Release/salonmanager.exe
```

với `%APPDATA%` cô lập trong thư mục tạm của runner. Process phải còn sống sau 10 giây; nếu app crash/thoát sớm thì job fail. CI sau đó chủ động đóng process.

Gate này chứng minh đồng thời:

- toàn bộ regression suite chạy được trên Windows;
- Windows Release build thành công;
- executable Release tồn tại và khởi động được với môi trường local-data sạch.

## Đối chiếu V2-2 — Lịch giờ × nhân viên

Các regression hiện có bao phủ phần logic quan trọng của V2-2:

- xung đột lịch theo nhân viên;
- thời lượng lịch theo tổng dịch vụ;
- employee attribution theo `employeeId`, không suy từ tên hiển thị;
- chặn nhân viên trạng thái không phù hợp nhận lịch/dịch vụ mới;
- lịch `Đã hủy` không chặn slot;
- lịch đã thanh toán không được sửa thành trạng thái/dữ liệu gây lệch hóa đơn;
- flow Lịch → hồ sơ khách / nhân viên / dịch vụ / POS giữ đúng entity ID.

V2-2 được coi là code-regression complete khi cả Ubuntu regression và Windows regression smoke xanh trên exact PR head. UI interaction thủ công vẫn nên được chạy trước publish thật.

## Đối chiếu V2-3 — POS 3 khu

Các regression hiện có bao phủ:

- draft bill được lưu bền và phục hồi;
- chống checkout trùng;
- transaction checkout không để lại partial state;
- discount từng dòng và toàn bill;
- chỉnh giá từng dòng không đổi catalog gốc;
- tách line cùng SKU;
- employee attribution cho service line;
- customer/payment persistence;
- lịch → POS giữ đúng appointment/customer/services;
- revenue/reporting dùng net invoice sau bill-level discount.

Windows regression smoke bổ sung bằng chứng rằng toàn suite này chạy trên Windows và Release executable khởi động được.

## Luồng regression toàn app cần giữ xanh

Luồng chính:

`Khách → Lịch → POS → Thanh toán → Lịch sử → Overview/Reports → Kho → Settings`

Nhóm test cần đặc biệt chú ý khi CI đỏ:

- appointment correctness / conflict / status guard;
- invoice draft integrity / checkout transaction / employee flow;
- customer query semantics;
- inventory persistence + atomic batch;
- settings ownership / payment persistence;
- reporting discount allocation / canceled-status semantics;
- backup/restore safety;
- shell/layout regression ở desktop sizes.

Nếu có nhiều lỗi cùng xuất hiện, đọc toàn bộ job đỏ trước rồi gom nguyên nhân thành một lô sửa; không push từng lỗi lắt nhắt.

## Windows manual pre-release còn cần làm trước publish thật

CI startup smoke không thay thế hoàn toàn thao tác người dùng phụ thuộc desktop shell/OS. Trước khi publish/release thực tế, kiểm tra thủ công tối thiểu:

- mở đủ chín workspace chính;
- tạo/sửa lịch và xác nhận xung đột hiển thị đúng;
- Lịch → POS → checkout trên UI thật;
- đóng/mở app giữa lúc có bill dở và xác nhận draft phục hồi;
- xuất/mở PDF hóa đơn;
- xuất CSV Reports;
- backup và restore từ đường dẫn Windows thật;
- theme/focus/keyboard ở kích thước desktop thông dụng.

Các mục này là release/manual gate, không phải lý do để sửa code nếu chưa có lỗi được tái hiện.

## Quy tắc đóng roadmap

- `#46`: chỉ đóng sau khi #40–#45 đã hoàn tất, regression CI hậu kiểm xanh và tài liệu V2-8 đã merge.
- `#18`: chỉ đóng khi V2-2/V2-3 được đối chiếu xong, V2-8 có bằng chứng Windows + tài liệu và không còn blocker V2 đã biết.
- Không merge PR V2-8 nếu chưa có lệnh rõ ràng.
- Không deploy, release hay migration từ lô này.
