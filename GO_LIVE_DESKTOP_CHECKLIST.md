# Go-Live Checklist (Desktop Pilot)

## 1) Nguon cap nhat va bao mat
- [ ] `offlineUpdatePath` tro den nguon tin cay (SMB noi bo hoac HTTPS).
- [ ] Manifest co `latestVersion`, `downloadPath`, `sha256` hop le.
- [ ] Thu nghiem 1 lan hash mismatch de xac nhan app chan goi cai dat khong hop le.
- [ ] Kiem tra file log audit tao duoc tai `%APPDATA%/HairSpaManager/logs/update_audit.log`.

## 2) Kich ban van hanh update
- [ ] Mo Settings -> bam `Kiem tra cap nhat` -> nhan duoc ket qua ro rang.
- [ ] Khi co ban moi, top bar hien badge version moi.
- [ ] Bam `Tai va cai dat` -> app tai bo cai va mo installer.
- [ ] Neu loi tai/cai dat, app khong crash va thong bao loi de thu lai.

## 3) Kiem thu ky thuat
- [ ] `flutter analyze` pass.
- [ ] `flutter test` pass.
- [ ] `flutter build windows --release` pass.

## 4) Van hanh salon thuc te
- [ ] Chot nguoi phu trach update tai salon.
- [ ] Chot khung gio update (ngoai gio dong khach).
- [ ] Co huong dan rollback ve ban truoc neu installer loi.
- [ ] Co quy trinh backup du lieu truoc moi lan update.

## 5) Dieu kien go/no-go
- Go: Tat ca muc 1, 2, 3 pass va muc 4 da phan cong nguoi thuc hien.
- No-Go: Bat ky muc nao trong 1, 2, 3 fail hoac chua co backup/rollback ro rang.
