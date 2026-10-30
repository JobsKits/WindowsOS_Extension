# Build.ps1 | JobsFileVolumes
# Created by Jobs on 2026年10月28日，星期三.
# 仅编译本包原生菜单 DLL；不注册、不联网、不安装编译器。
[CmdletBinding()]
param([string]$SourceRoot = (Split-Path -Parent $PSScriptRoot), [Parameter(Mandatory = $true)][string]$OutputRoot)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '原生菜单编译只支持 Windows。' }
$architecture = $env:PROCESSOR_ARCHITEW6432
if ([string]::IsNullOrWhiteSpace($architecture)) { $architecture = $env:PROCESSOR_ARCHITECTURE }
$target = switch ($architecture.ToUpperInvariant()) { 'AMD64' { 'x64' } 'ARM64' { 'arm64' } 'X86' { 'x86' } default { throw '无法识别 Explorer 的原生架构。' } }
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere -PathType Leaf)) {
    throw '缺少原生菜单编译工具。请安装 Visual Studio / Build Tools 的“使用 C++ 的桌面开发”（MSVC 与 Windows SDK），再安装本包：https://visualstudio.microsoft.com/visual-cpp-build-tools/'
}
$component = 'Microsoft.VisualStudio.Component.VC.Tools.x86.x64'
if ($target -eq 'arm64') { $component = 'Microsoft.VisualStudio.Component.VC.Tools.ARM64' }
$installation = @(& $vswhere -latest -products '*' -requires $component -property installationPath)
if ($LASTEXITCODE -ne 0 -or $installation.Count -ne 1) { throw ('未找到支持 ' + $target + ' 的 MSVC。请在 Visual Studio Installer 中补齐 C++ 桌面工作负载及对应架构工具。') }
$vcvars = Join-Path $installation[0] 'VC/Auxiliary/Build/vcvarsall.bat'
if (-not (Test-Path -LiteralPath $vcvars -PathType Leaf) -or $vcvars -match '["%\r\n]') { throw 'MSVC 环境入口缺失或路径不受支持。' }
$hostTarget = $target
if ($target -eq 'arm64') { $hostTarget = 'amd64_arm64' }
$environmentStart = New-Object Diagnostics.ProcessStartInfo
$environmentStart.FileName = Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
$environmentStart.Arguments = '/d /v:off /s /c ""' + $vcvars + '" ' + $hostTarget + ' >nul && set"'
$environmentStart.UseShellExecute = $false
$environmentStart.CreateNoWindow = $true
$environmentStart.RedirectStandardOutput = $true
$environmentStart.RedirectStandardError = $true
$environmentProcess = [Diagnostics.Process]::Start($environmentStart)
try {
    $stdout = $environmentProcess.StandardOutput.ReadToEndAsync()
    $stderr = $environmentProcess.StandardError.ReadToEndAsync()
    if (-not $environmentProcess.WaitForExit(60000)) { $environmentProcess.Kill(); throw 'MSVC 环境准备超时。' }
    if ($environmentProcess.ExitCode -ne 0) { throw ('MSVC 环境准备失败：' + $stderr.GetAwaiter().GetResult()) }
    $buildEnvironment = @{}
    foreach ($line in ($stdout.GetAwaiter().GetResult() -split '\r?\n')) {
        if ($line -match '^([^=]+)=(.*)$') { $buildEnvironment[$Matches[1]] = $Matches[2] }
    }
} finally { $environmentProcess.Dispose() }
$compiler = $null
foreach ($directory in ($buildEnvironment['PATH'] -split ';')) {
    $candidate = Join-Path $directory 'cl.exe'
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $compiler = $candidate; break }
}
if (-not $compiler -or -not $buildEnvironment['INCLUDE'] -or -not $buildEnvironment['LIB']) { throw 'MSVC / Windows SDK 环境不完整，停止注册菜单。' }
[void][IO.Directory]::CreateDirectory($OutputRoot)
$output = [IO.Path]::GetFullPath($OutputRoot)
$scripts = Join-Path ([IO.Path]::GetFullPath($SourceRoot)) 'Scripts'
$response = Join-Path $output 'native.rsp'
$arguments = @('/nologo', '/LD', '/MT', '/EHsc', '/std:c++14', '/O2', '/W4', '/utf-8', '/DUNICODE', '/D_UNICODE',
    ('/I"' + $scripts + '"'), ('/Fo"' + (Join-Path $output 'ContextMenu.obj') + '"'),
    ('"' + (Join-Path $scripts 'ContextMenu.cpp') + '"'), '/link',
    ('/DEF:"' + (Join-Path $scripts 'ContextMenu.def') + '"'),
    ('/OUT:"' + (Join-Path $output 'JobsFileVolumesContextMenu.dll') + '"'),
    'shell32.lib', 'shlwapi.lib', 'ole32.lib', 'uuid.lib', 'user32.lib')
[IO.File]::WriteAllLines($response, $arguments, (New-Object Text.UTF8Encoding($true)))
$buildStart = New-Object Diagnostics.ProcessStartInfo
$buildStart.FileName = $compiler
$buildStart.Arguments = '@"' + $response + '"'
$buildStart.WorkingDirectory = $output
$buildStart.UseShellExecute = $false
foreach ($name in $buildEnvironment.Keys) { $buildStart.EnvironmentVariables[$name] = $buildEnvironment[$name] }
if ($env:JOBS_MANAGEMENT_GUI -eq '1') {
    $buildExitCode = Invoke-JobsManagementNativeProcess -StartInfo $buildStart -TimeoutMilliseconds 120000
    if ($buildExitCode -ne 0) { throw '原生菜单编译失败；尚未写入注册表。' }
} else {
    $build = [Diagnostics.Process]::Start($buildStart)
    try {
        if (-not $build.WaitForExit(120000)) { $build.Kill(); throw '原生菜单编译超时。' }
        if ($build.ExitCode -ne 0) { throw '原生菜单编译失败；尚未写入注册表。' }
    } finally { $build.Dispose() }
}
if (-not (Test-Path -LiteralPath (Join-Path $output 'JobsFileVolumesContextMenu.dll') -PathType Leaf)) { throw '文件分卷菜单构建产物缺失。' }
Write-Host ('原生 文件分卷菜单已编译：' + $output)
