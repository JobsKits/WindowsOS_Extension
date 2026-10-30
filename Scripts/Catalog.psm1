# Catalog.psm1 | WindowsOS@Extension 组合安装清单
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
        # 枚举只读显示元数据；坏包仍可见，只有选中执行时才校验其源码与安装器。
        try {
            $manifest = Get-Content -LiteralPath (Join-Path $packagePath 'Extension.json') -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($manifest.Id -cne $entry.Id -or $manifest.Name -cne $entry.Name) { throw ('功能清单与包身份不一致：' + $entry.Name) }
            foreach ($field in @('Label', 'Description')) {
                if ($null -eq $manifest.PSObject.Properties[$field] -or $manifest.$field -isnot [string] -or [string]::IsNullOrWhiteSpace($manifest.$field)) { throw ('功能清单文本缺失：' + $field) }
            }
        } catch {
            $manifest = [pscustomobject]@{
                Id = $entry.Id; Name = $entry.Name; Label = $entry.Name
                Description = '本包清单不可用，执行时会报告具体失败：' + $_.Exception.Message
                CatalogError = $_.Exception.Message
            }
        }
        $manifest | Add-Member -NotePropertyName PackagePath -NotePropertyValue $packagePath -PassThru -Force
    }
}

# 面板来源：普通 Id 来自 Extensions.json/包清单；Flutter 叶子来自唯一 FeatureActions，勿在此复制动作表。
function Get-JobsSelectableFeatures {
    param([object[]]$Packages)
    foreach ($package in $Packages) {
        if ($package.Id -cne 'flutter-tools') { $package; continue }
        try {
            $actionRoot = Join-Path $PSScriptRoot '../JobsFlutterTools'
            if ($null -ne $package.PSObject.Properties['PackagePath']) { $actionRoot = $package.PackagePath }
            $actions = Import-Module (Join-Path $actionRoot 'Scripts/FeatureActions.psm1') -PassThru -DisableNameChecking -ErrorAction Stop
            $catalog = @(& $actions { Get-JobsFlutterActionCatalog })
        } catch {
            $package.Description += "`r`nFlutter 动作清单不可用，执行时报告失败：" + $_.Exception.Message
            $package
            continue
        }
        foreach ($entry in $catalog) {
            [pscustomobject]@{
                Id = 'flutter-' + $entry.Id; Label = $entry.Label; Description = $package.Description
                PackageId = $package.Id; ActionId = $entry.Id; Group = $entry.Group
            }
        }
    }
}

function Expand-JobsFeatureSelection {
    param([object[]]$Packages, [string[]]$Selected)
    $features = @(Get-JobsSelectableFeatures -Packages $Packages)
    foreach ($id in @($Selected)) {
        if ($id -ceq 'flutter-tools' -and $id -cin @($Packages.Id)) {
            $features | Where-Object { $_.Id -clike 'flutter-*' } | ForEach-Object { $_.Id }
        } elseif ($id -cin @($features.Id)) { $id }
        else { throw ('未知功能标识：' + $id) }
    }
}

