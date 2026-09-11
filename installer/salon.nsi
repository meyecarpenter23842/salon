Unicode true

!include "MUI2.nsh"
!include "LogicLib.nsh"

!ifndef PRODUCT_VERSION
  !error "PRODUCT_VERSION is required"
!endif
!ifndef FILE_VERSION
  !error "FILE_VERSION is required"
!endif
!ifndef BUILD_DIR
  !error "BUILD_DIR is required"
!endif
!ifndef OUTPUT_DIR
  !error "OUTPUT_DIR is required"
!endif
!ifndef APP_ICON
  !error "APP_ICON is required"
!endif

!define MUI_ICON "${APP_ICON}"
!define MUI_UNICON "${APP_ICON}"

Name "Hair Spa Manager"
OutFile "${OUTPUT_DIR}\Salon-Setup-${PRODUCT_VERSION}.exe"
InstallDir "$LOCALAPPDATA\Programs\Salon"
InstallDirRegKey HKCU "Software\HairSpaManager" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma
SetCompressorDictSize 32
ShowInstDetails show
ShowUninstDetails show

VIProductVersion "${FILE_VERSION}"
VIAddVersionKey /LANG=1033 "ProductName" "Hair Spa Manager"
VIAddVersionKey /LANG=1033 "FileDescription" "Hair Spa Manager Windows Installer"
VIAddVersionKey /LANG=1033 "FileVersion" "${PRODUCT_VERSION}"
VIAddVersionKey /LANG=1033 "ProductVersion" "${PRODUCT_VERSION}"

!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\salonmanager.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Mở Hair Spa Manager"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Vietnamese"

Function .onInit
  SetShellVarContext current
  ; Silent self-update is launched only after the external updater helper has
  ; confirmed all Salon processes exited. Never force-kill Salon from NSIS:
  ; SQLite must already be closed before application binaries are replaced.
FunctionEnd

Section "Hair Spa Manager" SEC_MAIN
  SectionIn RO
  SetShellVarContext current
  SetOutPath "$INSTDIR"
  SetOverwrite on

  File /r "${BUILD_DIR}\*.*"

  WriteRegStr HKCU "Software\HairSpaManager" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Salon" "DisplayName" "Hair Spa Manager"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Salon" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Salon" "Publisher" "Hair Spa Manager"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Salon" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Salon" "UninstallString" '"$INSTDIR\Uninstall.exe"'

  WriteUninstaller "$INSTDIR\Uninstall.exe"

  ; Remove legacy shortcut names before creating the canonical brand shortcuts.
  Delete "$DESKTOP\Salon.lnk"
  Delete "$SMPROGRAMS\Salon\Salon.lnk"
  Delete "$SMPROGRAMS\Salon\Gỡ cài đặt Salon.lnk"
  RMDir "$SMPROGRAMS\Salon"

  CreateShortcut "$DESKTOP\Hair Spa Manager.lnk" "$INSTDIR\salonmanager.exe"
  CreateDirectory "$SMPROGRAMS\Hair Spa Manager"
  CreateShortcut "$SMPROGRAMS\Hair Spa Manager\Hair Spa Manager.lnk" "$INSTDIR\salonmanager.exe"
  CreateShortcut "$SMPROGRAMS\Hair Spa Manager\Gỡ cài đặt Hair Spa Manager.lnk" "$INSTDIR\Uninstall.exe"

  ; Interactive installs use the MUI finish-page Run action above. Silent
  ; self-updates are restarted by the external helper only after this installer
  ; exits successfully, matching the Key Manager handoff model.
SectionEnd

Section "Uninstall"
  SetShellVarContext current

  Delete "$DESKTOP\Hair Spa Manager.lnk"
  Delete "$SMPROGRAMS\Hair Spa Manager\Hair Spa Manager.lnk"
  Delete "$SMPROGRAMS\Hair Spa Manager\Gỡ cài đặt Hair Spa Manager.lnk"
  RMDir "$SMPROGRAMS\Hair Spa Manager"

  ; Also clean up legacy shortcut names from older releases.
  Delete "$DESKTOP\Salon.lnk"
  Delete "$SMPROGRAMS\Salon\Salon.lnk"
  Delete "$SMPROGRAMS\Salon\Gỡ cài đặt Salon.lnk"
  RMDir "$SMPROGRAMS\Salon"

  ; Only remove known application payload. Never touch %APPDATA% or
  ; %LOCALAPPDATA%\HairSpaManager runtime data/backups.
  Delete "$INSTDIR\salonmanager.exe"
  Delete "$INSTDIR\*.dll"
  Delete "$INSTDIR\*.exe.manifest"
  RMDir /r "$INSTDIR\data"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"

  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Salon"
  DeleteRegKey HKCU "Software\HairSpaManager"
SectionEnd
