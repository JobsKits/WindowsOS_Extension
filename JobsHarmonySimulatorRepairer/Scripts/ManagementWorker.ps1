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
    $failedCount = 0
    for ($index = 0; $index -lt $operations.Count; $index++) {
        $operation = $operations[$index]
        Write-JobsManagementEvent -State Running -FeatureIds @($operation.FeatureIds) -Message ($operation.DisplayMode + '：' + $operation.Label)
        try {
            if ($operation.Mode -notin @('Install', 'Uninstall')) { throw '所选包的操作模式无效。' }
            $manifestPath = Join-Path $operation.PackagePath 'Extension.json'
            $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($manifest.Id -cne $operation.Id -or ($null -ne $operation.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$operation.Name) -and $manifest.Name -cne $operation.Name)) { throw ('功能清单与所选包身份不一致：' + $operation.PackagePath) }
            $modulePath = Join-Path $operation.PackagePath 'Scripts/PackageInstaller.psm1'
            if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw ('所选包缺少安装器：' + $modulePath) }
            $module = Import-Module $modulePath -PassThru -Force -DisableNameChecking
            Write-Host ('来源：' + $operation.PackagePath)
            if ($null -ne $operation.PSObject.Properties['ActionIds']) {
                & $module { param($Path, $Mode, $Ids) Invoke-JobsPackageChange -PackagePath $Path -Mode $Mode -ActionIds $Ids } $operation.PackagePath $operation.Mode @($operation.ActionIds) | ForEach-Object { Write-JobsManagementResult $_ }
            } else {
                & $module { param($Path, $Mode) Invoke-JobsPackageChange -PackagePath $Path -Mode $Mode } $operation.PackagePath $operation.Mode | ForEach-Object { Write-JobsManagementResult $_ }
            }
            Write-JobsManagementEvent -State Succeeded -FeatureIds @($operation.FeatureIds) -Message ('完成：' + $operation.Label)
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
