# DB-7 — Future phone-ready baseline

## Mục tiêu

DB-7 chỉ tạo một baseline sạch để sau này có thể thêm phone client mà không phải đổi lại toàn bộ identity/repository boundary.

**Không thuộc DB-7:** sync engine, cloud/server, Supabase, API mới, conflict resolver, tombstone hàng loạt, `version` hàng loạt, migration production hoặc phone app.

## Baseline đã audit

### 1. Repository boundary

UI đọc/ghi nghiệp vụ qua Riverpod providers và các contract trong `lib/core/repositories/repository_contracts.dart`.

Flow hiện tại:

```text
UI
→ Riverpod provider
→ Repository contract
→ SQLite adapter / fake adapter
```

Phone phase sau này phải giữ UI/business flow tách khỏi transport. Nếu có LAN/API/cloud adapter thì adapter mới phải nằm sau boundary này; không cho feature page gọi SQLite hoặc HTTP trực tiếp.

### 2. Identity

Các primary key nghiệp vụ đang lưu bằng SQLite `TEXT`, nên không cần migration kiểu cột để chấp nhận UUID.

Từ DB-7, các record mới thuộc nhóm quản lý ít rủi ro dùng ID dạng:

```text
<entity-prefix>-<uuid-v4>
```

Áp dụng cho:

- `customers`
- `services`
- `employees`
- `retail_products`
- `service_formulas`

Ví dụ:

```text
customer-550e8400-e29b-41d4-a716-446655440000
```

Quy tắc tương thích:

- ID cũ không bị rewrite.
- Update record phải giữ nguyên ID.
- Foreign key vẫn là `TEXT`; không có migration schema.
- Không dùng phone/name/timestamp làm identity mới cho các entity trên.

### 3. Timestamp baseline

Các top-level business entity sau đã có `created_at` và `updated_at`:

- `customers`
- `employees`
- `services`
- `service_formulas`
- `retail_products`
- `appointments`
- `invoices`

Đây là baseline đủ để audit lịch sử thay đổi local. Chưa coi các timestamp này là protocol sync.

### 4. Những thứ cố ý chưa sync-ready

Các điểm dưới đây **không sửa trong DB-7** vì chưa có phone/sync phase và chưa có conflict semantics:

- `appointments` và invoice archive hiện vẫn dùng ID local hiện có; phải chuẩn hóa identity trước khi cho nhiều client cùng tạo record.
- `appointment_services` và `invoice_items` là child rows, chưa có `created_at`/`updated_at`; chỉ bổ sung khi child-level sync thực sự cần.
- `invoice-draft-001` là sentinel draft cục bộ, không phải entity để đồng bộ.
- `app_settings` là runtime metadata của SQLite; settings người dùng hiện còn ownership qua `LocalSettingsStore`/SharedPreferences và không được tự động biến thành sync entity.
- Chưa thêm `deleted_at`. Chỉ thêm khi business đã chốt soft-delete/tombstone semantics.
- Chưa thêm `version`/revision. Chỉ thêm khi có conflict/version protocol thật.

## Điều kiện trước khi bắt đầu phone sync

Trước khi xây phone client hoặc sync engine phải có một scope riêng để chốt tối thiểu:

1. authority: desktop, server hay multi-writer;
2. identity cho `appointments`, `invoices` và child rows;
3. conflict semantics cho update đồng thời;
4. delete/tombstone semantics;
5. revision/version semantics;
6. transport/API boundary và authentication;
7. ownership của settings nào là per-device, per-salon hay syncable.

DB-7 không tự quyết các điểm này.

## Safety

- Không tăng `DatabaseSchema.version`.
- Không chạy migration.
- Không reset/xóa dữ liệu.
- Không đổi auth/permission/business flow.
- Không thêm menu/UI mới.
- Không thêm cloud hoặc phone runtime.
