# Action.psm1 | JobsHiddenFilesToggler
# Created by Jobs on 2026年10月26日，星期一.
# 读取与写入仅作用于当前用户 Hidden；导入及安装均不切换偏好。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking
$script:preferencePath = 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'

function Get-JobsHiddenFilesState {
    param($RegistryRoot = [Microsoft.Win32.Registry]::CurrentUser)
    $key = $RegistryRoot.OpenSubKey($script:preferencePath, $false)
    if ($null -eq $key) { return 2 }
    try {
        $value = $key.GetValue('Hidden', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        if ($null -eq $value) { return 2 }
        if ($key.GetValueKind('Hidden') -ne [Microsoft.Win32.RegistryValueKind]::DWord -or
            ($value -isnot [int] -and $value -isnot [uint32]) -or $value -notin @(1, 2)) {
            throw '无法识别当前用户隐藏文件显示状态；保留原设置。'
        }
        return [int]$value
    } finally { $key.Dispose() }
}

function Invoke-JobsHiddenFilesToggle {
    param($RegistryRoot = [Microsoft.Win32.Registry]::CurrentUser,
        [ValidateSet('Show', 'Hide', 'Toggle')][string]$Visibility = 'Toggle')
    $before = Get-JobsHiddenFilesState -RegistryRoot $RegistryRoot
    $next = 1
    if ($Visibility -ceq 'Hide' -or ($Visibility -ceq 'Toggle' -and $before -eq 1)) { $next = 2 }
    if ($before -eq $next) { return $next }
    $key = $RegistryRoot.CreateSubKey($script:preferencePath)
    try {
        # 只改普通隐藏文件，ShowSuperHidden 与其它 Explorer 设置保持原值。
        $key.SetValue('Hidden', $next, [Microsoft.Win32.RegistryValueKind]::DWord)
        $key.Flush()
    } finally { $key.Dispose() }
    if ((Get-JobsHiddenFilesState -RegistryRoot $RegistryRoot) -ne $next) {
        throw '隐藏文件设置回读不一致；请重新打开菜单检查当前状态。'
    }
    return $next
}

function Send-JobsHiddenFilesRefresh {
    if (-not ('Jobs.ExplorerRefresher' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'ExplorerRefresher.cs') }
    [Jobs.ExplorerRefresher]::Notify()
    $shell = $null
    $windows = $null
    try {
        $shell = New-Object -ComObject Shell.Application
        $windows = $shell.Windows()
        foreach ($window in $windows) {
            try {
                if ([IO.Path]::GetFileName([string]$window.FullName) -ieq 'explorer.exe') { $window.Refresh() }
            } catch { Write-JobsLog '一个 Explorer 窗口未响应刷新；显示偏好已保存。' }
            finally { if ($null -ne $window) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($window) } }
        }
    } catch { Write-JobsLog '隐藏文件显示偏好已保存；部分 Explorer 窗口需要手动刷新。' }
    finally {
        if ($null -ne $windows) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($windows) }
        if ($null -ne $shell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
    }
}

function Invoke-JobsFeature {
    param([Parameter(Mandatory = $true)][string]$Target,
        [ValidateSet('Show', 'Hide', 'Toggle')][string]$Visibility = 'Toggle')
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '隐藏文件切换只支持 Windows。' }
    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    $path = Resolve-JobsTarget $Target
    if ([string]::IsNullOrWhiteSpace($desktop) -or -not [string]::Equals(
        [IO.Path]::GetFullPath($path).TrimEnd('\'), [IO.Path]::GetFullPath($desktop).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
        throw '此入口只支持系统桌面空白处。'
    }
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $mutex = New-Object Threading.Mutex($false, ('Local\JobsHiddenFilesToggle-' + $sid))
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(2000) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw '另一个隐藏文件切换正在处理，请稍后重试。' }
        $state = Invoke-JobsHiddenFilesToggle -Visibility $Visibility
        Send-JobsHiddenFilesRefresh
        Write-JobsLog ('当前用户普通隐藏文件显示：' + ($state -eq 1))
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
Export-ModuleMember -Function Invoke-JobsFeature
