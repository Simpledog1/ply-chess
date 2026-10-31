; Inno Setup script for the Ply Windows installer.
; Build the app first:  flutter build windows --release
; Then:                 ISCC.exe installer\ply.iss
; Output:               build\installer\Ply-Setup-<version>.exe

#define AppVersion "1.2.1"

[Setup]
; Keep this AppId fixed so new versions upgrade the existing install.
AppId={{FC92003B-6D53-4B32-8F12-4637AEF9C7BA}
AppName=Ply
AppVersion={#AppVersion}
AppVerName=Ply {#AppVersion}
AppPublisher=Bernard M. Rodriguez Jr.
AppPublisherURL=https://github.com/Simpledog1/ply-chess
AppSupportURL=https://github.com/Simpledog1/ply-chess/issues
AppComments=Every move teaches. Personal chess analysis with Stockfish.
; Per-user install: no administrator rights needed.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
DefaultDirName={autopf}\Ply
DisableProgramGroupPage=yes
DisableDirPage=auto
OutputDir=..\build\installer
OutputBaseFilename=Ply-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\Ply.exe
UninstallDisplayName=Ply
LicenseFile=installer_license.txt
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
; Close a running Ply before upgrading or uninstalling.
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\Ply"; Filename: "{app}\Ply.exe"; Comment: "Chess analysis with Stockfish"
Name: "{autodesktop}\Ply"; Filename: "{app}\Ply.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Ply.exe"; Description: "Launch Ply"; Flags: nowait postinstall skipifsilent

; Settings and saved history live in %APPDATA%\Simpledog1\Ply and are kept on
; uninstall, so reinstalling keeps them. Delete them from Ply (Settings ->
; Profiles & privacy) before uninstalling to remove everything.
