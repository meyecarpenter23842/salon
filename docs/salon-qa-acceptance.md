# Biên bản nghiệm thu LAN V1 — #111

**Trạng thái mẫu: CHƯA CHẠY TRÊN ĐIỆN THOẠI THẬT.** Sao chép mẫu cho mỗi phiên kiểm tra; để “Chưa chạy” cho ca chưa thực hiện, không đánh dấu pass theo CI/emulator. #111 và roadmap #104 chỉ nghiệm thu khi có bằng chứng thiết bị thật và owner duyệt UX. [Hướng dẫn vận hành](salon-operations.md).

Dùng dữ liệu giả trên môi trường QA được owner cho phép. Cài APK/desktop, chạy app và migration/restore trên máy salon cần yêu cầu riêng theo #104. Không thử ngắt mạng/thanh toán trên chứng từ thật chưa chốt; dùng fixture đã kiểm soát và backup trước phiên.

## Thông tin bắt buộc

| Trường | Giá trị |
|---|---|
| Người thực hiện / owner nghiệm thu | Chưa ghi |
| Ngày giờ / múi giờ | Chưa ghi |
| Thiết bị 1, hãng/model / Android OS / bản vá | Chưa ghi |
| Thiết bị 2, hãng/model / Android OS | Chưa ghi (cần cho sửa đồng thời) |
| PC / Windows / desktop version **đang chạy** | Chưa ghi |
| PR / head SHA / CI run và attempt | Chưa ghi |
| Tested checkout SHA / tree SHA từ manifest | Chưa ghi |
| Main merge SHA / tree nguồn desktop | Chưa ghi |
| APK artifact ID / ZIP SHA-256 | Chưa ghi |
| APK file SHA-256 / tên/version đã cài | Chưa ghi |
| Exe/bộ cài desktop SHA-256 / nguồn của file | Chưa ghi |
| Mạng PC/phone, Private profile / port | Chưa ghi (che địa chỉ nếu đăng công khai) |
| Backup trước phiên: mốc / SHA-256 / nơi lưu riêng | Chưa ghi |
| Dữ liệu QA: ID khách/lịch/bill/phiếu | Chưa ghi (ID giả) |

Giữ manifest CI cùng hồ sơ. Không suy ra version exe từ pubspec local. APK hash là file đã cài, không phải ZIP artifact. Không đăng dữ liệu khách/token/PIN/private key vào hồ sơ công khai.

## Các ca thiết bị thật

Mỗi dòng ghi **Pass / Fail / Chưa chạy**, kết quả thực tế, thời điểm, link ảnh/video đã che dữ liệu và issue lỗi nếu có. Không chỉ ghi “đã thử”.