# 选择映射：普通选项一包一事务；flutter-* 叶子折叠成 flutter-tools 的 ActionIds，未选功能保留既有策略。
function Get-JobsPackageOperationPlan {
    param([object[]]$Packages, [string[]]$Selected, [string[]]$Installed, [ValidateSet('Install', 'Configure', 'Uninstall')][string]$Mode)
    $selectedFeatures = @(Expand-JobsFeatureSelection -Packages $Packages -Selected $Selected)
    $installedFeatures = @(Expand-JobsFeatureSelection -Packages $Packages -Selected $Installed)
    foreach ($package in $Packages) {
        if ($package.Id -ceq 'flutter-tools') {
            $prefix = 'flutter-'
            $chosen = @($selectedFeatures | Where-Object { $_ -clike 'flutter-*' })
            $existing = @($installedFeatures | Where-Object { $_ -clike 'flutter-*' })
            $remaining = $chosen
            if ($Mode -eq 'Uninstall') { $remaining = @($existing | Where-Object { $_ -cnotin $chosen }) }
            elseif ($Mode -eq 'Install') {
                # 管理面板默认空选；安装所选动作时保留本包已启用的兄弟动作。
                $enabled = @($existing) + @($chosen)
                $remaining = @(Get-JobsSelectableFeatures -Packages @($package) | Where-Object { $_.Id -cin $enabled } | ForEach-Object { $_.Id })
            }
            $change = ($Mode -eq 'Configure' -and ($chosen.Count -gt 0 -or $existing.Count -gt 0)) -or
                ($Mode -eq 'Install' -and $chosen.Count -gt 0) -or
                ($Mode -eq 'Uninstall' -and @($existing | Where-Object { $_ -cin $chosen }).Count -gt 0)
            if ($change) {
                $operation = 'Install'
                if ($remaining.Count -eq 0) { $operation = 'Uninstall' }
                [pscustomobject]@{ Id = $package.Id; Name = $(if ($null -ne $package.PSObject.Properties['Name']) { $package.Name } else { '' }); Label = $package.Label; PackagePath = $package.PackagePath
                    Mode = $operation; DisplayMode = $Mode; FeatureIds = @($(if ($Mode -eq 'Configure') { @($existing + $chosen | Select-Object -Unique) } else { $chosen })); ActionIds = @($remaining | ForEach-Object { $_.Substring($prefix.Length) }) }
            }
            continue
        }
        $operation = $null
        if ($Mode -eq 'Uninstall') {
            if ($package.Id -in $selectedFeatures -and $package.Id -in $installedFeatures) { $operation = 'Uninstall' }
        } elseif ($package.Id -in $selectedFeatures) { $operation = 'Install' }
        elseif ($Mode -eq 'Configure' -and $package.Id -in $installedFeatures) { $operation = 'Uninstall' }
        if ($operation) {
            [pscustomobject]@{ Id = $package.Id; Name = $(if ($null -ne $package.PSObject.Properties['Name']) { $package.Name } else { '' }); Label = $package.Label; PackagePath = $package.PackagePath; Mode = $operation; DisplayMode = $Mode; FeatureIds = @($package.Id) }
        }
    }
}

function Invoke-JobsPackageOperations {
    param([object[]]$Plan, [scriptblock]$Executor)
    $completed = @()
    $failures = @()
    foreach ($operation in $Plan) {
        try {
            if ($Executor) { & $Executor $operation | Out-Null }
            else {
                # 使用包自己的安装模块；不加载 Action，也不复制未选择功能的运行代码。
                $installer = Import-Module (Join-Path $operation.PackagePath 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
                if ($null -ne $operation.PSObject.Properties['ActionIds']) {
                    & $installer { param($Path, $Mode, $Ids) Invoke-JobsPackageChange -PackagePath $Path -Mode $Mode -ActionIds $Ids } $operation.PackagePath $operation.Mode @($operation.ActionIds) | Out-Null
                } else {
                    & $installer { param($Path, $Mode) Invoke-JobsPackageChange -PackagePath $Path -Mode $Mode } $operation.PackagePath $operation.Mode | Out-Null
                }
            }
            $completed += ($operation.Mode + ':' + $operation.Id)
        } catch {
            $failures += [pscustomobject]@{ Id = $operation.Id; Message = $_.Exception.Message }
        }
    }
    $firstFailed = $null
    if ($failures.Count -gt 0) { $firstFailed = $failures[0].Id }
    return [pscustomobject]@{ Success = ($failures.Count -eq 0); Completed = $completed; Failed = $firstFailed; Failures = @($failures); Message = (@($failures | ForEach-Object { $_.Message }) -join '; ') }
}

Export-ModuleMember -Function Get-JobsFeaturePackages, Get-JobsSelectableFeatures, Expand-JobsFeatureSelection, Get-JobsPackageOperationPlan, Invoke-JobsPackageOperations
