#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys
import io

# Fix Windows encoding issues
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

filepath = 'lib/features/settings/presentation/pages/settings_page.dart'

# Đọc file dưới dạng Latin-1 (môj ibake), rồi lưu lại as UTF-8
with open(filepath, 'rb') as f:
    content_bytes = f.read()

# Thử tất cả các encoding để tìm cái có HTML entities hoặc mojibake
try:
    # Nếu file chứa UTF-8 bytes được lưu như Latin-1, hãy fix
    content_latin1 = content_bytes.decode('iso-8859-1')
    # Encode lại thành UTF-8
    content_utf8_bytes = content_latin1.encode('utf-8')
    # Write back
    with open(filepath, 'wb') as f:
        f.write(content_utf8_bytes)
    print('Fixed file encoding from ISO-8859-1 to UTF-8')
except Exception as e:
    print(f'Error: {e}')
