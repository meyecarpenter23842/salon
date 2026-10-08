# Voucher, membership và gói dịch vụ — domain schema 27

Issue #143 là lớp domain/database. POS checkout, UI, PDF và reporting nằm ở
#144/#145.

## Không dùng dữ liệu cũ làm entitlement

- `customers.tier` vẫn chỉ là nhãn hồ sơ.
- `loyalty_points` vẫn là điểm tích lũy hiện tại.
- Migration 26 → 27 chỉ tạo cấu trúc; không suy voucher, membership hoặc package
  từ tier, points hay invoice cũ.

## Voucher

Voucher V1 là mã giảm giá một lần, không phải gift card/stored-value. Code unique
không phân biệt hoa thường; hỗ trợ fixed/percent, optional cap/min spend, public
hoặc customer-bound và validity window. Cấu hình dùng revision và không hard
delete. Redeem/restore là chứng từ append-only; restore sau void cho phép dùng
lại, còn refund semantics sẽ được nối ở #144.

## Membership

Plan hiện hành có giá bán, số ngày hiệu lực, % giảm dịch vụ và sản phẩm ở dạng
basis points. Membership đã kích hoạt lưu snapshot toàn bộ plan, gắn đúng khách.
Renewal khi còn hạn bắt đầu từ expiry mới nhất, vì vậy không có hai membership
active chồng nhau. Cancellation là chứng từ riêng, không sửa snapshot.

Usage/restore membership là append-only và link invoice. #144 sẽ gọi primitive
này trong transaction checkout/void; không đọc lại plan live để tính quyền lợi.

## Service package

Plan gồm dịch vụ + số lượt. Khi issue package, service name/list price/quantity
được snapshot. Giá bán package được phân bổ deterministic theo cumulative
proportional weight:

`allocatedThrough = salePrice * cumulativeWeight ~/ totalWeight`

Allocation từng component là chênh lệch hai mốc cumulative; trong component,
`unitValueBase` + `remainderUnits` xác định giá trị recognized của từng lượt.
Tổng allocation luôn bằng đúng giá package, không dùng số thực.

Balance là tổng movement append-only:
- grant: cộng lượt;
- redeem: trừ lượt + recognized value;
- restore: cộng lại đúng movement gốc;
- cancel: đưa số dư chưa dùng về 0.

Package snapshot/unit/movement/cancellation đều immutable. Plan current config có
thể sửa cho lần bán sau mà không đổi package đã bán.

## Idempotency và quyền

Mọi mutation dùng `benefit_events.request_id` + signature. Retry đúng payload
trả lại chứng từ cũ; cùng requestId khác payload bị chặn. Catalog, issue/cancel
và correction yêu cầu Owner/PIN và ghi audit. Redemption/use bình thường là
primitive domain cho checkout, không tự yêu cầu Owner; #144 chịu trách nhiệm gọi
chúng trong transaction invoice.

## Backup/migration

Schema 27 backup phải có đầy đủ plan/catalog, entitlement snapshot, usage/
redemption/movement/cancellation và event journal. Partial migration chạy lại
idempotent. Restore/restart giữ ID, snapshot, balance và event nguyên vẹn.


## POS integration — schema 28 (#144)

Schema 28 không thay đổi entitlement schema 27. Nó chỉ thêm snapshot nối hóa đơn với
quyền lợi: tổng benefit trên invoice, basis tiền mặt theo từng invoice line và
package movement gắn đúng service line. Draft lưu intent trong app_settings; chỉ
checkout transaction mới redeem/use/issue entitlement.

Thứ tự V1: package trước, sau đó membership hoặc voucher, sau đó manual line/bill
discount. Snapshot line giữ cash basis và recognized package value riêng để
commission không double-count package purchase với service redemption. Void đảo
voucher/membership/package usage theo rule; refund sau dịch vụ không restore
voucher/package. Refund/void giao dịch mua membership/package dùng cancellation
primitive schema 27 và bị chặn nếu còn net usage/redemption.
