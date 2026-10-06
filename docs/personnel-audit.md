# Audit nhân sự và thứ tự triển khai sau V1

## Audit mục nhân sự — 06/10/2026
Nguồn đọc: main `6a855c635b0133a9926fd01e2e8c47b7b8efb5a1`, 1.8.6+18/schema 20. #111 phần CI/fixture/hướng dẫn đã xong; owner chưa có điện thoại, gate thật vẫn chờ. Không xem #111 đã nghiệm thu hoặc đóng #104.

### Đã có
- employee_id trên từng invoice_items, gán/tách dòng và giữ attribution qua checkout (test invoice_employee_flow, issue_78_pos_employee_attribution, employee_attribution_status_regression).
- Phân bổ giảm giá toàn bill xuống dòng một cách deterministic, chỉ doanh thu hóa đơn đã trả không có refund/void; profile tính doanh thu dịch vụ cho nhân viên (invoice_revenue_allocation + issue_45_reporting_semantics).
- Owner/PIN/audit và tiền mặt/ca thu ngân hiện có; ca thu ngân không phải bảng chấm công của nhân viên.

### Thiếu / rủi ro phải giải quyết
1. sqlite_employees_repository.dart:83–84 tính estimatedCommission từ doanh thu tháng nhân commission_rate **hiện tại**. Không có snapshot tỷ lệ tại giao dịch hoặc hiệu lực theo ngày; đổi tỷ lệ làm ước tính cả tháng đổi. UI employees_page.dart:628 ghi “Hoa hồng”, dễ nhầm đã được chốt/đã trả.
2. employees.commission_label là text; parser bỏ % và đọc số/100, không có validation domain 0–100/non-finite; text không đọc được thành rate 0. KPI text không có chính sách tính/chứng từ.
3. Chưa có commission accrual/payout/adjustment ledger, trạng thái chốt/đã trả, số còn phải trả hoặc liên kết chứng từ trả tiền. retail_products.commission_percent được lưu nhưng UI nói rõ chưa tính hoa hồng bán lẻ; không được tự biến thành khoản phải trả.
4. Không tìm thấy attendance/payroll/salary/payout domain/table/repository. shift_label/today_schedule chỉ là text hiển thị; cashier_shifts/cash_movements không chứng minh có mặt hoặc chi lương.
5. Chức danh role đang là text và danh sách UI hardcode; khác hoàn toàn PhoneWriteRole/Owner PIN. Thay chức danh không được cấp quyền bảo mật.
6. _fetchServiceHistory đọc total_price dòng và không loại adjustment như tổng doanh thu net; phải giữ nhãn/lịch sử giao dịch phù hợp, không dùng list này làm sổ quyết toán hoa hồng.

### Đối chiếu #55
Code hiện đã có today-only không fallback, filter/search/isPaid guards, header/list/rail và --staff-window. Baseline hỗ trợ nhiều billing sessions qua PR trước; giả định “global draft, không multi-bill” của issue #55 đã cũ. #110 thêm cross-process refresh; CI #374 có dual-process Staff smoke. Đây là bằng chứng code/CI, không chứng minh manual smoke/owner mockup nghiệm thu. **Không tick/đóng #55**, không viết payroll/chấm công vào workstation, không làm trùng redesign.

### Quyết định triển khai
Tách issue nhỏ trước code. Làm theo thứ tự: làm rõ ước tính và input hồ sơ → hoa hồng/chốt/chi trả theo quy tắc owner → chấm công → payroll → danh mục chức danh (tách quyền). Giữ chứng từ đã trả và attribution; không tính lại hồi tố âm thầm, không bịa hoa hồng cũ hoặc tiền đã trả từ báo cáo ước tính.
Chờ owner chốt cơ sở hoa hồng, chu kỳ chi trả, bán lẻ và hoàn/hủy sau chi trả trước khi tạo nghĩa vụ tiền. Không tự chọn chính sách lương/thuế/OT/nghỉ/bù trừ. Chi phí/công nợ/gói/remote/unit consumption tiếp tục là các nhánh sau, chưa triển khai.


## Các lô nhỏ

1. [#124](https://github.com/meyecarpenter23842/salon/issues/124): làm rõ ước tính; nhãn và ghi chú hồ sơ được sửa, không đổi công thức/tỷ lệ/schema/attribution.
2. [#125](https://github.com/meyecarpenter23842/salon/issues/125): sổ hoa hồng và chi trả; phải chốt quy tắc owner trước tính nghĩa vụ tiền.
3. [#126](https://github.com/meyecarpenter23842/salon/issues/126): chấm công; không suy từ cashier shift/lịch hẹn.
4. [#127](https://github.com/meyecarpenter23842/salon/issues/127): payroll theo kỳ; cần đầu vào chính sách lương/công, chống cộng hoa hồng đã trả hai lần.

Sau các lô này tiếp tục danh mục chức danh, chi phí/công nợ, membership/gói và các nhánh #112. Không tự mở scope cloud/offline mutation hoặc truy cập từ xa trước nghiệm thu LAN.

## Bằng chứng nguồn đã đối chiếu

- [Công thức hồ sơ nhân viên](https://github.com/meyecarpenter23842/salon/blob/6a855c635b0133a9926fd01e2e8c47b7b8efb5a1/lib/core/repositories/sqlite_employees_repository.dart#L83).
- [Phân bổ doanh thu hóa đơn](https://github.com/meyecarpenter23842/salon/blob/6a855c635b0133a9926fd01e2e8c47b7b8efb5a1/lib/core/repositories/invoice_revenue_allocation.dart#L94).
- [Schema nghiệp vụ hiện tại](https://github.com/meyecarpenter23842/salon/blob/6a855c635b0133a9926fd01e2e8c47b7b8efb5a1/lib/core/database/database_schema.dart).
- [Mục nhân sự và các issue phụ](https://github.com/meyecarpenter23842/salon/issues/112); #55 giữ riêng và chưa nghiệm thu manual.
