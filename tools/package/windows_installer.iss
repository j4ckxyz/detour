; Inno Setup script for the Windows installer (CI: .github/workflows/build.yml).
;   iscc /DAppVersion=0.1.0 /DSourceDir=export\windows /DOutputDir=dist tools\package\windows_installer.iss
; Installs per user by default (no admin prompt); the installer offers an all-users install.

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\export\windows"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
AppId={{BD084C10-139D-4E66-B28E-C60C779AE76D}
AppName=Detour
AppVersion={#AppVersion}
AppPublisher=Detour contributors
AppPublisherURL=https://github.com/j4ckxyz/detour
AppSupportURL=https://github.com/j4ckxyz/detour/issues
DefaultDirName={autopf}\Detour
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=Detour-Setup-x86_64
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\Detour.exe

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs

[Icons]
Name: "{autoprograms}\Detour"; Filename: "{app}\Detour.exe"
Name: "{autodesktop}\Detour"; Filename: "{app}\Detour.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Detour.exe"; Description: "{cm:LaunchProgram,Detour}"; Flags: nowait postinstall skipifsilent
; The in-game updater runs this installer with /SILENT: start the game again afterwards.
Filename: "{app}\Detour.exe"; Flags: nowait; Check: WizardSilent
