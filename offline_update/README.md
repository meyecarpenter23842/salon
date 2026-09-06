# Legacy offline updater

Tài liệu này được giữ lại để ghi nhận hướng update offline cũ của Salon, nhưng **không còn là quy trình release hiện hành**.

Kênh Windows hiện tại đã chuyển sang:

- Flutter Windows native giữ nguyên;
- NSIS installer cho chọn ổ/thư mục cài;
- public Cloudflare R2 feed;
- tải update có progress + SHA-256;
- restart và chỉ xác nhận thành công sau khi app chạy đúng version mới;
- build/release ở máy local, CI chỉ test/verify;
- không scan/copy/adopt/migrate data từ portable hoặc app cũ bên ngoài.

Xem quy trình chuẩn tại:

- `WINDOWS_RELEASE.md`
- `GO_LIVE_DESKTOP_CHECKLIST.md`

Không dùng `offline_update/version.json.example` cho release mới.
