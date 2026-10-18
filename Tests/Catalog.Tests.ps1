# Catalog.Tests.ps1
# Windows@Extension
# Created by Jobs on 2026年10月18日，星期日.

[CmdletBinding()]
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:assertions = 0
function Assert-True {
    param([bool]$Condition, [string]$Because)
    $script:assertions++
    if (-not $Condition) { throw "断言失败：$Because" }
}

$sourceRoot = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('JobsCatalog-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$module = $null
try {
    # 用十一个只有本包生命周期接口的夹具，不运行真正安装、注册表或右键业务。
    Copy-Item -LiteralPath (Join-Path $sourceRoot 'Extensions.json') -Destination $testRoot
    $parsed = Get-Content -LiteralPath (Join-Path $testRoot 'Extensions.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $entries = @($parsed)
    foreach ($entry in $entries) {
        $package = Join-Path $testRoot $entry.Name
        $scripts = Join-Path $package 'Scripts'
        [void][IO.Directory]::CreateDirectory($scripts)
        Copy-Item -LiteralPath (Join-Path $sourceRoot ($entry.Name + '/Extension.json')) -Destination $package
        foreach ($name in @('Manage.ps1', 'Common.psm1', 'Invoke.ps1', 'Action.psm1')) {
            [IO.File]::WriteAllText((Join-Path $scripts $name), '# Fixture only')
        }
        $installer = @'
function Invoke-JobsPackageChange {
    param([string]$PackagePath, [string]$Mode)
    [pscustomobject]@{ PackagePath = $PackagePath; Mode = $Mode }
}
Export-ModuleMember -Function Invoke-JobsPackageChange
'@
        [IO.File]::WriteAllText((Join-Path $scripts 'PackageInstaller.psm1'), $installer)
    }
    $module = Import-Module (Join-Path $sourceRoot 'Scripts/Catalog.psm1') -PassThru -DisableNameChecking
    $nativePackages = @(Get-JobsFeaturePackages -Root $testRoot)
    Assert-True ($nativePackages.Count -eq 11) '当前 PowerShell 加载十一个独立包'
    Assert-True (@($nativePackages | Where-Object { $_ -is [Management.Automation.PSModuleInfo] }).Count -eq 0) '包清单输出没有模块对象'
    & $module {
        # Windows PowerShell 5.1 的 JSON 顶层数组作为单个管道对象输出。
        function script:ConvertFrom-Json {
            [CmdletBinding()]
            param([Parameter(ValueFromPipeline = $true)][string]$InputObject)
            process {
                $parsedValue = Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $InputObject
                return ,$parsedValue
            }
        }
    }
    $legacyPackages = @(Get-JobsFeaturePackages -Root $testRoot)
    Assert-True ($legacyPackages.Count -eq 11) '模拟 PowerShell 5.1 JSON 非枚举输出仍加载十一个包'
    for ($index = 0; $index -lt $entries.Count; $index++) {
        Assert-True ($legacyPackages[$index].Id -ceq $entries[$index].Id) ('5.1 包身份保持：' + $entries[$index].Id)
        Assert-True ($legacyPackages[$index].PackagePath -eq (Join-Path $testRoot $entries[$index].Name)) ('5.1 包路径保持：' + $entries[$index].Id)
    }
    Assert-True ((Get-Command ConvertFrom-Json).CommandType -eq [Management.Automation.CommandTypes]::Cmdlet) '模拟 JSON helper 只留在 Catalog 模块内'
    $selected = @($entries[0].Id, $entries[3].Id)
    $plan = @(Get-JobsPackageOperationPlan -Packages $legacyPackages -Selected $selected -Installed @() -Mode Install)
    Assert-True ($plan.Count -eq 2) '只为勾选的两个功能生成安装计划'
    Assert-True (@($plan | Where-Object { $_.Id -notin $selected -or $_.Mode -ne 'Install' }).Count -eq 0) '未勾选功能不进入初次安装'
    $resultItems = @(Invoke-JobsPackageOperations -Plan $plan)
    Assert-True ($resultItems.Count -eq 1) '逐包编排只返回一份结果'
    Assert-True ($resultItems[0].Success -and @($resultItems[0].Completed).Count -eq 2) '两个本包生命周期均执行完成'
    Assert-True (@($resultItems | Where-Object { $_ -is [Management.Automation.PSModuleInfo] }).Count -eq 0) '安装器模块对象不泄漏到编排结果'
    Assert-True (@(Get-Module | Where-Object { $_.Path -eq (Join-Path $testRoot ($entries[1].Name + '/Scripts/PackageInstaller.psm1')) }).Count -eq 0) '未勾选功能安装器不参与执行'
    Write-Host ("Catalog tests passed: {0} assertions." -f $script:assertions)
}
finally {
    if ($null -ne $module) { Remove-Module $module }
    foreach ($loaded in @(Get-Module | Where-Object { $_.Path -and $_.Path.StartsWith($testRoot, [StringComparison]::OrdinalIgnoreCase) })) {
        Remove-Module $loaded
    }
    Remove-Item -LiteralPath $testRoot -Recurse -Force
}
