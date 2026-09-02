#!/usr/bin/env python3
# -*- coding: utf-8 -*-
import sys
import io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')

files_to_fix = [
    'lib/features/appointments/presentation/pages/appointments_page.dart',
    'lib/features/services/presentation/pages/services_page.dart',
    'lib/features/reports/presentation/pages/reports_page.dart',
]

for filepath in files_to_fix:
    try:
        with open(filepath, 'rb') as f:
            content_bytes = f.read()
        
        content_latin1 = content_bytes.decode('iso-8859-1')
        content_utf8_bytes = content_latin1.encode('utf-8')
        
        with open(filepath, 'wb') as f:
            f.write(content_utf8_bytes)
        
        print(f'✓ Fixed {filepath.split("/")[-1]}')
    except Exception as e:
        print(f'✗ Error in {filepath}: {e}')

print('Done!')
