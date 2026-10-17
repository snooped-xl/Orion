; A portable launcher, not a system installer. Flutter's complete runtime is
; embedded in this one EXE and cached per content hash for later launches.
Unicode true
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"
Name "Orion"
OutFile "${OUTPUT_FILE}"
RequestExecutionLevel user
SilentInstall silent
AutoCloseWindow true
SetCompressor /SOLID lzma
SetCompressorDictSize 64
CRCCheck force
Icon "../windows/runner/resources/app_icon.ico"
VIProductVersion "1.0.0.1"
VIAddVersionKey /LANG=1033 "ProductName" "Orion"
VIAddVersionKey /LANG=1033 "FileDescription" "Orion portable workspace"
VIAddVersionKey /LANG=1033 "FileVersion" "1.0.0"
VIAddVersionKey /LANG=1033 "LegalCopyright" "Orion contributors"
Var Arguments
Var Lock
Var Result

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_ICONSTOP "This Orion build requires 64-bit Windows."
    SetErrorLevel 1
    Quit
  ${EndIf}
  SetShellVarContext current
  StrCpy $INSTDIR "$LOCALAPPDATA\Orion\Runtime\${BUNDLE_ID}"
  ${GetParameters} $Arguments
  System::Call 'kernel32::CreateMutexW(p 0, i 0, w "Local\OrionPortable-${BUNDLE_ID}") p .r0'
  StrCpy $Lock $0
  System::Call 'kernel32::WaitForSingleObject(p r0, i 120000) i .r1'
  ${If} $1 != 0
  ${AndIf} $1 != 128
    MessageBox MB_ICONSTOP "Another Orion launch is preparing its runtime. Please try again."
    SetErrorLevel 1
    Quit
  ${EndIf}
FunctionEnd

Section
  IfFileExists "$INSTDIR\.complete" ready
  SetOutPath "$INSTDIR"
  SetOverwrite on
  ClearErrors
  File /r "${BUNDLE_DIR}\*"
  ${If} ${Errors}
    MessageBox MB_ICONSTOP "Orion could not extract its runtime. Check free space and permissions in LocalAppData."
    SetErrorLevel 1
    Quit
  ${EndIf}
  ; Fixed Version WebView2 120+ needs these read/execute ACLs on Windows 10.
  ; The permission is scoped to the bundled browser, never the user workspace.
  nsExec::ExecToStack '"$SYSDIR\icacls.exe" "$INSTDIR\data\webview2" /grant "*S-1-15-2-2:(OI)(CI)(RX)" "*S-1-15-2-1:(OI)(CI)(RX)" /Q'
  Pop $0
  Pop $1
  ${If} $0 != 0
    MessageBox MB_ICONSTOP "Orion could not prepare WebView2's AppContainer permissions. Check write access to its runtime cache."
    SetErrorLevel 1
    Quit
  ${EndIf}
  FileOpen $0 "$INSTDIR\.complete" w
  FileWrite $0 "${BUNDLE_ID}"
  FileClose $0
  ready:
  System::Call 'kernel32::ReleaseMutex(p $Lock)'
  System::Call 'kernel32::CloseHandle(p $Lock)'
  SetOutPath "$INSTDIR"
  ClearErrors
  ExecWait '"$INSTDIR\orion.exe" $Arguments' $Result
  ${If} ${Errors}
    MessageBox MB_ICONSTOP "Orion could not start. The portable runtime may be blocked by Windows security or missing files."
    SetErrorLevel 1
  ${Else}
    SetErrorLevel $Result
  ${EndIf}
SectionEnd
