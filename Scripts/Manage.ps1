<#
Manage.ps1 | WindowsOS@Extension 安装 / 卸载管理入口
Created by Jobs on 2026年10月18日，星期日.
读取独立包清单，显示复选框；仅编排各包自己的安装与卸载，不承载右键业务。
每包独立事务，单包失败后继续其它所选包并显示各项结果；不联网、不提权、不改变系统执行策略。
MAINTENANCE_INDEX（菜单与安装的唯一维护入口）
- 总面板：Extensions.json 的 Id/Name -> Catalog.psm1/Get-JobsSelectableFeatures -> Installer.psm1/Show-JobsFeatureSelection。
- 单项：<Name>/Extension.json -> Scripts/PackageInstaller.psm1；静态标题来自清单，原生标题/显隐来自 ContextMenu.cpp 或共享菜单表，Action.psm1 负责后台执行。
- Flutter 多叶：JobsFlutterTools/Scripts/FeatureActions.psm1 管面板 ActionId/分组，FlutterToolsMenu.h 管原生标题；Catalog 只聚合为一个安装单元。
- 隐藏文件：JobsHiddenFilesToggler 的 HiddenFilesMenu.h 管全局状态/动态标题，Action.psm1 只写当前用户 Hidden；Show/Hide 明确传入，安装不切状态。
- Sourcetree：open-sourcetree 已从总清单移除；旧 JobsSourcetreeOpener 只保留卸载兼容，原生 COM 不再插入菜单。
- 查看文件：file-content-viewer -> JobsFileContentViewer；ContextMenu.cpp + FileViewerTarget.h 仅单个普通文件，Invoke.ps1 的可见控制台 -> Action.psm1 -> FileViewer.ps1 的阈值/编码确认与固定块只读输出。
- 分卷：file-volumes -> JobsFileVolumes；VolumeSelection.h 严格验证单文件/完整同组多选，ContextMenu.cpp 的一次性JSON选择清单 -> Invoke.ps1 -> FileVolumes.ps1；原件始终保留。
- IDE 门禁：AndroidStudio/VSCode 两包的 IDEProject.h + FlutterProject.h 管菜单，IDEProject.cs + ProjectEligibility.ps1 管后台；同字节副本须配对同步并跑 IDEProject.Tests.ps1。
- 产物/注册/状态：原生包 Build.ps1 -> 独立 release/bin DLL；PackageInstaller 仅写自己的 HKCU\Software\Classes 键；LOCALAPPDATA/Jobs/WindowsExtension/extensions/<Id>/settings.json 保存启用与 ReleasePath。
- 副本边界：只改源码包，release 的 Extension.json/脚本由 New-JobsPackageRelease 按字节哈希复制；Infrastructure 只生成通用模板，按包 InfrastructureOverrides 保留专用 Invoke/安装器，勿覆盖业务或修补已部署副本。
#>
[CmdletBinding()]
param(
    [ValidateSet('Manage', 'Install', 'Configure', 'Uninstall')][string]$Mode = 'Manage',
    [switch]$Preview
)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Catalog.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'Installer.psm1') -DisableNameChecking

function Main {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $PSVersionTable.PSEdition -ne 'Desktop' -or $PSVersionTable.PSVersion -lt [version]'5.1') {
        throw '请在 Windows 使用系统 Windows PowerShell 5.1 或根目录 .vbs 入口。'
    }
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw '请通过 .vbs 入口启动原生安装面板。' }
    Add-Type -AssemblyName System.Windows.Forms
    Write-Host 'Jobs Windows 独立扩展 · 安装 / 卸载管理面板' -ForegroundColor Red
    Write-Host ('来源：' + (Split-Path -Parent $PSScriptRoot)) -ForegroundColor Cyan
    Write-Host '范围：当前用户的 Jobs\WindowsExtension 运行目录和 HKCU\Software\Classes 菜单键。'
    Write-Host '在面板选择安装 / 更新或卸载，再勾选功能；未选功能保留。取消、关闭或空选不执行。'
    Write-Host '每包独立备份与回滚；单包失败后继续其它所选包，已完成项保留。取消或关闭窗口不执行操作。'
    if ($Preview) { Write-Host '仅预览：在面板底部显示选择，不部署、不写状态或注册表。' -ForegroundColor Yellow }
    $packages = @(Get-JobsFeaturePackages)
    $installed = @()
    foreach ($package in $packages) {
        try {
            $module = Import-Module (Join-Path $package.PackagePath 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking -ErrorAction Stop
            $state = & $module { param($Path) Get-JobsPackageState -PackagePath $Path } $package.PackagePath
            if ($state.Enabled) {
                if ($package.Id -ceq 'flutter-tools') { $installed += @($state.ActionIds | ForEach-Object { 'flutter-' + $_ }) }
                else { $installed += $package.Id }
            }
        } catch {
            $package.Description += "`r`n安装状态暂不可读；仅影响本项：" + $_.Exception.Message
        }
    }
    $features = @(Get-JobsSelectableFeatures -Packages $packages)
    $display = $features
    $selected = $installed
    if ($Mode -eq 'Uninstall') {
        $display = @($features | Where-Object { $_.Id -in $installed })
        if ($Preview) {
            $display = $features
            $selected = @($features.Id)
        } elseif ($display.Count -eq 0) {
            [void][System.Windows.Forms.MessageBox]::Show('没有已安装的扩展。', 'Jobs Windows 独立扩展')
            return
        }
    } elseif ($Mode -eq 'Install') { $selected = @($features.Id) }
    if ($Mode -eq 'Manage') { $selected = @() }
    $buildPlan = {
        param($Choice)
        Get-JobsPackageOperationPlan -Packages $packages -Selected @($Choice.Features) -Installed $installed -Mode $Choice.Mode
    }.GetNewClosure()
    $choice = Show-JobsFeatureSelection -Packages $display -Selected $selected -Installed $installed -Mode $Mode -Preview:$Preview -BuildPlan $buildPlan -WorkerPath (Join-Path $PSScriptRoot 'ManagementWorker.ps1')
    if ($Preview -and $null -ne $choice) { $choice | ConvertTo-Json -Depth 3 }

}

try { Main } catch {
    $message = $_.Exception.Message
    Write-Error $message -ErrorAction Continue
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        Add-Type -AssemblyName System.Windows.Forms
        [void][System.Windows.Forms.MessageBox]::Show($message, 'Jobs Windows 独立扩展 · 停止')
    }
    exit 1
}
