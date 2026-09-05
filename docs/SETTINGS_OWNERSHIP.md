# Settings ownership

Salon separates settings by ownership so editing one group cannot overwrite another.

## Business data (SQLite, included in database backup)

- Salon name, VND currency, appointment reminder.
- Bank name, account number, account holder and transfer-content template.
- Receipt content/layout: salon receipt identity, address/phone/tagline, visibility toggles, font/layout, footer text and QR visibility.

## Device data (SharedPreferences, stays on each Windows machine)

- Offline update path, updater license, device id/name.
- Receipt output device choices: printer, paper size, copy count, local logo file path and logo visibility.

The current app supports VND only. The generated checkout QR is an internal text QR containing transfer information; it is **not** a VietQR/NAPAS-standard banking QR. Uploaded-QR modes are not shown or used until a real configuration flow exists.
