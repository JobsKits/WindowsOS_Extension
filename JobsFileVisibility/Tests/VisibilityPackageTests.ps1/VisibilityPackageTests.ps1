# VisibilityPackageTests.ps1 | JobsFileVisibility
# Created by Jobs on 2026年11月18日，星期三.
# Isolated package, registry-plan and translation checks; no registry writes or native DLL loading.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$script:Assertions = 0
# Fail immediately with the behavior being verified.
function Assert-Visibility {
    param([bool]$Condition,[string]$Message)
    $script:Assertions++
    if (-not $Condition) { throw $Message }
}
# Verify a moved package publishes itself without source-repository dependencies.
function Main {
    $package = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('Jobs 可见性 !&%-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($temporary)
    try {
        $copy = Join-Path $temporary '已改名独立包'
        Copy-Item -LiteralPath $package -Destination $copy -Recurse
        $module = Import-Module (Join-Path $copy 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
        $manifest = Get-Content -LiteralPath (Join-Path $copy 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($enabled in @($true,$false)) {
            $plan = @(Get-JobsPackageRegistryPlan -Manifest $manifest -ReleasePath $copy -PowerShellPath 'powershell.exe' -Enabled $enabled)
            Assert-Visibility ($plan.Count -eq 3) 'only file/directory handlers and own CLSID'
            Assert-Visibility (@($plan | Where-Object { $_.Enabled -ne $enabled }).Count -eq 0) 'install/uninstall use the same exact scope'
            Assert-Visibility (@($plan | Where-Object { $_.Key -match 'DesktopBackground|Directory\\Background|Classes\\Drive' }).Count -eq 0) 'no background or drive registration'
            Assert-Visibility ($plan[2].InProcServer -eq (Join-Path $copy 'bin/JobsFileVisibilityContextMenu.dll')) 'native DLL stays within moved package'
        }
        $release = Join-Path $temporary 'release'
        New-JobsPackageRelease -PackagePath $copy -Destination $release | Out-Null
        foreach ($relative in @('Extension.json','Manage.cmd','Manage.vbs','Scripts/Invoke.ps1','Scripts/Action.psm1','Scripts/Common.psm1','Scripts/SelectionPanel.psm1','Scripts/ManagementWorker.ps1','Scripts/Manage.ps1','Scripts/Build.ps1','Scripts/PackageInstaller.psm1','Scripts/ContextMenu.cpp','Scripts/ContextMenu.def','Scripts/FileVisibility.h','Scripts/FileVisibilityText.h','Scripts/VisibilityRuntime.h')) {
            Assert-Visibility (Test-Path -LiteralPath (Join-Path $release $relative) -PathType Leaf) ('release includes ' + $relative)
        }
        $sourceNames = @('Scripts/Invoke.ps1/Invoke.ps1','Scripts/Build.ps1/Build.ps1','Scripts/Manage.ps1/Manage.ps1','Scripts/ManagementWorker.ps1/ManagementWorker.ps1')
        foreach ($name in $sourceNames) {
            $flat = $name -replace '/[^/]+$',''
            Assert-Visibility ((Get-FileHash -LiteralPath (Join-Path $copy $name)).Hash -eq (Get-FileHash -LiteralPath (Join-Path $release $flat)).Hash) ('source/flat release match: ' + $flat)
        }
        Assert-Visibility (-not (Test-Path -LiteralPath (Join-Path $release 'Tests'))) 'development fixtures excluded from release'
        $action = Import-Module (Join-Path $release 'Scripts/Action.psm1') -PassThru -DisableNameChecking
        $rejected = $false
        try { & $action { Invoke-JobsFeature -Target 'C:\fixture' -State 'Toggle' } } catch { $rejected = $true }
        Assert-Visibility $rejected 'ambiguous toggle action rejected before native code'
        $invalid = $false
        try { & $action { Invoke-JobsFeature -Target @() -State 'Hide' } } catch { $invalid = $true }
        Assert-Visibility $invalid 'empty selection rejected'
        $panel = Import-Module (Join-Path $release 'Scripts/SelectionPanel.psm1') -PassThru -DisableNameChecking
        foreach ($code in @('zh-Hans','zh-Hant','bo','en','ja','fr','es','de','ru','ko')) {
            $translated = Get-JobsPanelText $manifest.Label $code
            Assert-Visibility (-not [string]::IsNullOrWhiteSpace($translated)) ('panel label translated: ' + $code)
            Assert-Visibility (-not [string]::IsNullOrWhiteSpace((Get-JobsPanelText $manifest.Description $code))) ('panel description translated: ' + $code)
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $release -File -Recurse | Where-Object { $_.Extension -in @('.ps1','.psm1') })) {
            $tokens = $null; $errors = $null
            [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
            Assert-Visibility (@($errors).Count -eq 0) ('PowerShell syntax: ' + $file.Name)
        }
        Write-Host ('PASS: {0} isolated package assertions' -f $script:Assertions)
    } finally {
        foreach ($module in @($module,$action,$panel)) { if ($null -ne $module) { Remove-Module $module -ErrorAction SilentlyContinue } }
        if (Test-Path -LiteralPath $temporary) { [IO.Directory]::Delete($temporary,$true) }
    }
}
Main
