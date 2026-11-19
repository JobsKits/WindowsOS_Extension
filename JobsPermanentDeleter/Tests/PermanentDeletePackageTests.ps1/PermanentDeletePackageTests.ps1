# PermanentDeletePackageTests.ps1 | JobsPermanentDeleter
# Created by Jobs on 2026年11月18日，星期三.
# Isolated publishing, prebuilt-integrity mutations and management plans; never registers or deletes user targets.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$script:Assertions = 0
# Stop at the first behavior regression with its scenario name.
function Assert-DeletePackage {
    param([bool]$Condition,[string]$Message)
    $script:Assertions++
    if (-not $Condition) { throw $Message }
}
# Verify a fully moved package, including both source-bound native architectures.
function Main {
    $package = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('Jobs 永久删除 !&%-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($temporary)
    try {
        $copy = Join-Path $temporary '已改名独立包'
        Copy-Item -LiteralPath $package -Destination $copy -Recurse
        $module = Import-Module (Join-Path $copy 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
        $manifest = Get-Content -LiteralPath (Join-Path $copy 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($enabled in @($true,$false)) {
            $plan = @(Get-JobsPackageRegistryPlan -Manifest $manifest -ReleasePath $copy -PowerShellPath 'powershell.exe' -Enabled $enabled)
            Assert-DeletePackage ($plan.Count -eq 3) 'only file/directory handlers and own CLSID'
            Assert-DeletePackage (@($plan | Where-Object { $_.Enabled -ne $enabled }).Count -eq 0) 'same exact install/uninstall registration scope'
            Assert-DeletePackage (@($plan | Where-Object { $_.Key -match 'DesktopBackground|Directory\\Background|Classes\\Drive' }).Count -eq 0) 'no background or drive registration'
            Assert-DeletePackage ($plan[2].InProcServer -eq (Join-Path $copy 'bin/JobsPermanentDeleterContextMenu.dll')) 'runtime DLL uses explicit deployed name'
            Assert-DeletePackage ($plan[2].Key -match '79022A9C-59CF-485A-90D8-67C67EE7CE33') 'feature owns distinct CLSID'
        }
        $release = Join-Path $temporary 'release'
        New-JobsPackageRelease -PackagePath $copy -Destination $release | Out-Null
        foreach ($relative in @('Extension.json','Manage.cmd','Manage.vbs','Scripts/Invoke.ps1','Scripts/Action.psm1','Scripts/Common.psm1','Scripts/SelectionPanel.psm1','Scripts/ManagementWorker.ps1','Scripts/Manage.ps1','Scripts/Build.ps1','Scripts/PackageInstaller.psm1','Scripts/Prebuilt.psm1','Scripts/ContextMenu.cpp','Scripts/ContextMenu.def','Scripts/PermanentDelete.h','Scripts/DeleteText.h','Scripts/DeleteDialog.h','Dist/BuildVerification.json','Dist/x64/JobsPermanentDeleter.dll','Dist/arm64/JobsPermanentDeleter.dll')) {
            Assert-DeletePackage (Test-Path -LiteralPath (Join-Path $release $relative) -PathType Leaf) ('release includes ' + $relative)
        }
        Assert-DeletePackage (-not (Test-Path -LiteralPath (Join-Path $release 'Tests'))) 'development tests excluded from runtime release'
        Import-Module (Join-Path $release 'Scripts/Prebuilt.psm1') -DisableNameChecking
        foreach ($architecture in @('x64','arm64')) {
            $valid = Get-JobsVerifiedPrebuiltBinary -SourceRoot $release -Target $architecture
            Assert-DeletePackage ($valid.Path -eq (Join-Path $release ('Dist/' + $architecture + '/JobsPermanentDeleter.dll'))) ('moved prebuilt verified for ' + $architecture)
        }
        Assert-DeletePackage ($null -eq (Get-JobsVerifiedPrebuiltBinary -SourceRoot $release -Target 'x86')) 'x86 explicitly falls back to local MSVC'
        $native = Join-Path $release 'Scripts/PermanentDelete.h'
        $original = [IO.File]::ReadAllBytes($native)
        [IO.File]::AppendAllText($native,"`n// source changed`n")
        Assert-DeletePackage ($null -eq (Get-JobsVerifiedPrebuiltBinary -SourceRoot $release -Target 'x64')) 'changed native source rejects stale prebuilt'
        [IO.File]::WriteAllBytes($native,$original)
        $receipt = Join-Path $release 'Dist/BuildVerification.json'
        $originalReceipt = [IO.File]::ReadAllText($receipt)
        $data = $originalReceipt | ConvertFrom-Json
        $data.nativeSources.PSObject.Properties.Remove('Scripts/DeleteText.h')
        [IO.File]::WriteAllText($receipt,($data|ConvertTo-Json -Depth 8))
        Assert-DeletePackage ($null -eq (Get-JobsVerifiedPrebuiltBinary -SourceRoot $release -Target 'x64')) 'incomplete source-key set rejected'
        $data = $originalReceipt | ConvertFrom-Json
        $data.binaries.x64.path = '../outside.dll'
        [IO.File]::WriteAllText($receipt,($data|ConvertTo-Json -Depth 8))
        Assert-DeletePackage ($null -eq (Get-JobsVerifiedPrebuiltBinary -SourceRoot $release -Target 'x64')) 'receipt traversal path rejected'
        [IO.File]::WriteAllText($receipt,$originalReceipt)
        $dll = Join-Path $release 'Dist/x64/JobsPermanentDeleter.dll'
        $originalDll = [IO.File]::ReadAllBytes($dll)
        $corrupt = [byte[]]$originalDll.Clone()
        $corrupt[$corrupt.Length-1] = $corrupt[$corrupt.Length-1] -bxor 1
        [IO.File]::WriteAllBytes($dll,$corrupt)
        Assert-DeletePackage ($null -eq (Get-JobsVerifiedPrebuiltBinary -SourceRoot $release -Target 'x64')) 'binary hash corruption rejected'
        [IO.File]::WriteAllBytes($dll,$originalDll)
        $data = $originalReceipt | ConvertFrom-Json
        $data.binaries.x64.sha256 = $data.binaries.arm64.sha256
        Copy-Item -LiteralPath (Join-Path $release 'Dist/arm64/JobsPermanentDeleter.dll') -Destination $dll -Force
        [IO.File]::WriteAllText($receipt,($data|ConvertTo-Json -Depth 8))
        Assert-DeletePackage ($null -eq (Get-JobsVerifiedPrebuiltBinary -SourceRoot $release -Target 'x64')) 'wrong machine rejected even with matching hash'
        [IO.File]::WriteAllBytes($dll,$originalDll)
        [IO.File]::WriteAllText($receipt,$originalReceipt)
        Import-Module (Join-Path $release 'Scripts/SelectionPanel.psm1') -DisableNameChecking
        foreach ($code in @('zh-Hans','zh-Hant','bo','en','ja','fr','es','de','ru','ko')) {
            $label = Get-JobsPanelText $manifest.Label $code
            $description = Get-JobsPanelText $manifest.Description $code
            Assert-DeletePackage (-not [string]::IsNullOrWhiteSpace($label)) ('panel label translated: ' + $code)
            Assert-DeletePackage (-not [string]::IsNullOrWhiteSpace($description)) ('panel description translated: ' + $code)
            if ($code -ne 'zh-Hans') { Assert-DeletePackage ($label -cne $manifest.Label) ('no source-language fallback: ' + $code) }
        }
        foreach ($file in @(Get-ChildItem -LiteralPath $release -File -Recurse | Where-Object { $_.Extension -in @('.ps1','.psm1') })) {
            $tokens = $null; $errors = $null
            [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
            Assert-DeletePackage (@($errors).Count -eq 0) ('PowerShell syntax: ' + $file.Name)
        }
        Write-Host ('PASS: {0} permanent-delete package assertions' -f $script:Assertions)
    } finally {
        if ([IO.Directory]::Exists($temporary)) { [IO.Directory]::Delete($temporary,$true) }
    }
}
Main
