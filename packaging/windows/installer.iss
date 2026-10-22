; Windows installer, built by the Release workflow with Inno Setup 6:
;   python wizard_images.py <images>
;   iscc /DVersion=1.0.0 /DBuild=<folder of the exported app> /DImages=<images> /O<output folder> installer.iss
; Installs for the current user (no administrator rights needed), makes spritesheetbelli
; the app that opens .sbelli projects, and offers it in "Open with" for the files it can
; import, without taking them over. The native library is installed when the export has it.

#define App "spritesheetbelli"
#define ProgId "spritesheetbelli.project"
#define AppKey "Software\Classes\Applications\" + App + ".exe"
#ifndef Version
	#define Version "0.0.0"
#endif
#ifndef Build
	#define Build "..\..\build\windows"
#endif
#ifndef Images
	#define Images "..\..\build\wizard"
#endif

[Setup]
AppId={#App}
AppName={#App}
AppVersion={#Version}
AppVerName={#App} {#Version}
AppPublisher=Caleb Tognoli
AppPublisherURL=https://github.com/caleb-tognoli/spritesheetbelli
VersionInfoVersion={#Version}
PrivilegesRequired=lowest
; %LOCALAPPDATA%\Programs, as installing for the current user
DefaultDirName={autopf}\{#App}
DisableProgramGroupPage=yes
DisableReadyPage=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
WizardImageFile={#Images}\side-164.bmp,{#Images}\side-192.bmp,{#Images}\side-246.bmp,{#Images}\side-273.bmp,{#Images}\side-328.bmp,{#Images}\side-383.bmp,{#Images}\side-410.bmp
WizardSmallImageFile={#Images}\corner-55.bmp,{#Images}\corner-64.bmp,{#Images}\corner-69.bmp,{#Images}\corner-83.bmp,{#Images}\corner-92.bmp,{#Images}\corner-110.bmp,{#Images}\corner-119.bmp,{#Images}\corner-138.bmp
WizardImageAlphaFormat=defined
SetupIconFile=..\..\assets\branding\icon.ico
UninstallDisplayIcon={app}\{#App}.exe
UninstallDisplayName={#App}
OutputBaseFilename={#App}-{#Version}-windows-setup
Compression=lzma2/max
SolidCompression=yes
; Tells Explorer the file types changed, after installing and after uninstalling
ChangesAssociations=yes

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "it"; MessagesFile: "compiler:Languages\Italian.isl"

[Messages]
; Choosing the folder is the last step before installing, see CurPageChanged
en.SelectDirBrowseLabel=To install, click Install. If you would like to select a different folder, click Browse.
it.SelectDirBrowseLabel=Per installare seleziona "Installa".%nPer scegliere un'altra cartella seleziona "Sfoglia".

[Files]
Source: "{#Build}\{#App}.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#Build}\sbelli_native.windows.x86_64.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{autoprograms}\{#App}"; Filename: "{app}\{#App}.exe"

; The files it imports: offered in "Open with", never made the default
#dim Types[9] {".sbelli", ".png", ".jpg", ".jpeg", ".jpe", ".webp", ".gif", ".json", ".atlas"}
#define I

#sub OpenWith
Root: HKCU; Subkey: "Software\Classes\{#Types[I]}"; Flags: uninsdeletekeyifempty
Root: HKCU; Subkey: "Software\Classes\{#Types[I]}\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue uninsdeletekeyifempty
Root: HKCU; Subkey: "{#AppKey}\SupportedTypes"; ValueType: string; ValueName: "{#Types[I]}"; ValueData: ""
#endsub

[Registry]
; How the files it opens look and open
Root: HKCU; Subkey: "Software\Classes\{#ProgId}"; ValueType: string; ValueName: ""; ValueData: "spritesheetbelli project"; Flags: uninsdeletekey
Root: HKCU; Subkey: "Software\Classes\{#ProgId}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#App}.exe,0"
Root: HKCU; Subkey: "Software\Classes\{#ProgId}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#App}.exe"" ""%1"""
Root: HKCU; Subkey: "{#AppKey}"; ValueType: string; ValueName: "FriendlyAppName"; ValueData: "{#App}"; Flags: uninsdeletekey
Root: HKCU; Subkey: "{#AppKey}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#App}.exe,0"
Root: HKCU; Subkey: "{#AppKey}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#App}.exe"" ""%1"""
#for {I = 0; I < DimOf(Types); I++} OpenWith
; .sbelli projects open with it by default. Listed after the entries above, as uninstalling
; goes backwards: the key is let go once these are gone. Its default is taken back in [Code],
; unless another app took .sbelli over since.
Root: HKCU; Subkey: "Software\Classes\.sbelli"; ValueType: string; ValueName: ""; ValueData: "{#ProgId}"
Root: HKCU; Subkey: "Software\Classes\.sbelli"; ValueType: string; ValueName: "Content Type"; ValueData: "application/x-spritesheetbelli"; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{#App}.exe"; Description: "{cm:LaunchProgram,{#App}}"; Flags: nowait postinstall skipifsilent

[Code]
// With no Ready page, choosing the folder is the last step before installing
procedure CurPageChanged(CurPageID: Integer);
begin
	if CurPageID = wpSelectDir then
		WizardForm.NextButton.Caption := SetupMessage(msgButtonInstall);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
	Opener: String;
begin
	if (CurUninstallStep = usUninstall)
		and RegQueryStringValue(HKCU, 'Software\Classes\.sbelli', '', Opener)
		and (Opener = '{#ProgId}') then
		RegDeleteValue(HKCU, 'Software\Classes\.sbelli', '');
end;
