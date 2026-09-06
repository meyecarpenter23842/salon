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

Name "Salon"
OutFile "${OUTPUT_DIR}\Salon-Setup-${PRODUCT_VERSION}.exe"
InstallDir "$LOCALAPPDATA\Programs\Salon"
InstallDirRegKey HKCU "Software\HairSpaManager" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma
SetCompressorDictSize 32
ShowInstDetails show
ShowUninstDetails show

VIProductVersion "${FILE_VERSION}"
VIAddVersionKey /LANG=1033 "ProductName" "Salon"
VIAddVersionKey /LANG=1033 "FileDescription" "Salon Windows Installer"
VIAddVersionKey /LANG=1033 "FileVersion" "${PRODUCT_VERSION}"
VIAddVersionKey /LANG=1033 "ProductVersion" "${PRODUCT_VERSION}"

!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\salonmanager.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Mở Salon"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Vietnamese"

Function .onInit
  SetShellVarContext current
  IfSilent 0 done
    ; Updater launches this installer while Salon is still running. Give the
    ; Flutter process time to flush state, then stop all Salon windows before
    ; replacing application binaries. Runtime data lives under AppData and is
    ; intentionally outside $INSTDIR.
    Sleep 800
    nsExec::ExecToLog 'taskkill /IM salonmanager.exe /F'
    Sleep 500
  done:
FunctionEnd

Section "Salon" SEC_MAIN
  SectionIn RO
  SetShellVarContext current
  SetOutPath "$INSTDIR"
  SetOverwrite on

  File /r "${BUILD_DIR}\*.*"

  WriteRegStr HKCU "Software\HairSpaManager" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Salon" "DisplayName" "Salon"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Salon" "DisplayVersion" "${PRODUCT_VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Salon" "Publisher" "Salon"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Salon" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\Salon" "UninstallString" '"$INSTDIR\Uninstall.exe"'

  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateShortcut "$DESKTOP\Salon.lnk" "$INSTDIR\salonmanager.exe"
  CreateDirectory "$SMPROGRAMS\Salon"
  CreateShortcut "$SMPROGRAMS\Salon\Salon.lnk" "$INSTDIR\salonmanager.exe"
  CreateShortcut "$SMPROGRAMS\Salon\Gỡ cài đặt Salon.lnk" "$INSTDIR\Uninstall.exe"

  ; Silent mode is used only by the in-app updater. Restart after files have
  ; been replaced so the next Flutter process can verify the new version.
  IfSilent 0 interactive_done
    Exec '"$INSTDIR\salonmanager.exe"'
  interactive_done:
SectionEnd

Section "Uninstall"
  SetShellVarContext current

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