| ID | Thao tác và kết quả cần đạt | Thực tế / bằng chứng |
|---|---|---|
| P01 | Camera quét QR desktop; đối chiếu endpoint/pin, chỉ điền sau xác nhận. QR không tự cấp quyền | Chưa chạy |
| P02 | Từ chối/cấp lại Camera, quay lại, QR sai/cũ/quá lớn, dán/nhập; không crash hoặc tự lưu mã lạ | Chưa chạy |
| P03 | Health đúng pin; pin sai/host dừng bị từ chối; thời gian chờ và lỗi rõ | Chưa chạy |
| P04 | Xin/duyệt đúng tên + ID; sai/hết hạn mã, từ chối; cấp quyền xem/vai trò ghi; hai phone độc lập | Chưa chạy |
| P05 | Xem/tìm khách, sửa hồ sơ theo quyền; desktop/Staff và phone khớp; thiết bị chỉ đọc không ghi được | Chưa chạy |
| P06 | Tạo/đổi lịch với khách/dịch vụ/nhân viên, date/time picker; timeline/desktop đúng ID và thời gian | Chưa chạy |
| P07 | Lịch → bill, thêm/sửa dịch vụ/hàng/nhân viên/giá theo quyền, giảm giá, nhiều bill giữ đúng nháp | Chưa chạy |
| P08 | Tiền mặt/chuyển khoản/thẻ/chia khoản; tổng/phân bổ đúng, checkout tạo một hóa đơn và trừ kho đúng một lần, biên nhận đúng | Chưa chạy |
| P09 | Sửa desktop và Staff, phone cập nhật poll; giữ lọc/scroll; đổi danh mục/đơn vị phản ánh đúng | Chưa chạy |
| P10 | Mất Wi-Fi lúc nhập: cảnh báo, giữ nháp foreground, khóa ghi; reconnect yêu cầu snapshot mới trước lưu | Chưa chạy |
| P11 | Ngắt mạng sau gửi payment/checkout: ghi commandId, Kiểm tra kết quả sau nối/restart; không hóa đơn/thu tiền/trừ kho lần hai | Chưa chạy |
| P12 | PC sleep/thoát main/restart; offline rõ; epoch mới/resync; Staff riêng không làm host thay main | Chưa chạy |
| P13 | Đổi IP cùng pin/quét QR mới giữ quyền; pin đổi phải đối chiếu/ghép lại, bảo toàn lệnh chưa rõ kết quả | Chưa chạy |
| P14 | Background/resume và thu hồi/đổi quyền khi bill/dialog đang mở: dữ liệu riêng tư đóng, không ghi bằng quyền cũ | Chưa chạy |
| P15 | Hai phone mở cùng revision, A lưu; B conflict, tải lại/đối chiếu; không mất sửa của A hoặc ghi lặp | Chưa chạy |
| P16 | PC dây + phone Wi-Fi và cả hai Wi-Fi; mạng khách/isolation lỗi rõ; kiểm tra Private rule đúng app/port, không mở router/Public | Chưa chạy |
| P17 | Bàn phím che form, Back/đổi tab/bill, bỏ nháp, chữ lớn/cỡ màn nhỏ, scroll/tap/loading/rỗng/lỗi; owner nhận xét cụ thể | Chưa chạy |
| K01 | Đơn vị/danh mục sửa/ngừng sử dụng giữ ID lịch sử; sản phẩm/dịch vụ cũ vẫn đọc đúng | Chưa chạy |
| K02 | PN nhiều dòng/NCC/giá nhập: nháp không đổi tồn, xác nhận một lần, snapshot/tổng chính xác | Chưa chạy |
| K03 | PX từ 0 xuống âm đỏ; nhập bù còn âm vẫn đỏ; hủy có lý do đảo trên tồn hiện tại, lịch sử đúng | Chưa chạy |
| K04 | Hủy nháp không đổi tồn, phân trang/tìm phiếu, PDF/in A4 tiếng Việt đúng dòng và tổng | Chưa chạy |
| B01 | Backup/restore môi trường QA: bill legacy/đa bill/paid, phân bổ, chứng từ/tồn/danh mục giữ đúng mốc; ghi số liệu trước/sau | Chưa chạy |
| B02 | Dữ liệu lỗi/schema mới bị từ chối, pre_restore/rollback đối chiếu; sau restore main/Staff/phone đọc bản mới | Chưa chạy |

P11 phải có số hóa đơn, tổng phân bổ và tồn/lịch sử trước–sau trong hồ sơ riêng; ảnh “thành công” đơn lẻ chưa chứng minh không ghi lặp. P15 phải có kết quả của cả hai thiết bị. K04 PDF CI không chứng minh máy in thật. B01/B02 không thực hiện trên production theo mặc định.

## Bằng chứng CI và giới hạn

| Phần | Nguồn kiểm chứng tự động |
|---|---|
| Restore, safety backup, rollback sau lỗi mở, schema 19→20 và legacy draft | test/backup_service_test.dart (fixture giả, đối chiếu tất cả bảng nghiệp vụ) |
| Migration danh mục/schema 17/18/19 | catalog_management_test, negative_stock_test, stock_document_repository_test |
| Atomic checkout/journal/retry/quyền/concurrency | lan_write_engine_test, lan_workflow_* và các invoice/checkout tests |
| QR, pin, cursor/reconnect/background/revoke | lan_connection_qr_test, companion_qr_test, companion_resync_test, lan_changes_test |
| UI/theme/keyboard/chữ lớn | companion widget tests và mobile-ui-review Flutter engine renders |
| Windows/Staff/installer/updater/NSIS, APK compile | Full Flutter CI đúng head; ghi link run/attempt và manifest APK |

Điền link run, số test pass/skip với lý do và failure/rerun nếu có vào biên bản. Mọi gate phải xanh đúng head; không skip test nghiệp vụ để nghiệm thu. CI fixture không kiểm tra camera/Wi-Fi/sleep/firewall/Keystore/UX trên phần cứng của owner.

## Kết luận phiên

- Ca đã pass: Chưa ghi.
- Ca fail + issue sửa: Chưa ghi.
- Ca chưa chạy / thiết bị còn thiếu: Chưa ghi.
- Owner đánh giá UI/UX và yêu cầu sửa: Chưa ghi.
- Quyết định nghiệm thu: **Chưa đạt gate thiết bị thật**.
- #111: **giữ mở**. #104: **giữ mở**. #55 Staff theo dõi riêng; khác Wi-Fi/4G, nhân sự và phần sau V1 ở #112.

Chỉ thay quyết định khi đã có kết quả thật cho các ca áp dụng và owner xác nhận; giữ lịch sử, không xóa ca fail để làm báo cáo xanh.
