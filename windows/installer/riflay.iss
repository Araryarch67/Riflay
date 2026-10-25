; Windows installer (Inno Setup 6). Built by the release workflow:
;   iscc /DAppVersion=1.2.3 /DSourceDir=<Release folder> /DOutputDir=dist windows\installer\riflay.iss
; Installs for the current user only, so no administrator prompt.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif
#ifndef OutputDir
  #define OutputDir "..\..\dist"
#endif

[Setup]
AppId={{DC558C20-B893-4F78-A05F-6E08F3F2435E}
AppName=Riflay
AppVersion={#AppVersion}
AppPublisher=Riflay
AppPublisherURL=https://github.com/Araryarch67/Riflay
DefaultDirName={localappdata}\Programs\Riflay
DefaultGroupName=Riflay
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=Riflay-windows-x64-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\riflay.exe
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Riflay"; Filename: "{app}\riflay.exe"
Name: "{autodesktop}\Riflay"; Filename: "{app}\riflay.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\riflay.exe"; Description: "{cm:LaunchProgram,Riflay}"; Flags: nowait postinstall skipifsilent

[Code]
const
  // OpenMusic, as Riflay was called before 2.0, installed under an id of its own.
  OldAppUninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{6F1D2C7E-4B9A-4E8B-9E7A-0C3F5B2A9D41}_is1';

// OpenMusic goes first, so the Start menu doesn't keep both. Its settings, library
// and sign-in stay in AppData: Riflay brings them over when it first starts.
procedure CurStepChanged(CurStep: TSetupStep);
var
  Uninstaller: String;
  ResultCode: Integer;
begin
  if (CurStep = ssInstall) and RegQueryStringValue(HKCU, OldAppUninstallKey, 'UninstallString', Uninstaller) then
    Exec(RemoveQuotes(Uninstaller), '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;
