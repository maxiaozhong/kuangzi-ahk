#Requires -Version 5.1
<#
.SYNOPSIS
  框子宿主构建脚本：把各入口 .ahk 按序编译成 exe。

.DESCRIPTION
  前置条件（需自行安装，均不入版本管理）：
      1. AutoHotkey v2（https://www.autohotkey.com/）——脚本运行与编译基底（base）
      2. Ahk2Exe 编译器——自动探测以下位置，找不到时用 -Ahk2Exe 指定：
         <AHK 安装目录>\Compiler\Ahk2Exe.exe、tools\Ahk2Exe\Ahk2Exe.exe（仓库内，自备）

  编译顺序即依赖顺序：
      kuangzi.ahk           -> kuangzi.exe            GUI 宿主
      kuangzi-cli.ahk       -> kuangzi-cli.exe        CLI
      kuangzi-uninstall.ahk -> kuangzi-uninstall.exe  卸载器
      plugins-src\kuangzi-jisuan\main.ahk
                            -> build\plugins\kuangzi-jisuan.exe
                               模板插件，独立产物（不被安装器内嵌）：Release 附件里的
                               插件 zip 靠它开箱即用——用户不必装 AHK v2
      安装器                -> 必须排最后：它用 FileInstall 内嵌上面三个宿主 exe 的成品，
                              先编它就会嵌到旧版本（这正是要有本脚本的原因，人工容易错序）

  编译前若产品根的上一层 tools\ 里有 set-version.ps1 就先跑它 -Check：源码没注入版本号就
  不该编——编译指令只认字面量，漏注入的产物属性里没有版本号，且不会报错（静默漂移）。
  该脚本不是本脚本的依赖，找不到就跳过。

  CLI 的 Console base：
      AHK v2 官方只发 GUI 子系统的 base（AutoHotkey64.exe），其产物在 cmd/PowerShell 里
      直接敲没有回显（管道调用正常）。本脚本就地派生一个 Console base（把 PE 头的
      Subsystem 从 GUI 改成 Console，解释器本体不动），缺失即自动重建，只给 CLI 用；
      宿主 / 卸载器 / 安装器保持 GUI base——它们是窗口程序，用 Console base 会弹黑框。

.EXAMPLE
  .\tools\build.ps1                                  # 产物到 build\
  .\tools\build.ps1 -OutDir D:\tmp\kz                # 指定输出目录
  .\tools\build.ps1 -Base 'D:\ahk\AutoHotkey64.exe'  # 指定 base
  .\tools\build.ps1 -Ahk2Exe 'D:\Ahk2Exe.exe'        # 指定编译器

.NOTES
  注意：本文件必须保存为「UTF-8 带 BOM」——PowerShell 5.1 读无 BOM 的 .ps1 会按 GBK 解析，
        脚本内的中文将失效。
#>
[CmdletBinding()]
param(
    [string]$OutDir = '',
    [string]$Base = '',
    [string]$Ahk2Exe = ''
)

$ErrorActionPreference = 'Stop'
# 本脚本住在产品根的 tools\ 下，产品根 = 脚本所在目录的上一级
$prodRoot = Split-Path -Parent $PSScriptRoot
$mfPath = Join-Path $prodRoot 'manifest.json'
if (-not (Test-Path $mfPath)) { throw "找不到产品根：$prodRoot 下没有 manifest.json" }

# ===== 定位编译器 =====
if ($Ahk2Exe -eq '' -or -not (Test-Path $Ahk2Exe)) {
    $cands = @(
        (Join-Path $env:ProgramFiles 'AutoHotkey\Compiler\Ahk2Exe.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'AutoHotkey\Compiler\Ahk2Exe.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\Compiler\Ahk2Exe.exe'),
        (Join-Path $prodRoot 'tools\Ahk2Exe\Ahk2Exe.exe')
    )
    foreach ($c in $cands) {
        if ($c -and (Test-Path $c)) { $Ahk2Exe = $c; break }
    }
}
if ($Ahk2Exe -eq '' -or -not (Test-Path $Ahk2Exe)) {
    throw "找不到 Ahk2Exe 编译器。请安装 AutoHotkey v2（自带 Compiler），或用 -Ahk2Exe <路径> 指定。"
}

# ===== 定位 base =====
if ($Base -eq '') {
    $cands = @(
        (Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'AutoHotkey\v2\AutoHotkey64.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\AutoHotkey\v2\AutoHotkey64.exe')
    )
    foreach ($c in $cands) {
        if ($c -and (Test-Path $c)) { $Base = $c; break }
    }
}
if ($Base -eq '' -or -not (Test-Path $Base)) {
    throw "找不到 AutoHotkey v2 的 base。请用 -Base <路径> 指定（一般形如 C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe）。"
}

# ===== 派生 Console base（只给 CLI 用）=====
# 读 PE OptionalHeader.Subsystem：2=GUI / 3=Console；读不出有效 PE 返回 -1
function Get-PESubsystem([string]$Path) {
    if (-not (Test-Path $Path)) { return -1 }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 0x40) { return -1 }
    $peOff = [BitConverter]::ToInt32($bytes, 0x3C)
    if ($peOff -le 0 -or ($peOff + 24 + 0x46) -gt $bytes.Length) { return -1 }
    # 'PE\0\0' 签名（按字节比，避开反引号转义歧义）
    if ($bytes[$peOff] -ne 0x50 -or $bytes[$peOff + 1] -ne 0x45 -or
        $bytes[$peOff + 2] -ne 0x00 -or $bytes[$peOff + 3] -ne 0x00) { return -1 }
    return [BitConverter]::ToUInt16($bytes, $peOff + 24 + 0x44)
}

