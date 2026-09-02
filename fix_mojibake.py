#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys

def fix_file(filepath):
    # Đọc file
    with open(filepath, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    
    # Danh sách các thay thế từ mojibake sang UTF-8 đúng
    replacements = {
        # Các pattern lỗi cần sửa, thêm nhiều biến thể
        'KhÃ´ng táº£i Ä\'Æ°á»£c cÃ i Ä\'áº·t': 'Không tải được cài đặt',
        'Khôngáº£i Ä\u0091Æ°a»£c cÃ i Ä\u0091áº·t': 'Không tải được cài đặt',
        'Äang kiá»ƒm tra': 'Đang kiểm tra',
        'Kiá»ƒm tra cáº­p nháº­t': 'Kiểm tra cập nhật',
        'Template hiá»‡n táº¡i': 'Template hiện tại',
        'Tiá»n tá»‡': 'Tiền tệ',
        'Nháº¯c lá»‹ch': 'Nhắc lịch',
        'Version hiá»‡n táº¡i': 'Version hiện tại',
        'Giao diá»‡n salon': 'Giao diện salon',
        'Thiáº¿t láº­p cá»¥c bá»™': 'Thiết lập cơ bản',
        'Chá»‰nh sá»­a thiáº¿t láº­p cá»¥c bá»™': 'Chỉnh sửa thiết lập cơ bản',
        'Chá»‰nh sá»­a': 'Chỉnh sửa',
        'Nguá»"n update offline': 'Nguồn update offline',
        'Cháº¿ Ä\'á»™ kiá»ƒm tra update': 'Chế độ kiểm tra update',
        'Thá»§ cÃ´ng trong CÃ i Ä\'áº·t': 'Thử công trong Cài đặt',
        'Dá»¯ liá»‡u máº«u': 'Dữ liệu mẫu',
        'Template Ä\'ang lÆ°u': 'Template đang lưu',
        'Báº­t': 'Bật',
        'Táº¯t': 'Tắt',
        'Manifest Ä\'ang Ä\'á»c': 'Manifest đang đọc',
        'Báº£n má»›i nháº¥t': 'Bản mới nhất',
        'ChÆ°a cÃ³ manifest há»£p lá»‡': 'Chưa có manifest hợp lệ',
        'cÃ²n Ä\'Æ°á»£c há»— trá»£': 'còn được hỗ trợ',
        'Cáº§n update báº¯t buá»™c': 'Cần update bắt buộc',
        'Quyá»n má»Ÿ bá»™ cÃ i': 'Quyền mở bộ cài',
        'ChÆ°a Ä\'Æ°á»£c phÃ©p': 'Chưa được phép',
        'Äang táº£i bá»™ cÃ i': 'Đang tải bộ cài',
        'Táº£i vÃ  cÃ i Ä\'áº·t': 'Tải và cài đặt',
        'MÃ£ hÃ³a Ä\'Æ¡n + SÄT khÃ¡ch': 'Mã hóa đơn + SĐT khách',
        'Tá»± kiá»ƒm tra update offline': 'Tự kiểm tra update offline',
        'App tá»± sinh vÃ  dÃ¹ng Ä\'á»ƒ rÃ ng buá»™c quyá»n update theo mÃ¡y': 'App tự sinh và dùng để rang buộc quyền update theo máy',
        'Nháº­p key Ä\'Æ°á»£c cáº¥p Ä\'á»ƒ kiá»ƒm tra quyá»n update': 'Nhập key được cấp để kiểm tra quyền update',
    }
    
    original_len = len(content)
    for bad, good in replacements.items():
        if bad in content:
            count = content.count(bad)
            content = content.replace(bad, good)
            print(f'Thay thế {count}x: {bad[:30]}... -> {good[:30]}...')
    
    # Ghi file
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    
    print(f'Sửa xong {filepath}')

if __name__ == '__main__':
    import sys
    filepath = sys.argv[1] if len(sys.argv) > 1 else 'lib/features/overview/presentation/pages/overview_page.dart'

    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Build exact search strings using chr() from known hex dumps
    # Line 224: 'Overview Ä[U+2018]ang dÃ¹ng dá»¯ liá»[U+2021]u demo'
    s224 = ('Overview ' + chr(0xC4) + chr(0x2018) + 'ang d'
            + chr(0xC3) + chr(0xB9) + 'ng d'
            + chr(0xE1) + chr(0xBB) + chr(0xAF)
            + ' li' + chr(0xE1) + chr(0xBB) + chr(0x2021) + 'u demo')

    # Line 582: lịch hiá»[U+0192]n thá»[U+2039]  (0x83→U+0192=ƒ; 0x8B→U+2039=‹ in CP1252)
    s582 = ('lịch hi' + chr(0xE1) + chr(0xBB) + chr(0x0192) + 'n th'
            + chr(0xE1) + chr(0xBB) + chr(0x2039))

    # Line 62: 'ÄÃ£ Ä'áº·t' = Đã đặt  (Đ creates Ä+U+0090, ã creates Ã+£, đ creates Ä+U+2018)
    s62 = (chr(0xC4) + chr(0x90) + chr(0xC3) + chr(0xA3) + ' '
           + chr(0xC4) + chr(0x2018) + chr(0xE1) + chr(0xBA) + chr(0xB7) + 't')

    # Line 895: KhÃ¡ch Ä[?]ang ch[á»][U+008D]n
    s895 = ('KhÃ¡ch ' + chr(0xC4) + chr(0x2018) + 'ang ch'
            + chr(0xE1) + chr(0xBB) + chr(0x8D) + 'n')
    s895b = ('KhÃ¡ch ' + chr(0xC4) + chr(0x2018) + 'ang ch'
             + chr(0xE1) + chr(0xBB) + chr(0x008D) + 'n')

    fixes = [
        (s224, 'Overview đang dùng dữ liệu demo'),
        (s582, 'lịch hiển thị'),
        (s62, 'Đã đặt'),
        (s895, 'Khách đang chọn'),
        (s895b, 'Khách đang chọn'),
    ]

    original = content
    for old, new in fixes:
        if old in content:
            content = content.replace(old, new)
            print(f'Fixed: {repr(old[:50])} -> {repr(new[:30])}')
        else:
            print(f'Skip : {repr(old[:50])}')

    if content != original:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        print('Saved.')
    else:
        print('No changes.')




