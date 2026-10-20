<#
Manage.ps1 | WindowsOS@Extension 独立功能包
Created by Jobs on 2026年10月18日，星期日.
安装：只复制本包运行文件并注册本功能的当前用户右键菜单。
卸载：只移除本功能菜单，保留禁用状态、运行文件、工具、备份和日志。
确认前可取消；不提权、不联网、不修改系统执行策略，也不打开总安装面板。
#>
[CmdletBinding()]
param([ValidateSet('Install', 'Uninstall')][string]$Mode = 'Install')

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Main {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '本工具仅支持 Windows。' }
    if ($PSVersionTable.PSVersion -lt [version]'5.1' -or $PSVersionTable.PSEdition -ne 'Desktop') { throw '请使用系统 Windows PowerShell 5.1 或本包 .cmd 入口。' }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw '请通过本包 .cmd 入口或 powershell.exe -STA 启动。' }
    $package = Split-Path -Parent $PSScriptRoot
    # 持有本包模块对象，避免其它同名功能包模块覆盖当前操作的作用域。
    $installer = Import-Module (Join-Path $PSScriptRoot 'PackageInstaller.psm1') -PassThru -DisableNameChecking
    $manifest = & $installer { param($Path) Get-JobsPackageManifest -PackagePath $Path } $package
    $state = & $installer { param($Path) Get-JobsPackageState -PackagePath $Path } $package
    Write-Host ('Jobs 独立右键扩展 · ' + $manifest.Label) -ForegroundColor Red
    Write-Host ('操作：' + $Mode) -ForegroundColor Cyan
    Write-Host ('来源：' + $package) -ForegroundColor Cyan
    Write-Host ('目标：' + $state.Root) -ForegroundColor Cyan
    Write-Host ('影响：仅当前用户、本功能 ' + $manifest.Id + ' 的右键菜单；修改前保存注册表与状态备份。')
    Write-Host '安装从本地复制本包；卸载保留程序、工具、备份与日志。确认窗口默认取消。'
    Add-Type -AssemblyName System.Windows.Forms
    $verb = '安装 / 更新'
    if ($Mode -eq 'Uninstall') { $verb = '卸载' }
    $message = $verb + '“' + $manifest.Label + '”右键菜单？' + [Environment]::NewLine +
        '来源：' + $package + [Environment]::NewLine + '目标：' + $state.Root + [Environment]::NewLine +
        '只处理本功能；保留程序、工具、日志和备份。'
    $answer = [System.Windows.Forms.MessageBox]::Show($message, ('Jobs · ' + $manifest.Label), 'YesNo', 'Question', 'Button2')
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $result = & $installer { param($Path, $Operation) Invoke-JobsPackageChange -PackagePath $Path -Mode $Operation } $package $Mode
    Write-Host ($verb + '完成；备份：' + $result.Backup) -ForegroundColor Green
    [void][System.Windows.Forms.MessageBox]::Show(($verb + '完成。重新右键即可。' + [Environment]::NewLine +
        'Windows 11：右键 → 显示更多选项。' + [Environment]::NewLine + '备份：' + $result.Backup), ('Jobs · ' + $manifest.Label))
}

try { Main }
catch {
    $message = $_.Exception.Message
    Write-Error $message -ErrorAction Continue
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        try {
            Add-Type -AssemblyName System.Windows.Forms
            [void][System.Windows.Forms.MessageBox]::Show($message, 'Jobs 独立右键扩展 · 操作失败')
        }
        catch { Write-Warning '无法显示错误窗口，请查看终端错误信息。' }
    }
    exit 1
}
