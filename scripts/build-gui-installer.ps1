param(
  [string]$ReleaseDir = (Resolve-Path (Join-Path $PSScriptRoot '..\release\gui-windows')).Path,
  [string]$OutFile = (Join-Path $PSScriptRoot '..\release\WeLearn-Setup-1.2.0.exe'),
  [string]$Version = '1.2.0'
)

$ErrorActionPreference = 'Stop'

# 1. 找 NSIS。项目约定把便携版放在 D:\dev\nsis\nsis-3.11；没有就下载一份。
$makensis = (Get-Command makensis -ErrorAction SilentlyContinue).Source
if (-not $makensis) {
  $candidate = 'D:\dev\nsis\nsis-3.11\makensis.exe'
  if (-not (Test-Path $candidate)) {
    $zip = Join-Path $env:TEMP 'nsis-3.11.zip'
    $dest = Join-Path $env:TEMP 'nsis-3.11'
    if (-not (Test-Path $zip)) {
      curl.exe -L -o $zip 'https://downloads.sourceforge.net/project/nsis/NSIS%203/3.11/nsis-3.11.zip'
    }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (-not (Test-Path $dest)) {
      [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $dest)
    }
    $candidate = Get-ChildItem $dest -Filter makensis.exe -Recurse |
      Select-Object -First 1 -ExpandProperty FullName
  }
  $makensis = $candidate
}
if (-not (Test-Path $makensis)) {
  throw "未找到 makensis.exe，请先安装 NSIS 或把便携版放到 D:\dev\nsis"
}

# 2. 在英文路径暂存安装内容；排除运行时生成的 WebView2 缓存。
$root = if (Test-Path 'D:\dev') {
  'D:\dev\welearn-installer'
} else {
  Join-Path $env:TEMP 'welearn-installer'
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$payload = Join-Path $root "payload-$stamp"
$output = Join-Path $root "WeLearn-Setup-$Version.exe"
New-Item -ItemType Directory -Force -Path $payload | Out-Null

Get-ChildItem $ReleaseDir -Force |
  Where-Object { $_.Name -notin @('welearn_app.exe.WebView2', 'uninstall.exe') } |
  ForEach-Object {
    Copy-Item $_.FullName (Join-Path $payload $_.Name) -Recurse -Force
  }
Copy-Item (Join-Path $PSScriptRoot '..\app\windows\runner\resources\app_icon.ico') `
  (Join-Path $payload 'app_icon.ico') -Force

# 3. 生成 NSIS 脚本。安装到当前用户目录，不弹 UAC；卸载不删用户数据。
$nsi = Join-Path $root "installer-$stamp.nsi"
$content = @"
Unicode true
!include "MUI2.nsh"

!define APP_NAME "WeLearn 助手"
!define APP_VERSION "$Version"
!define APP_ID "WeLearnAssistant"
!define PAYLOAD "$payload"
!define OUTFILE "$output"

Name "`${APP_NAME}"
OutFile "`${OUTFILE}"
InstallDir "`$LOCALAPPDATA\Programs\`${APP_NAME}"
InstallDirRegKey HKCU "Software\`${APP_ID}" "InstallDir"
RequestExecutionLevel user
SetCompressor /SOLID lzma
SetCompressorDictSize 64

VIProductVersion "`${APP_VERSION}.0"
VIAddVersionKey "ProductName" "`${APP_NAME}"
VIAddVersionKey "CompanyName" "Auto-WeLearn"
VIAddVersionKey "FileDescription" "`${APP_NAME} 安装程序"
VIAddVersionKey "FileVersion" "`${APP_VERSION}"
VIAddVersionKey "ProductVersion" "`${APP_VERSION}"

!define MUI_ABORTWARNING
!define MUI_ICON "`${PAYLOAD}\app_icon.ico"
!define MUI_UNICON "`${PAYLOAD}\app_icon.ico"
!define MUI_FINISHPAGE_RUN "`$INSTDIR\welearn_app.exe"
!define MUI_FINISHPAGE_RUN_TEXT "运行 WeLearn 助手"

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "English"

Section "Install"
  ; 旧版在托盘后台运行时仍会占用 welearn_app.exe，直接覆盖会失败。
  ; 先等它自行退出（应用内更新会主动退出，最多等约 10 秒），
  ; 仍未退出（手动双击安装包的情况）就强制结束，再开始复制文件。
  StrCpy `$R9 0
  wait_app_exit:
    ; find 命中时返回码为 0，说明旧进程还在；未命中为 1，可以开始安装。
    ; nsExec 把输出和返回码一起压栈，这里两个都看一眼，不依赖压栈顺序。
    nsExec::ExecToStack 'cmd /c tasklist /FI "IMAGENAME eq welearn_app.exe" /NH | find /I "welearn_app.exe"'
    Pop `$R8
    Pop `$R7
    StrCmp `$R8 "0" still_running
    StrCmp `$R7 "0" still_running app_gone
  still_running:
    Sleep 300
    IntOp `$R9 `$R9 + 1
    IntCmp `$R9 12 app_gone wait_app_exit wait_app_exit
  app_gone:
  nsExec::ExecToStack 'cmd /c taskkill /IM welearn_app.exe /F'
  Sleep 400

  SetOutPath "`$INSTDIR"
  File /r "`${PAYLOAD}\*.*"
  WriteUninstaller "`$INSTDIR\uninstall.exe"

  CreateShortcut "`$DESKTOP\`${APP_NAME}.lnk" "`$INSTDIR\welearn_app.exe" "" "`$INSTDIR\app_icon.ico" 0
  CreateDirectory "`$SMPROGRAMS\`${APP_NAME}"
  CreateShortcut "`$SMPROGRAMS\`${APP_NAME}\`${APP_NAME}.lnk" "`$INSTDIR\welearn_app.exe" "" "`$INSTDIR\app_icon.ico" 0
  CreateShortcut "`$SMPROGRAMS\`${APP_NAME}\卸载 `${APP_NAME}.lnk" "`$INSTDIR\uninstall.exe"

  WriteRegStr HKCU "Software\`${APP_ID}" "InstallDir" "`$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\`${APP_ID}" "DisplayName" "`${APP_NAME}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\`${APP_ID}" "DisplayVersion" "`${APP_VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\`${APP_ID}" "Publisher" "Auto-WeLearn"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\`${APP_ID}" "DisplayIcon" "`$INSTDIR\welearn_app.exe,0"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\`${APP_ID}" "InstallLocation" "`$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\`${APP_ID}" "UninstallString" '"`$INSTDIR\uninstall.exe"'
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\`${APP_ID}" "NoModify" 1
  WriteRegDWORD HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\`${APP_ID}" "NoRepair" 1
SectionEnd

Section "Uninstall"
  Delete "`$DESKTOP\`${APP_NAME}.lnk"
  Delete "`$SMPROGRAMS\`${APP_NAME}\`${APP_NAME}.lnk"
  Delete "`$SMPROGRAMS\`${APP_NAME}\卸载 `${APP_NAME}.lnk"
  RMDir "`$SMPROGRAMS\`${APP_NAME}"
  DeleteRegKey HKCU "Software\`${APP_ID}"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\`${APP_ID}"
  RMDir /r "`$INSTDIR"
SectionEnd
"@
[System.IO.File]::WriteAllText($nsi, $content, [System.Text.UTF8Encoding]::new($true))

& $makensis /V2 $nsi
if ($LASTEXITCODE -ne 0) {
  throw "NSIS 编译失败：$LASTEXITCODE"
}
Copy-Item $output $OutFile -Force
Write-Host "安装包已生成：$OutFile"
