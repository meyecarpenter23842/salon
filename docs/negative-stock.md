# Xuất âm và cảnh báo tồn kho (#106)

POS desktop, Staff và lệnh ghi Android dùng cùng repository SQLite: thêm sản phẩm, tăng số lượng và checkout được vượt tồn. Checkout tạo dòng tồn nếu chưa nhập, ghi sale movement cùng hóa đơn trong một transaction. Journal điện thoại chống ghi lặp; retry sau khởi động lại không trừ thêm tồn.

Kho hàng phân biệt âm (đỏ, icon cảnh báo, nhãn Âm kho), hết (0), sắp hết và còn hàng. Bộ lọc có số sản phẩm âm; các chỉ số đếm sản phẩm, không cộng số lượng Chai/Cái/... thành một tổng. Ngưỡng sắp hết đặt trong sửa sản phẩm, mặc định 5; 0 tắt cảnh báo sắp hết. Schema 19 thêm cột ngưỡng với mặc định, giữ lịch sử và tồn cũ.

Nhập kho phải dương nhưng được bù từng phần: -5 + 3 = -2. Kiểm kê nhập số tồn thực tế không âm. Hủy hóa đơn hoàn đúng lượng đã bán một lần; hoàn tiền chỉ hoàn tiền, không tự coi là hàng đã trả. Hóa đơn cũ không có sale movement không cộng tồn giả.

CI kiểm tra nguồn, repository, journal, migration và widget; không thay thế kiểm thử trên điện thoại thật. Không chạy build/test app hoặc migration dữ liệu trên máy salon trong lô này.
