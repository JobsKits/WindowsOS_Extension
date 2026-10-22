# Installer.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026-10-18.
# Windows 注册测试只写入本次 GUID 隔离目录，绝不使用真实菜单键。
[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:Assertions = 0
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'Scripts'
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'JobsPathCopier/Scripts/Common.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $scripts 'Catalog.psm1') -Force -DisableNameChecking
$packageInstaller = Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'JobsPathCopier/Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
function Get-JobsRegistryPlan {
    param([string[]]$Features, [string]$ReleasePath, [string]$PowerShellPath)
    $known = @(Get-JobsFeaturePackages)
    foreach ($id in $Features) { if ($id -notin @($known.Id)) { throw 'Unknown feature' } }
    foreach ($feature in $known) {
        $ownInstaller = Import-Module (Join-Path $feature.PackagePath 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
        & $ownInstaller { param($Manifest, $Release, $PowerShell, $Enabled) Get-JobsPackageRegistryPlan -Manifest $Manifest -ReleasePath $Release -PowerShellPath $PowerShell -Enabled $Enabled } $feature $ReleasePath $PowerShellPath ($feature.Id -in $Features)
    }
}

function Assert-JobsTest {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
    $script:Assertions++
}

function Assert-JobsThrows {
    param([scriptblock]$Body, [string]$Message)
    $threw = $false
    try { & $Body } catch { $threw = $true }
    Assert-JobsTest $threw $Message
}

$features = @(Get-JobsFeaturePackages)
$parsedCatalog = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'Extensions.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$expectedCount = @($parsedCatalog).Count
Assert-JobsTest ($features.Count -eq $expectedCount) '提供登记的独立功能'
Assert-JobsTest (@($features.Id | Select-Object -Unique).Count -eq $expectedCount) '功能标识唯一'
$release = Join-Path ([IO.Path]::GetTempPath()) 'Jobs 中文 & 100% release'
$powerShell = Join-Path $PSHOME 'powershell.exe'
$all = @(Get-JobsRegistryPlan -Features @($features.Id) -ReleasePath $release -PowerShellPath $powerShell)
Assert-JobsTest ($all.Count -gt 0) '注册计划非空'
Assert-JobsTest (@($all.Key | Select-Object -Unique).Count -eq $all.Count) '每个菜单键唯一'
Assert-JobsTest (@($all | Where-Object { -not $_.Enabled }).Count -eq 0) '全选计划全部启用'

foreach ($feature in $features) {
    if ($feature.Id -eq 'git-proxy-configure') {
        $desktop = @($all | Where-Object { $_.Key.EndsWith('Jobs.WindowsExtension.git-proxy-configure') })
        Assert-JobsTest ($desktop.Count -eq 1) 'Git 配置只注册一个桌面空白入口'
        Assert-JobsTest ($desktop[0].Key -eq 'Software\Classes\DesktopBackground\shell\Jobs.WindowsExtension.git-proxy-configure') 'Git 配置不进入普通目录、磁盘和选中项'
        continue
    }
    if ($feature.Id -eq 'android-simulator-create') {
        $native = @($all | Where-Object { $_.Key.EndsWith('Jobs.WindowsExtension.android-simulator-create') -or $_.Key.EndsWith('CLSID\{9591D98B-3481-4E05-BE24-470FCDFD0E23}') })
        Assert-JobsTest ($native.Count -eq 2) 'Android 桌面 handler 与 CLSID 独立'
        Assert-JobsTest (@($native | Where-Object { $_.Key -match '\\Directory|\\Drive|\\\*|\\shell\\' }).Count -eq 0) 'Android 不注册普通目录与选中项'
        continue
    }
    if ($feature.Id -in @('flutter-run', 'flutter-package', 'flutter-doctor', 'flutter-codegen')) {
        $clsid = '{239D7884-83C5-4D66-AB0C-14A2667DCD61}'
        if ($feature.Id -eq 'flutter-package') { $clsid = '{64A7C5BE-E031-4E89-A2D7-75C3F62B1AC9}' }
        if ($feature.Id -eq 'flutter-doctor') { $clsid = '{A41E939F-64E7-49DD-85FA-81F9B8CFD5E2}' }
        if ($feature.Id -eq 'flutter-codegen') { $clsid = '{DD71AE09-8A16-4B08-9868-5A40A9F39F63}' }
        $native = @($all | Where-Object { $_.Key.EndsWith('Jobs.WindowsExtension.' + $feature.Id) -or $_.Key.EndsWith('CLSID\' + $clsid) })
        Assert-JobsTest ($native.Count -eq 4) 'Flutter 运行包只注册三个动态处理器和独立 CLSID'
        Assert-JobsTest (@($native | Where-Object { $_.Key -match '\\shell\\' }).Count -eq 0) 'Flutter 运行包不残留始终可见的静态菜单'
        continue
    }
    $items = @($all | Where-Object { $_.Key.EndsWith('\Jobs.WindowsExtension.' + $feature.Id) })
    $expectedCount = 4
    if ($feature.DirectoryOnly) { $expectedCount = 3 }
    Assert-JobsTest ($items.Count -eq $expectedCount) ('上下文数量：' + $feature.Id)
    foreach ($class in @('Directory', 'Directory\Background', 'Drive')) {
        $key = 'Software\Classes\' + $class + '\shell\Jobs.WindowsExtension.' + $feature.Id
        Assert-JobsTest (@($items | Where-Object { $_.Key -eq $key }).Count -eq 1) ('目录/背景/磁盘：' + $class + '/' + $feature.Id)
    }
    $fileCount = @($items | Where-Object { $_.Key.StartsWith('Software\Classes\*\') }).Count
    Assert-JobsTest ($fileCount -eq [int](-not $feature.DirectoryOnly)) ('文件上下文遵守适用条件：' + $feature.Id)
    foreach ($item in $items) {
        $placeholder = '%1'
        if ($item.Key.Contains('\Directory\Background\')) { $placeholder = '%V' }
        Assert-JobsTest ($item.Command.EndsWith('-Target "' + $placeholder + '|JobsPathEnd"')) ('占位符和盘符反斜杠保护：' + $item.Key)
        Assert-JobsTest ($item.Command.Contains('-File ' + (Quote-JobsArgument (Join-Path $release 'Scripts/Invoke.ps1')))) '运行文件使用独立参数'
        Assert-JobsTest (-not $item.Command.Contains(' -Command ')) '注册命令不解释目标路径为脚本'
    }
}

$one = @(Get-JobsRegistryPlan -Features @($features[0].Id) -ReleasePath $release -PowerShellPath $powerShell)
Assert-JobsTest (@($one | Where-Object { $_.Enabled }).Count -eq @($all | Where-Object { $_.Key.EndsWith('\Jobs.WindowsExtension.' + $features[0].Id) }).Count) '单项选择只启用该项上下文'
$none = @(Get-JobsRegistryPlan -Features @() -ReleasePath $release -PowerShellPath $powerShell)
Assert-JobsTest (@($none | Where-Object { $_.Enabled }).Count -eq 0) '全不选保留完整删除计划'
Assert-JobsThrows { Get-JobsRegistryPlan -Features @('unknown-feature') -ReleasePath $release -PowerShellPath $powerShell } '未知标识立即拒绝'

if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
    if (-not ('Jobs.InstallerTestNative' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Jobs {
    public static class InstallerTestNative {
        [DllImport("shell32.dll", SetLastError = true)]
        private static extern IntPtr CommandLineToArgvW([MarshalAs(UnmanagedType.LPWStr)] string commandLine, out int count);
        [DllImport("kernel32.dll")]
        private static extern IntPtr LocalFree(IntPtr memory);
        public static string[] Arguments(string commandLine) {
            int count;
            IntPtr values = CommandLineToArgvW(commandLine, out count);
            if (values == IntPtr.Zero) throw new InvalidOperationException("CommandLineToArgvW failed");
            try {
                string[] result = new string[count];
                for (int i = 0; i < count; i++) result[i] = Marshal.PtrToStringUni(Marshal.ReadIntPtr(values, i * IntPtr.Size));
                return result;
            } finally { LocalFree(values); }
        }
    }
}
'@
    }
    $rootPath = [IO.Path]::GetPathRoot([Environment]::SystemDirectory)
    foreach ($target in @($rootPath, 'C:\研发 & 团队\100% done', 'C:\引号''与`字符\file.txt')) {
        foreach ($item in @($all[0], @($all | Where-Object { $_.Key.Contains('\Directory\Background\') })[0])) {
            $placeholder = '%1'
            if ($item.Key.Contains('\Directory\Background\')) { $placeholder = '%V' }
            $command = $item.Command.Replace($placeholder, $target)
            $argv = [Jobs.InstallerTestNative]::Arguments($command)
            Assert-JobsTest ($argv[0] -eq $powerShell) '原生 argv 保留 PowerShell 路径'
            $fileIndex = [Array]::IndexOf($argv, '-File')
            $targetIndex = [Array]::IndexOf($argv, '-Target')
            Assert-JobsTest ($fileIndex -gt 0 -and $argv[$fileIndex + 1] -eq (Join-Path $release 'Scripts/Invoke.ps1')) '原生 argv 保留中文/空格/&/% 的安装路径'
            Assert-JobsTest ($targetIndex -gt 0 -and $argv[$targetIndex + 1] -eq ($target + '|JobsPathEnd')) '原生 argv 保留中文/&/%/根盘符目标'
            Assert-JobsTest ($argv.Count -eq $targetIndex + 2) '目标字符没有增加命令参数'
        }
    }

} else {
    Write-Host 'SKIP: 原生 argv 测试需要 Windows；注册事务另见 PackageInstaller.Tests.ps1。'
}
Write-Host ('PASS: Installer.Tests.ps1 (' + $script:Assertions + ' assertions)')
