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
Assert-JobsTest (@($all | Where-Object { -not $_.Enabled -and $_.Key -notmatch 'Jobs\.WindowsExtension\.flutter-(pub-get|version-manager|sdk-inspector|dependency-extract|run|package|doctor|codegen)$' -and $_.Key -notmatch '\\shell\\Jobs\.WindowsExtension\.open-(android-studio|vscode)$' }).Count -eq 0) '全选当前功能启用；仅固定旧 Flutter / IDE 静态菜单按迁移计划停用'

foreach ($feature in $features) {
    if ($feature.Id -eq 'flutter-tools') {
        $native = @($all | Where-Object { $_.Enabled -and ($_.Key.EndsWith('Jobs.WindowsExtension.flutter-tools') -or $_.Key.EndsWith('CLSID\{55C8C7A9-8625-4AF0-8598-DFA975064F0C}')) })
        Assert-JobsTest ($native.Count -eq 4) '统一 Flutter 只启用三个项目 handler 和 CLSID'
        Assert-JobsTest (@($native | Where-Object { $_.Key -match '\\shell\\' }).Count -eq 0) '统一 Flutter 不启用始终可见的静态菜单'
        continue
    }
    if ($feature.Id -eq 'hidden-files-toggle') {
        $clsid = '{F92F7AF9-65B6-41CB-A6D8-712F01F79126}'
        $native = @($all | Where-Object { $_.Key.EndsWith('Jobs.WindowsExtension.hidden-files-toggle') -or $_.Key.EndsWith('CLSID\' + $clsid) })
        Assert-JobsTest ($native.Count -eq 2) '隐藏文件只注册桌面 handler 和独立 CLSID'
        Assert-JobsTest (@($native | Where-Object { $_.Key -eq 'Software\Classes\DesktopBackground\shellex\ContextMenuHandlers\Jobs.WindowsExtension.hidden-files-toggle' }).Count -eq 1) '隐藏文件只适用于桌面背景'
        continue
    }
    if ($feature.Id -in @('open-android-studio', 'open-vscode')) {
        $clsid = '{9D337A22-B981-4C26-B586-9CC8CE7B3292}'
        if ($feature.Id -eq 'open-vscode') { $clsid = '{5B0C107E-53D8-4787-AE32-13D11CC5A07A}' }
        $native = @($all | Where-Object { $_.Enabled -and ($_.Key.EndsWith('Jobs.WindowsExtension.' + $feature.Id) -or $_.Key.EndsWith('CLSID\' + $clsid)) })
        Assert-JobsTest ($native.Count -eq 4) 'IDE 只启用三个目录 handler 和独立 CLSID'
        Assert-JobsTest (@($native | Where-Object { $_.Key.Contains('\shell\') }).Count -eq 0) 'IDE 不启用旧静态入口'
        $legacy = @($all | Where-Object { -not $_.Enabled -and $_.Key.EndsWith('\shell\Jobs.WindowsExtension.' + $feature.Id) })
        Assert-JobsTest ($legacy.Count -eq 4) 'IDE 精确停用四个旧静态入口'
        continue
    }
    if ($feature.Id -eq 'open-sourcetree') {
        $clsid = '{CF4D4697-749B-4C37-98EC-0952B2EF1E16}'
        $native = @($all | Where-Object { $_.Key.EndsWith('Jobs.WindowsExtension.open-sourcetree') -or $_.Key.EndsWith('CLSID\' + $clsid) })
        Assert-JobsTest ($native.Count -eq 4) 'Sourcetree只注册三个动态处理器和独立 CLSID'
        Assert-JobsTest (@($native | Where-Object { $_.Key -match '\\shell\\' }).Count -eq 0) 'Sourcetree不注册始终可见的静态菜单'
        foreach ($class in @('Directory', 'Directory\Background', 'Drive')) {
            $key='Software\Classes\' + $class + '\shellex\ContextMenuHandlers\Jobs.WindowsExtension.open-sourcetree'
            Assert-JobsTest (@($native | Where-Object { $_.Key -ceq $key -and $_.Values[''] -ceq $clsid }).Count -eq 1) ('Sourcetree精确上下文：' + $class)
        }
        $server=@($native | Where-Object { $_.Key.EndsWith('CLSID\' + $clsid) })
        Assert-JobsTest ($server.Count -eq 1 -and $server[0].InProcServer -ceq (Join-Path $release 'bin/JobsSourcetreeOpenerContextMenu.dll')) 'Sourcetree CLSID 精确归属于本包 DLL'
        continue
    }
    if ($feature.Id -eq 'git-rollback') {
        $clsid = '{E58D6868-A650-42EB-9629-E97338918229}'
        $native = @($all | Where-Object { $_.Key.EndsWith('Jobs.WindowsExtension.git-rollback') -or $_.Key.EndsWith('CLSID\' + $clsid) })
        Assert-JobsTest ($native.Count -eq 4) 'Git 回退只注册三个动态处理器和独立 CLSID'
        Assert-JobsTest (@($native | Where-Object { $_.Key -match '\\shell\\' }).Count -eq 0) 'Git 回退不注册始终可见的静态菜单'
        foreach ($class in @('Directory', 'Directory\Background', 'Drive')) {
            $key='Software\Classes\' + $class + '\shellex\ContextMenuHandlers\Jobs.WindowsExtension.git-rollback'
            Assert-JobsTest (@($native | Where-Object { $_.Key -ceq $key -and $_.Values[''] -ceq $clsid }).Count -eq 1) ('Git 回退精确上下文：' + $class)
        }
        $server=@($native | Where-Object { $_.Key.EndsWith('CLSID\' + $clsid) })
        Assert-JobsTest ($server.Count -eq 1 -and $server[0].InProcServer -ceq (Join-Path $release 'bin/JobsGitRollbackContextMenu.dll')) 'Git 回退 CLSID 精确归属于本包 DLL'
        continue
    }
    if ($feature.Id -eq 'git-proxy-configure') {
        $desktop = @($all | Where-Object { $_.Key.EndsWith('Jobs.WindowsExtension.git-proxy-configure') })
        Assert-JobsTest ($desktop.Count -eq 1) 'Git 配置只注册一个桌面空白入口'
        Assert-JobsTest ($desktop[0].Key -eq 'Software\Classes\DesktopBackground\shell\Jobs.WindowsExtension.git-proxy-configure') 'Git 配置不进入普通目录、磁盘和选中项'
        continue
    }
    if ($feature.Id -in @('android-simulator-create', 'android-simulator-repair', 'harmony-simulator-create', 'harmony-simulator-repair')) {
        $clsid = '{9591D98B-3481-4E05-BE24-470FCDFD0E23}'
        if ($feature.Id -eq 'android-simulator-repair') { $clsid = '{A6D8DCE0-B691-4CC9-A3C5-F02B8BC704E5}' }
        if ($feature.Id -eq 'harmony-simulator-repair') { $clsid = '{C91A8F93-CA7B-4F28-B705-A0AC90C5F231}' }
        if ($feature.Id -eq 'harmony-simulator-create') { $clsid = '{95E5B535-2EB8-48CA-98B5-A14D17A0A859}' }
        $native = @($all | Where-Object { $_.Key.EndsWith('Jobs.WindowsExtension.' + $feature.Id) -or $_.Key.EndsWith('CLSID\' + $clsid) })
        Assert-JobsTest ($native.Count -eq 2) ('模拟器桌面 handler 与 CLSID 独立：' + $feature.Id)
        Assert-JobsTest (@($native | Where-Object { $_.Key -eq ('Software\Classes\DesktopBackground\shellex\ContextMenuHandlers\Jobs.WindowsExtension.' + $feature.Id) }).Count -eq 1) ('只登记系统桌面背景 handler：' + $feature.Id)
        Assert-JobsTest (@($native | Where-Object { $_.Key -match '\\Directory|\\Drive|\\\*|\\shell\\' }).Count -eq 0) ('模拟器不注册普通目录与选中项：' + $feature.Id)
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
    if ($feature.Id -in @('run-authorize', 'run-authorization-revoke')) {
        $clsid = '{AE09A13F-EF17-4CE3-8BA1-F557C34280DE}'
        if ($feature.Id -eq 'run-authorization-revoke') { $clsid = '{6AC50F49-6915-4130-8474-F99DA4D074D6}' }
        $native = @($all | Where-Object { $_.Key.EndsWith('Jobs.WindowsExtension.' + $feature.Id) -or $_.Key.EndsWith('CLSID\' + $clsid) })
        Assert-JobsTest ($native.Count -eq 2) '权限包仅普通单文件原生 handler 和 CLSID'
        Assert-JobsTest (@($native | Where-Object { $_.Key -match '\\Directory|\\Drive|DesktopBackground' }).Count -eq 0) '运行权限不注册目录或背景'
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
