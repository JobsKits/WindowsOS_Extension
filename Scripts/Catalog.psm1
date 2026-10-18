# Catalog.psm1 | Windows@Extension 组合安装清单
# Created by Jobs on 2026年10月18日，星期日.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Get-JobsFeaturePackages {
    param([string]$Root = (Split-Path -Parent $PSScriptRoot))
    # Windows PowerShell 5.1 会把 JSON 顶层数组作为单一管道对象返回，先赋值再枚举。
    $parsed = Get-Content -LiteralPath (Join-Path $Root 'Extensions.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $entries = @($parsed)
    $seen = @{}
    foreach ($entry in $entries) {
        if ($entry.Id -notmatch '^[a-z][a-z0-9-]+$' -or $entry.Name -notmatch '^Jobs[A-Za-z0-9]+$') { throw '组合清单包含不合法的包名或标识。' }
        if ($seen.ContainsKey($entry.Id) -or $seen.ContainsKey($entry.Name)) { throw '组合清单中的包名和标识必须唯一。' }
        $seen[$entry.Id] = $true
        $seen[$entry.Name] = $true
        $packagePath = Join-Path $Root $entry.Name
        $manifest = Get-Content -LiteralPath (Join-Path $packagePath 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($manifest.Id -cne $entry.Id -or $manifest.Name -cne $entry.Name) { throw ('功能清单与包身份不一致：' + $entry.Name) }
        foreach ($name in @('Manage.ps1', 'PackageInstaller.psm1', 'Common.psm1', 'Invoke.ps1', 'Action.psm1')) {
            if (-not (Test-Path -LiteralPath (Join-Path $packagePath ('Scripts/' + $name)) -PathType Leaf)) { throw ('独立包不完整：' + $entry.Name + '/' + $name) }
        }
        $manifest | Add-Member -NotePropertyName PackagePath -NotePropertyValue $packagePath -PassThru
    }
}

function Get-JobsPackageOperationPlan {
    param([object[]]$Packages, [string[]]$Selected, [string[]]$Installed, [ValidateSet('Install', 'Configure', 'Uninstall')][string]$Mode)
    $known = @($Packages | ForEach-Object { $_.Id })
    foreach ($id in @($Selected) + @($Installed)) {
        if ($id -notin $known) { throw ('未知功能标识：' + $id) }
    }
    foreach ($package in $Packages) {
        $operation = $null
        if ($Mode -eq 'Uninstall') {
            if ($package.Id -in $Selected -and $package.Id -in $Installed) { $operation = 'Uninstall' }
        } elseif ($package.Id -in $Selected) { $operation = 'Install' }
        elseif ($package.Id -in $Installed) { $operation = 'Uninstall' }
        if ($operation) {
            [pscustomobject]@{ Id = $package.Id; Label = $package.Label; PackagePath = $package.PackagePath; Mode = $operation }
        }
    }
}

function Invoke-JobsPackageOperations {
    param([object[]]$Plan, [scriptblock]$Executor)
    $completed = @()
    foreach ($operation in $Plan) {
        try {
            if ($Executor) { & $Executor $operation | Out-Null }
            else {
                # 使用包自己的安装模块；不加载 Action，也不复制未选择功能的运行代码。
                $installer = Import-Module (Join-Path $operation.PackagePath 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
                & $installer { param($Path, $Mode) Invoke-JobsPackageChange -PackagePath $Path -Mode $Mode } $operation.PackagePath $operation.Mode | Out-Null
            }
            $completed += ($operation.Mode + ':' + $operation.Id)
        } catch {
            return [pscustomobject]@{ Success = $false; Completed = $completed; Failed = $operation.Id; Message = $_.Exception.Message }
        }
    }
    return [pscustomobject]@{ Success = $true; Completed = $completed; Failed = $null; Message = $null }
}

Export-ModuleMember -Function Get-JobsFeaturePackages, Get-JobsPackageOperationPlan, Invoke-JobsPackageOperations
