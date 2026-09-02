#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys
import io

# Fix Windows encoding issues
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

filepath = 'lib/features/settings/presentation/pages/settings_page.dart'

# Đọc file
with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
    content = f.read()

# Sửa từng mojibake pattern được xác định từ grep
# Pattern 1: 'KhÃ´ng táº£i Ä'Æ°á»£c cÃ i Ä'áº·t'
content = content.replace('KhÃ´ng táº£i Ä\'Æ°á»£c cÃ i Ä\'áº·t', 'Không tải được cài đặt')

# Pattern 2: 'Äang kiá»ƒm tra'
content = content.replace('Äang kiá»ƒm tra', 'Đang kiểm tra')

# Pattern 3: 'Template hiá»‡n táº¡i'
content = content.replace('Template hiá»‡n táº¡i', 'Template hiện tại')

# Pattern 4: 'Tiá»n tá»‡'
content = content.replace('Tiá»n tá»‡', 'Tiền tệ')

# Pattern 5: 'Nháº¯c lá»‹ch'
content = content.replace('Nháº¯c lá»‹ch', 'Nhắc lịch')

# Pattern 6: 'Version hiá»‡n táº¡i'
content = content.replace('Version hiá»‡n táº¡i', 'Version hiện tại')

# Pattern 7: 'Kiá»ƒm tra cáº­p nháº­t'
content = content.replace('Kiá»ƒm tra cáº­p nháº­t', 'Kiểm tra cập nhật')

# Pattern 8: 'Giao diá»‡n salon'
content = content.replace('Giao diá»‡n salon', 'Giao diện salon')

# Pattern 9: 'Thiáº¿t láº­p cá»¥c bá»™'
content = content.replace('Thiáº¿t láº­p cá»¥c bá»™', 'Thiết lập cơ bản')

# Pattern 10: 'Chá»‰nh sá»­a thiáº¿t láº­p cá»¥c bá»™'
content = content.replace('Chá»‰nh sá»­a thiáº¿t láº­p cá»¥c bá»™', 'Chỉnh sửa thiết lập cơ bản')

# Pattern 11: 'Chá»‰nh sá»­a'
content = content.replace('Chá»‰nh sá»­a', 'Chỉnh sửa')

# Pattern 12: 'Nguá»"n update offline'
content = content.replace('Nguá»"n update offline', 'Nguồn update offline')

# Pattern 13: 'Cháº¿ Ä'á»™ kiá»ƒm tra update'
content = content.replace('Cháº¿ Ä\'á»™ kiá»ƒm tra update', 'Chế độ kiểm tra update')

# Pattern14: 'Thá»§ cÃ´ng trong CÃ i Ä'áº·t'
content = content.replace('Thá»§ cÃ´ng trong CÃ i Ä\'áº·t', 'Thử công trong Cài đặt')

# Pattern 15: 'Dá»¯ liá»‡u máº«u'
content = content.replace('Dá»¯ liá»‡u máº«u', 'Dữ liệu mẫu')

# Pattern 16: 'Template Ä'ang lÆ°u'
content = content.replace('Template Ä\'ang lÆ°u', 'Template đang lưu')

# Pattern 17: 'Báº£n má»›i nháº¥t'
content = content.replace('Báº£n má»›i nháº¥t', 'Bản mới nhất')

# Pattern 18: 'ChÆ°a cÃ³ manifest há»£p lá»‡'
content = content.replace('ChÆ°a cÃ³ manifest há»£p lá»‡', 'Chưa có manifest hợp lệ')

# Pattern 19: 'cÃ²n Ä'Æ°á»£c há»— trá»£'
content = content.replace('cÃ²n Ä\'Æ°á»£c há»— trá»£', 'còn được hỗ trợ')

# Pattern 20: 'Cáº§n update báº¯t buá»™c'
content = content.replace('Cáº§n update báº¯t buá»™c', 'Cần update bắt buộc')

# Pattern 21: 'Quyá»n má»Ÿ bá»™ cÃ i'
content = content.replace('Quyá»n má»Ÿ bá»™ cÃ i', 'Quyền mở bộ cài')

# Pattern 22: 'ChÆ°a Ä'Æ°á»£c phÃ©p'
content = content.replace('ChÆ°a Ä\'Æ°á»£c phÃ©p', 'Chưa được phép')

# Pattern 23: 'Äang táº£i bá»™ cÃ i'
content = content.replace('Äang táº£i bá»™ cÃ i', 'Đang tải bộ cài')

# Pattern 24: 'Táº£i vÃ  cÃ i Ä'áº·t'
content = content.replace('Táº£i vÃ  cÃ i Ä\'áº·t', 'Tải và cài đặt')

# Pattern 25: 'MÃ£ hÃ³a Ä'Æ¡n + SÄT khÃ¡ch'
content = content.replace('MÃ£ hÃ³a Ä\'Æ¡n + SÄT khÃ¡ch', 'Mã hóa đơn + SĐT khách')

# Pattern 26: 'Tá»± kiá»ƒm tra update offline'
content = content.replace('Tá»± kiá»ƒm tra update offline', 'Tự kiểm tra update offline')

# Pattern 27: 'App tá»± sinh vÃ  dÃ¹ng Ä'á»ƒ rÃ ng buá»™c quyá»n update theo mÃ¡y'
content = content.replace('App tá»± sinh vÃ  dÃ¹ng Ä\'á»ƒ rÃ ng buá»™c quyá»n update theo mÃ¡y', 'App tự sinh và dùng để rang buộc quyền update theo máy')

# Pattern 28: 'Nháº­p key Ä'Æ°á»£c cáº¥p Ä'á»ƒ kiá»ƒm tra quyá»n update'
content = content.replace('Nháº­p key Ä\'Æ°á»£c cáº¥p Ä\'á»ƒ kiá»ƒm tra quyá»n update', 'Nhập key được cấp để kiểm tra quyền update')

# Pattern 29: 'Báº­t' and 'Táº¯t'
content = content.replace('Báº­t', 'Bật')
content = content.replace('Táº¯t', 'Tắt')

# Pattern 30: 'Manifest Ä'ang Ä'á»c'
content = content.replace('Manifest Ä\'ang Ä\'á»c', 'Manifest đang đọc')

# Lưu file
with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)

print('Đã sửa xong settings_page.dart')
