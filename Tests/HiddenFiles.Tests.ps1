# HiddenFiles.Tests.ps1 | JobsHiddenFilesToggler
# Created by Jobs on 2026年10月26日，星期一.
# Registry fixtures never touch real Explorer preferences or notify the desktop.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$package = Join-Path $root 'JobsHiddenFilesToggler'
$module = Import-Module (Join-Path $package 'Scripts/Action.psm1') -PassThru -DisableNameChecking
$script:count = 0
function Assert { param([bool]$Value, [string]$Why); if (-not $Value) { throw ('FAIL: ' + $Why) }; $script:count++ }
function Throws { param([scriptblock]$Body, [string]$Why); $caught = $false; try { & $Body | Out-Null } catch { $caught = $true }; Assert $caught $Why }
function New-RegistryFixture {
    $fixture = [pscustomobject]@{ Values = @{ Hidden = 2; ShowSuperHidden = 0; Other = 'preserved' }; Kind = [Microsoft.Win32.RegistryValueKind]::DWord; Writes = 0; Reads = 0; Exists = $true; FailRead = $false }
    $fixture | Add-Member ScriptMethod OpenSubKey {
        param($Path, $Writable)
        if ($Path -cne 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -or $Writable) { throw 'Unexpected registry scope' }
        $this.Reads++
        if ($this.FailRead) { throw 'Access denied fixture' }
        if ($this.Exists) { return $this }
        return $null
    }
    $fixture | Add-Member ScriptMethod CreateSubKey { param($Path); if ($Path -cne 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced') { throw 'Unexpected write scope' }; $this.Exists = $true; return $this }
    $fixture | Add-Member ScriptMethod GetValue { param($Name, $Default, $Options); if ($this.Values.ContainsKey($Name)) { return $this.Values[$Name] }; return $Default }
    $fixture | Add-Member ScriptMethod GetValueKind { param($Name); return $this.Kind }
    $fixture | Add-Member ScriptMethod SetValue { param($Name, $Value, $Kind); if ($Name -cne 'Hidden' -or $Kind -ne [Microsoft.Win32.RegistryValueKind]::DWord) { throw 'Unexpected preference mutation' }; $this.Values[$Name] = $Value; $this.Writes++ }
    $fixture | Add-Member ScriptMethod Flush { }
    $fixture | Add-Member ScriptMethod Dispose { }
    return $fixture
}
try {
    $fixture = New-RegistryFixture
    Assert ($fixture.Reads -eq 0 -and $fixture.Writes -eq 0) 'module import has no preference effect'
    Assert ((& $module { param($Registry) Get-JobsHiddenFilesState -RegistryRoot $Registry } $fixture) -eq 2) 'hidden state read'
    Assert ($fixture.Writes -eq 0) 'menu-style read never writes'
    $next = & $module { param($Registry) Invoke-JobsHiddenFilesToggle -RegistryRoot $Registry } $fixture
    Assert ($next -eq 1 -and $fixture.Values.Hidden -eq 1 -and $fixture.Writes -eq 1) 'hidden to visible'
    $next = & $module { param($Registry) Invoke-JobsHiddenFilesToggle -RegistryRoot $Registry } $fixture
    Assert ($next -eq 2 -and $fixture.Values.Hidden -eq 2 -and $fixture.Writes -eq 2) 'visible to hidden'
    $explicit = & $module { param($Registry) Invoke-JobsHiddenFilesToggle -RegistryRoot $Registry -Visibility Show } $fixture
    Assert ($explicit -eq 1 -and $fixture.Writes -eq 3) 'explicit show applies the labelled target'
    $explicit = & $module { param($Registry) Invoke-JobsHiddenFilesToggle -RegistryRoot $Registry -Visibility Show } $fixture
    Assert ($explicit -eq 1 -and $fixture.Writes -eq 3) 'stale show menu never hides an already visible state'
    $explicit = & $module { param($Registry) Invoke-JobsHiddenFilesToggle -RegistryRoot $Registry -Visibility Hide } $fixture
    Assert ($explicit -eq 2 -and $fixture.Writes -eq 4) 'explicit hide applies the labelled target'
    $explicit = & $module { param($Registry) Invoke-JobsHiddenFilesToggle -RegistryRoot $Registry -Visibility Hide } $fixture
    Assert ($explicit -eq 2 -and $fixture.Writes -eq 4) 'stale hide menu never shows an already hidden state'
    Assert ($fixture.Values.ShowSuperHidden -eq 0 -and $fixture.Values.Other -ceq 'preserved' -and $fixture.Values.Count -eq 3) 'protected system file and other preferences remain untouched'
    $fixture.Values.Remove('Hidden')
    Assert ((& $module { param($Registry) Get-JobsHiddenFilesState -RegistryRoot $Registry } $fixture) -eq 2) 'missing value has normal hidden default'
    $fixture.Exists = $false
    Assert ((& $module { param($Registry) Get-JobsHiddenFilesState -RegistryRoot $Registry } $fixture) -eq 2) 'missing advanced key is only read as default'
    Assert (-not $fixture.Exists -and $fixture.Writes -eq 4) 'query does not create missing key'
    Assert ((& $module { param($Registry) Invoke-JobsHiddenFilesToggle -RegistryRoot $Registry } $fixture) -eq 1 -and $fixture.Exists) 'explicit action can create only the preference key'
    foreach ($invalid in @(0, 3, '1', $true)) {
        $fixture.Values.Hidden = $invalid
        $before = $fixture.Writes
        Throws { & $module { param($Registry) Invoke-JobsHiddenFilesToggle -RegistryRoot $Registry } $fixture } 'invalid state stops before write'
        Assert ($fixture.Writes -eq $before) 'invalid state preserved'
    }
    $fixture.Values.Hidden = 1
    $fixture.Kind = [Microsoft.Win32.RegistryValueKind]::String
    Throws { & $module { param($Registry) Invoke-JobsHiddenFilesToggle -RegistryRoot $Registry } $fixture } 'wrong registry value kind rejected'
    $fixture.Kind = [Microsoft.Win32.RegistryValueKind]::DWord
    $fixture.FailRead = $true
    Throws { & $module { param($Registry) Invoke-JobsHiddenFilesToggle -RegistryRoot $Registry } $fixture } 'read error is not guessed as a state'
    Add-Type -Path (Join-Path $package 'Scripts/ExplorerRefresher.cs')
    Assert ($null -ne ('Jobs.ExplorerRefresher' -as [type])) 'notification wrapper compiles without calling native APIs'
    $installer = Import-Module (Join-Path $package 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    $manifest = Get-Content -LiteralPath (Join-Path $package 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $plan = @(& $installer { param($Manifest) Get-JobsPackageRegistryPlan -Manifest $Manifest -ReleasePath '/temporary/release' -PowerShellPath 'powershell.exe' } $manifest)
    Assert ($plan.Count -eq 2 -and $plan[0].Key -ceq 'Software\Classes\DesktopBackground\shellex\ContextMenuHandlers\Jobs.WindowsExtension.hidden-files-toggle') 'only desktop background handler and own CLSID'
    Assert ($plan[1].InProcServer.EndsWith((Join-Path 'bin' 'JobsHiddenFilesTogglerContextMenu.dll'))) 'own native release path'
    $disabled = @(& $installer { param($Manifest) Get-JobsPackageRegistryPlan -Manifest $Manifest -ReleasePath '/temporary/release' -PowerShellPath 'powershell.exe' -Enabled $false } $manifest)
    Assert (@($disabled | Where-Object Enabled).Count -eq 0) 'uninstall only disables registration'
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $testName = 'Software\Jobs\Tests\HiddenFiles-' + [guid]::NewGuid().ToString('N')
        $registry = [Microsoft.Win32.Registry]::CurrentUser
        $temporary = $registry.CreateSubKey($testName)
        try {
            $key = $temporary.CreateSubKey('Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced')
            try { $key.SetValue('Hidden', 2, [Microsoft.Win32.RegistryValueKind]::DWord); $key.SetValue('ShowSuperHidden', 0, [Microsoft.Win32.RegistryValueKind]::DWord) } finally { $key.Dispose() }
            Assert ((& $module { param($Registry) Invoke-JobsHiddenFilesToggle -RegistryRoot $Registry } $temporary) -eq 1) 'temporary Windows registry toggles visible'
            Assert ((& $module { param($Registry) Invoke-JobsHiddenFilesToggle -RegistryRoot $Registry } $temporary) -eq 2) 'temporary Windows registry toggles hidden'
            $key = $temporary.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced')
            try { Assert ($key.GetValue('ShowSuperHidden') -eq 0) 'temporary registry system-file setting preserved' } finally { $key.Dispose() }
        } finally { $temporary.Dispose(); $registry.DeleteSubKeyTree($testName, $false) }
    } else { Write-Host 'SKIP: temporary Windows registry/API branch requires Windows; real Explorer preferences were not read or changed.' }
    Write-Host ('PASS: HiddenFiles (' + $script:count + ' assertions)')
} finally { Remove-Module $module -ErrorAction SilentlyContinue }
