<#
ManagementWorker.ps1 | Jobs 扩展管理后台事务
Created by Jobs on 2026年10月28日，星期三.
只接收面板形成的逐包计划；逐项发事件并输出完整命令日志，不弹出控制台。
#>
[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$RequestPath)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding

function Write-JobsManagementEvent {
    param([string]$State, [object[]]$FeatureIds, [string]$Message)
    $event = [ordered]@{ State = $State; FeatureIds = @($FeatureIds); Message = $Message }
    [Console]::Out.WriteLine()
    [Console]::Out.WriteLine('@@JOBS-MANAGER@@' + (ConvertTo-Json -InputObject $event -Compress -Depth 4))
    [Console]::Out.Flush()
}

Import-Module (Join-Path $PSScriptRoot 'SelectionPanel.psm1') -DisableNameChecking -Global

function Write-JobsManagementResult {
    param($Value)
    if ($null -ne $Value -and $null -ne $Value.PSObject.Properties['Backup']) { Write-Host ('备份：' + $Value.Backup) }
    elseif ($null -ne $Value) { [Console]::Out.WriteLine([string]$Value); [Console]::Out.Flush() }
}

function Main {
    $request = Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $operations = @($request.Plan)
    if ($operations.Count -eq 0) { throw '管理计划为空。' }
    $route = 'installed'
    if ($null -ne $request.PSObject.Properties['DeploymentMode']) { $route = [string]$request.DeploymentMode }
    if ($route -notin @('installed', 'build')) { throw '部署路线无效。' }
    $autoCleanup = $null -ne $request.PSObject.Properties['AutoCleanup'] -and [bool]$request.AutoCleanup
    $failedCount = 0
    for ($index = 0; $index -lt $operations.Count; $index++) {
        $operation = $operations[$index]
        if ($null -ne $request.PSObject.Properties['StopRequestPath'] -and -not [string]::IsNullOrWhiteSpace([string]$request.StopRequestPath) -and (Test-Path -LiteralPath $request.StopRequestPath -PathType Leaf)) {
            foreach ($pending in @($operations[$index..($operations.Count - 1)])) { Write-JobsManagementEvent -State Skipped -FeatureIds @($pending.FeatureIds) -Message ('已停止，未执行：' + $pending.Label) }
            Write-JobsManagementEvent -State Stopped -FeatureIds @() -Message '已停止安装：当前包已结束，后续包未执行。'
            if ($failedCount -gt 0) { exit 1 }
            return
        }
        Write-JobsManagementEvent -State Running -FeatureIds @($operation.FeatureIds) -Message ($operation.DisplayMode + '：' + $operation.Label)
        $cleanupWarning = $null
        try {
            if ($operation.Mode -notin @('Install', 'Uninstall', 'Cleanup')) { throw '所选包的操作模式无效。' }
            $manifestPath = Join-Path $operation.PackagePath 'Extension.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($manifest.Id -cne $operation.Id -or ($null -ne $operation.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$operation.Name) -and $manifest.Name -cne $operation.Name)) { throw ('功能清单与所选包身份不一致：' + $operation.PackagePath) }
            $modulePath = Join-Path $operation.PackagePath 'Scripts/PackageInstaller.psm1'
            if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw ('所选包缺少安装器：' + $modulePath) }
            $module = Import-Module $modulePath -PassThru -Force -DisableNameChecking
            Write-Host ('来源：' + $operation.PackagePath)
            if ($operation.Mode -eq 'Cleanup') {
                if ($route -ne 'installed') { throw '临时构建路线禁止清理运行产物。' }
                & $module { param($Path) Clear-JobsPackageBuildArtifacts -PackagePath $Path } $operation.PackagePath | ForEach-Object { Write-JobsManagementResult $_ }
            } else {
                $parameters = @{ PackagePath = $operation.PackagePath; Mode = $operation.Mode }
                # 无路线字段的旧隔离计划继续兼容；GUI 新计划总是显式传递。
                if ($null -ne $request.PSObject.Properties['DeploymentMode']) { $parameters.DeploymentMode = $route }
                if ($null -ne $operation.PSObject.Properties['ActionIds']) { $parameters.ActionIds = @($operation.ActionIds) }
                $result = @(& $module { param($Parameters) Invoke-JobsPackageChange @Parameters } $parameters)
                $result | ForEach-Object { Write-JobsManagementResult $_ }
                if ($autoCleanup -and $route -eq 'installed' -and $operation.Mode -eq 'Install') {
                    try {
                        $buildPaths = @($result | Where-Object { $null -ne $_.PSObject.Properties['BuildPath'] -and -not [string]::IsNullOrWhiteSpace([string]$_.BuildPath) } | ForEach-Object { $_.BuildPath })
                        foreach ($buildPath in $buildPaths) { & $module { param($Path, $Build) Clear-JobsPackageBuildArtifacts -PackagePath $Path -BuildPath $Build } $operation.PackagePath $buildPath | ForEach-Object { Write-JobsManagementResult $_ } }
                    } catch {
                        # 安装事务已经提交；清理失败只记录警告，不改变安装结果。
                        $cleanupWarning = '安装成功，清理失败：' + $_.Exception.Message
                        [Console]::Error.WriteLine($cleanupWarning)
                    }
                }
            }
            $successMessage = '完成：' + $operation.Label
            if ($cleanupWarning) { $successMessage += '；' + $cleanupWarning }
            Write-JobsManagementEvent -State Succeeded -FeatureIds @($operation.FeatureIds) -Message $successMessage
        } catch {
            Write-JobsManagementEvent -State Failed -FeatureIds @($operation.FeatureIds) -Message ($_.Exception.Message)
            $failedCount++
            [Console]::Error.WriteLine(('本包失败，继续其它所选包：' + $_.Exception.Message))
        }
    }
    if ($failedCount -gt 0) {
        Write-JobsManagementEvent -State Finished -FeatureIds @() -Message ('所选包处理结束；失败 ' + $failedCount + ' 包，其它包已继续处理。')
        exit 1
    }
    Write-JobsManagementEvent -State Finished -FeatureIds @() -Message '全部处理完成；可复制日志或关闭面板。'
}
try { Main } catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
