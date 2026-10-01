; Windows installer, built by the Release workflow with NSIS:
;   makensis -DVERSION=0.2.0 -DEXE=path/to/spritesheetbelli.exe -DOUTFILE=setup.exe installer.nsi
; Installs for the current user (no administrator rights needed), makes spritesheetbelli
; the app that opens .sbelli projects, and offers it in "Open with" for the files it can
; import, without taking them over.

Unicode true
SetCompressor /SOLID lzma
RequestExecutionLevel user
ManifestDPIAware true

!define APP "spritesheetbelli"
!define PROG_ID "spritesheetbelli.project"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP}"
!define APP_KEY "Software\Classes\Applications\${APP}.exe"

!include "MUI2.nsh"

Name "${APP}"
OutFile "${OUTFILE}"
InstallDir "$LOCALAPPDATA\Programs\${APP}"
InstallDirRegKey HKCU "${UNINSTALL_KEY}" "InstallLocation"

!define MUI_ICON "${__FILEDIR__}/../../assets/branding/icon.ico"
!define MUI_UNICON "${__FILEDIR__}/../../assets/branding/icon.ico"
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP}.exe"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Italian"

; The files it imports: offered in "Open with", never made the default
!macro IMPORTABLE_TYPES MACRO
	!insertmacro ${MACRO} ".png"
	!insertmacro ${MACRO} ".jpg"
	!insertmacro ${MACRO} ".jpeg"
	!insertmacro ${MACRO} ".jpe"
	!insertmacro ${MACRO} ".webp"
	!insertmacro ${MACRO} ".gif"
	!insertmacro ${MACRO} ".json"
	!insertmacro ${MACRO} ".atlas"
!macroend

!macro ADD_OPEN_WITH EXT
	WriteRegStr HKCU "Software\Classes\${EXT}\OpenWithProgids" "${PROG_ID}" ""
	WriteRegStr HKCU "${APP_KEY}\SupportedTypes" "${EXT}" ""
!macroend

!macro REMOVE_OPEN_WITH EXT
	DeleteRegValue HKCU "Software\Classes\${EXT}\OpenWithProgids" "${PROG_ID}"
	DeleteRegKey /ifempty HKCU "Software\Classes\${EXT}\OpenWithProgids"
	DeleteRegKey /ifempty HKCU "Software\Classes\${EXT}"
!macroend

Section
	SetOutPath "$INSTDIR"
	File "/oname=${APP}.exe" "${EXE}"
	WriteUninstaller "$INSTDIR\uninstall.exe"
	CreateShortcut "$SMPROGRAMS\${APP}.lnk" "$INSTDIR\${APP}.exe"

	; How the files it opens look and open
	WriteRegStr HKCU "Software\Classes\${PROG_ID}" "" "spritesheetbelli project"
	WriteRegStr HKCU "Software\Classes\${PROG_ID}\DefaultIcon" "" "$INSTDIR\${APP}.exe,0"
	WriteRegStr HKCU "Software\Classes\${PROG_ID}\shell\open\command" "" '"$INSTDIR\${APP}.exe" "%1"'
	; .sbelli projects open with it by default
	WriteRegStr HKCU "Software\Classes\.sbelli" "" "${PROG_ID}"
	WriteRegStr HKCU "Software\Classes\.sbelli" "Content Type" "application/x-spritesheetbelli"
	!insertmacro ADD_OPEN_WITH ".sbelli"
	!insertmacro IMPORTABLE_TYPES ADD_OPEN_WITH
	WriteRegStr HKCU "${APP_KEY}" "FriendlyAppName" "${APP}"
	WriteRegStr HKCU "${APP_KEY}\DefaultIcon" "" "$INSTDIR\${APP}.exe,0"
	WriteRegStr HKCU "${APP_KEY}\shell\open\command" "" '"$INSTDIR\${APP}.exe" "%1"'

	WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${APP}"
	WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
	WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "Caleb Tognoli"
	WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\${APP}.exe,0"
	WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
	WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
	WriteRegStr HKCU "${UNINSTALL_KEY}" "URLInfoAbout" "https://github.com/caleb-tognoli/spritesheetbelli"
	WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
	WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1

	; Tells Explorer the file types changed (SHCNE_ASSOCCHANGED)
	System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
SectionEnd

Section "Uninstall"
	Delete "$INSTDIR\${APP}.exe"
	Delete "$INSTDIR\uninstall.exe"
	RMDir "$INSTDIR"
	Delete "$SMPROGRAMS\${APP}.lnk"

	; Unless another app took .sbelli over since
	ReadRegStr $0 HKCU "Software\Classes\.sbelli" ""
	StrCmp $0 "${PROG_ID}" 0 +2
		DeleteRegValue HKCU "Software\Classes\.sbelli" ""
	DeleteRegValue HKCU "Software\Classes\.sbelli" "Content Type"
	!insertmacro REMOVE_OPEN_WITH ".sbelli"
	!insertmacro IMPORTABLE_TYPES REMOVE_OPEN_WITH
	DeleteRegKey HKCU "Software\Classes\${PROG_ID}"
	DeleteRegKey HKCU "${APP_KEY}"
	DeleteRegKey HKCU "${UNINSTALL_KEY}"

	System::Call 'shell32::SHChangeNotify(i 0x08000000, i 0, p 0, p 0)'
SectionEnd