# Console base 是从本机 AutoHotkey64.exe 派生的（改 PE 头一个字节），放本地工具目录；
# 不入版本管理——每台机 build 时自动重建，换电脑无需同步二进制
$localToolsDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\_local'
if (-not (Test-Path $localToolsDir)) { New-Item -ItemType Directory -Path $localToolsDir -Force | Out-Null }
$consoleBase = Join-Path $localToolsDir 'AutoHotkey64-console.exe'
$consoleState = '沿用'
if ((Get-PESubsystem $consoleBase) -ne 3) {
    # 不存在或不是 Console 子系统（被换过/损坏）都重建：产物体质只取决于 base，不能靠信任
    if ((Get-PESubsystem $Base) -ne 2) {
        throw "GUI base 的 PE subsystem 是 $((Get-PESubsystem $Base))，不是 GUI(2)，无法派生 Console base：$Base"
    }
    $bytes = [System.IO.File]::ReadAllBytes($Base)
    $ssOff = [BitConverter]::ToInt32($bytes, 0x3C) + 24 + 0x44
    $bytes[$ssOff] = 3
    $bytes[$ssOff + 1] = 0
    [System.IO.File]::WriteAllBytes($consoleBase, $bytes)
    $consoleState = '新派生'
}

# ===== 输出目录 =====
if ($OutDir -eq '') { $OutDir = Join-Path $prodRoot 'build' }
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }

Write-Host ''
Write-Host "编译器   : $Ahk2Exe"
Write-Host "GUI base : $Base"
Write-Host "CLI base : $consoleBase（$consoleState）"
Write-Host "输出到   : $OutDir"

# ===== 编译前校验版本一致性（找得到 set-version.ps1 才做）=====
# 该脚本不在产品根内，位于产品根的上一层 tools\；找不到就跳过
$svScript = Join-Path $PSScriptRoot 'set-version.ps1'
if (-not (Test-Path $svScript)) { $svScript = Join-Path (Split-Path -Parent $prodRoot) 'tools\set-version.ps1' }
if (Test-Path $svScript) {
    Write-Host ''
    Write-Host '校验版本一致性…'
    & $svScript -Check
    if ($LASTEXITCODE -ne 0) {
        throw '版本不一致：先跑 tools\set-version.ps1 注入版本号，再构建。'
    }
}

# 版本源（setup 产物名用；与 set-version.ps1 同一真相源）
$mf = Get-Content $mfPath -Raw -Encoding UTF8 | ConvertFrom-Json
$verKuangzi = $mf.version

# ===== 编译清单（顺序 = 依赖顺序）=====
# setup 产物名带版本号（Release 附件直接用它，用户下载后离线可认版本）；
# 三个散件保持短名（安装器内嵌用，不是用户下载入口）。
$verTag = "-v$verKuangzi"
$targets = @(
    # 模板插件：随 Release 的插件 zip 分发，独立于宿主，也不被安装器内嵌
    @{ Src = 'plugins-src\kuangzi-jisuan\main.ahk'; Out = 'plugins\kuangzi-jisuan.exe'; Base = $Base },
    @{ Src = 'kuangzi.ahk';           Out = 'kuangzi.exe';           Base = $Base },
    @{ Src = 'kuangzi-cli.ahk';       Out = 'kuangzi-cli.exe';       Base = $consoleBase },
    @{ Src = 'kuangzi-uninstall.ahk'; Out = 'kuangzi-uninstall.exe'; Base = $Base }
    # 安装器**必须排最后一行**：它用 FileInstall 内嵌上面三个宿主 exe 的成品，
    # 排在前面就会把上一次编译的旧版本嵌进去。
    @{ Src = 'kuangzi-setup.ahk';     Out = "kuangzi-setup$verTag.exe"; Base = $Base }
)

$failed = New-Object System.Collections.ArrayList
foreach ($t in $targets) {
    $src = Join-Path $prodRoot $t.Src
    $out = Join-Path $OutDir  $t.Out
    $outParent = Split-Path $out -Parent
    if (-not (Test-Path $outParent)) { New-Item -ItemType Directory -Path $outParent -Force | Out-Null }

    Write-Host ''
    Write-Host "  $($t.Src)  ->  $($t.Out)"

    if (-not (Test-Path $src)) {
        Write-Host '    [!] 源文件不存在，跳过' -ForegroundColor Red
        [void]$failed.Add($t.Src)
        continue
    }

    # Ahk2Exe 是窗口程序：**必须显式等待**它编完（直接 & 调用不等）。
    # 用 .NET Process.Start：某些环境同时存在 http_proxy 与 HTTP_PROXY 时 Start-Process
    # 会因大小写不敏感字典冲突抛「已添加项」；CreateProcess 不碰那个字典。
    $argLine = '/in "{0}" /out "{1}" /base "{2}" /silent' -f $src, $out, $t.Base
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName        = $Ahk2Exe
    $psi.Arguments       = $argLine
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.WaitForExit()
    $code = $proc.ExitCode
    if ($code -ne 0 -or -not (Test-Path $out)) {
        Write-Host "    [!] 编译失败（exit=$code）" -ForegroundColor Red
        [void]$failed.Add($t.Src)
        continue
    }

    $fi = Get-Item $out
    $subLabel = switch (Get-PESubsystem $out) { 2 { 'GUI(2)' } 3 { 'Console(3)' } default { "?( $($_) )" } }
    Write-Host ("    [ok] {0:N0} 字节  v{1}  [{2}]" -f $fi.Length, $fi.VersionInfo.FileVersion, $subLabel)
}

Write-Host ''
if ($failed.Count -gt 0) {
    Write-Host "构建失败：$($failed -join '、')" -ForegroundColor Red
    exit 1
}
Write-Host "构建完成，产物在 $OutDir" -ForegroundColor Green
exit 0
