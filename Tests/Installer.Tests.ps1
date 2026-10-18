# Installer.Tests.ps1 | Windows@Extension
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
        & $packageInstaller { param($Manifest, $Release, $PowerShell, $Enabled) Get-JobsPackageRegistryPlan -Manifest $Manifest -ReleasePath $Release -PowerShellPath $PowerShell -Enabled $Enabled } $feature $ReleasePath $PowerShellPath ($feature.Id -in $Features)
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
Assert-JobsTest ($features.Count -eq 11) '提供十一个独立功能'
Assert-JobsTest (@($features.Id | Select-Object -Unique).Count -eq 11) '功能标识唯一'
$release = Join-Path ([IO.Path]::GetTempPath()) 'Jobs 中文 & 100% release'
$powerShell = Join-Path $PSHOME 'powershell.exe'
$all = @(Get-JobsRegistryPlan -Features @($features.Id) -ReleasePath $release -PowerShellPath $powerShell)
Assert-JobsTest ($all.Count -gt 0) '注册计划非空'
Assert-JobsTest (@($all.Key | Select-Object -Unique).Count -eq $all.Count) '每个菜单键唯一'
Assert-JobsTest (@($all | Where-Object { -not $_.Enabled }).Count -eq 0) '全选计划全部启用'

foreach ($feature in $features) {
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
