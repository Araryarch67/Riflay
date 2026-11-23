; Windows installer (Inno Setup 6). Built by the release workflow:
;   iscc /DAppVersion=1.0.0 /DSourceDir=<Release folder> /DOutputDir=dist windows\installer\riflay.iss
; Installs for the current user only, so no administrator prompt.

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
; VersionInfo fields take numbers only (1.3.0 for a release candidate's 1.3.0-rc1).
#ifndef NumericVersion
  #define NumericVersion AppVersion
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
VersionInfoVersion={#NumericVersion}
VersionInfoTextVersion={#AppVersion}
VersionInfoProductVersion={#NumericVersion}
VersionInfoProductTextVersion={#AppVersion}
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
SetupMutex=RiflaySetup
; {app}\bin goes on the user's PATH: Explorer and new terminals see it without signing out.
ChangesEnvironment=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; Only the two commands go on PATH, not the app's folder: its DLLs would be found by other programs' searches.
Source: "{#SourceDir}\riflay-cli.exe"; DestDir: "{app}\bin"; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#SourceDir}\riflay-tui.exe"; DestDir: "{app}\bin"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{autoprograms}\Riflay"; Filename: "{app}\riflay.exe"
Name: "{autodesktop}\Riflay"; Filename: "{app}\riflay.exe"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Environment"; ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}\bin"; Check: NeedsPath('{app}\bin')

[Run]
Filename: "{app}\riflay.exe"; Description: "{cm:LaunchProgram,Riflay}"; Flags: nowait postinstall skipifsilent
Filename: "{app}\riflay.exe"; Flags: nowait skipifnotsilent; Check: IsRiflayUpdate

[CustomMessages]
RiflayCloseForUpdate=Close Riflay and run the update again.

[Code]
const
  // OpenMusic, as Riflay was called before (up to 1.11.1), installed under an id of its own.
  OldAppUninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{6F1D2C7E-4B9A-4E8B-9E7A-0C3F5B2A9D41}_is1';

function OpenProcess(Access: LongWord; InheritHandle: Boolean; ProcessId: LongWord): LongWord;
  external 'OpenProcess@kernel32.dll stdcall';
function WaitForSingleObject(Handle, Timeout: LongWord): LongWord;
  external 'WaitForSingleObject@kernel32.dll stdcall';
function CloseHandle(Handle: LongWord): Boolean;
  external 'CloseHandle@kernel32.dll stdcall';

function NeedsPath(Dir: String): Boolean;
var
  Path: String;
begin
  Dir := ExpandConstant(Dir);
  if not RegQueryStringValue(HKCU, 'Environment', 'Path', Path) then
    Path := '';
  Result := Pos(';' + Uppercase(Dir) + ';', ';' + Uppercase(Path) + ';') = 0;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Path, Dir: String;
  At: Integer;
begin
  if CurUninstallStep <> usPostUninstall then Exit;
  if not RegQueryStringValue(HKCU, 'Environment', 'Path', Path) then Exit;
  Dir := ExpandConstant('{app}\bin');
  At := Pos(';' + Uppercase(Dir) + ';', ';' + Uppercase(Path) + ';');
  if At = 0 then Exit;
  Delete(Path, At, Length(Dir) + 1);
  if (Length(Path) > 0) and (Path[Length(Path)] = ';') then
    Delete(Path, Length(Path), 1);
  RegWriteExpandStringValue(HKCU, 'Environment', 'Path', Path);
end;

function IsRiflayUpdate: Boolean;
begin
  Result := StrToIntDef(ExpandConstant('{param:RIFLAYPID|0}'), 0) > 0;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ProcessHandle: LongWord;
begin
  Result := '';
  if not IsRiflayUpdate then Exit;
  // Riflay saves and exits itself. Never replace the files while it is still holding them open.
  ProcessHandle := OpenProcess($00100000, False, StrToIntDef(ExpandConstant('{param:RIFLAYPID|0}'), 0));
  if ProcessHandle = 0 then Exit;
  if WaitForSingleObject(ProcessHandle, 30000) <> 0 then
    Result := CustomMessage('RiflayCloseForUpdate');
  CloseHandle(ProcessHandle);
end;

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
