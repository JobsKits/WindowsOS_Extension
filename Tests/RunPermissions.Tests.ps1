# RunPermissions.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月24日，星期六.
# Cross-platform transaction fixtures; real ACL checks only use temporary NTFS files on Windows.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsRunPermissions-' + [guid]::NewGuid().ToString('N'))
$module = Import-Module (Join-Path $root 'JobsRunAuthorizer/Scripts/Action.psm1') -PassThru -DisableNameChecking
$script:count = 0
function Assert { param([bool]$Value, [string]$Why); if (-not $Value) { throw ('FAIL: ' + $Why) }; $script:count++ }
function Throws { param([scriptblock]$Body, [string]$Why); $caught = $false; try { & $Body | Out-Null } catch { $caught = $true }; Assert $caught $Why }
function New-Fixture {
    $file = [pscustomobject]@{ Identity = 'fixture-id'; Hash = 'hash-1'; Path = 'fixture-path'; Sddl = 'base'; Applies = 0; ForceDeny = $false }
    $file | Add-Member ScriptMethod Capture { return $this.Sddl }
    $file | Add-Member ScriptMethod Apply { param($Expected, $Replacement); if ($Expected -cne $this.Sddl) { throw 'conflict' }; $this.Sddl = $Replacement; $this.Applies++ }
    $file | Add-Member ScriptMethod HasExecute { return $this.Sddl.EndsWith('|Grant') -and -not $this.ForceDeny }
    return $file
}
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $core = Join-Path $root 'JobsRunAuthorizer/Scripts/RunPermissionFile.cs'
    Add-Type -Path $core
    Assert ($null -ne ('Jobs.RunPermissionFile' -as [type])) 'native handle core compiles'
    foreach ($path in @('C:\测试 & !\app.EXE', 'C:\dir\run.cmd', 'C:\dir\script.ps1', 'C:\dir\worker.py', 'C:\dir\start.sh')) {
        Assert ([Jobs.RunPermissionFile]::IsExecutablePath($path)) ('executable or script format accepted: ' + $path)
    }
    foreach ($path in @('README.md', 'notes.txt', 'archive.zip', 'app.exe.txt', 'settings.psd1', 'no-extension')) {
        Assert (-not [Jobs.RunPermissionFile]::IsExecutablePath($path)) ('ordinary data format rejected: ' + $path)
    }
    $header = [IO.File]::ReadAllText((Join-Path $root 'JobsRunAuthorizer/Scripts/RunPermissionTarget.h'))
    foreach ($match in [regex]::Matches($header, 'L"(\.[a-z0-9]+)"')) {
        Assert ([Jobs.RunPermissionFile]::IsExecutablePath('fixture' + $match.Groups[1].Value)) 'native menu and backend accept the same executable formats'
    }
    . (Join-Path $root 'JobsRunAuthorizer/Scripts/TerminalLauncher.ps1')
    $transportTarget = Join-Path $temporary '脚本 & 100% !.exe'
    [IO.File]::WriteAllText($transportTarget, 'inert transport fixture')
    $start = New-JobsPermissionTerminalStart $transportTarget (Join-Path $root 'JobsRunAuthorizer/Scripts') $temporary 'powershell.exe'
    Assert ($start.WorkingDirectory -ceq (Get-Item -LiteralPath $transportTarget).DirectoryName) 'single-file terminal starts in parent directory, never file path'
    Assert ($start.EnvironmentVariables['JOBS_RUN_PERMISSION_TARGET'] -ceq $transportTarget -and -not $start.Arguments.Contains($transportTarget)) 'CMD keeps metacharacter file path in process environment'
    Assert ($start.Arguments.StartsWith('/d /v:off /k ') -and -not $start.UseShellExecute) 'fixed transport disables delayed expansion and shell interpolation'
    Throws { New-JobsPermissionTerminalStart $temporary $root $temporary 'powershell.exe' } 'terminal refuses directory target'
    foreach ($name in @('RunPermissions.ps1', 'RunPermissionFile.cs', 'RunPermissionTarget.h')) {
        Assert ((Get-FileHash -LiteralPath (Join-Path $root ('JobsRunAuthorizer/Scripts/' + $name))).Hash -ceq (Get-FileHash -LiteralPath (Join-Path $root ('JobsRunAuthorizationRevoker/Scripts/' + $name))).Hash) 'paired packages carry identical independent core'
    }
    & $module { function script:Get-JobsPermissionReplacement { param($Original, $Sid, $Allow); if ($Allow) { return $Original + '|Grant' }; return $Original + '|Revoke' } }
    $record = Join-Path $temporary 'fixture.json'
    $alreadyDenied = New-Fixture
    $unusedRecord = Join-Path $temporary 'already-denied.json'
    & $module { param($File, $Record) Invoke-JobsPermissionChange $File 'fixture-sid' Revoke $Record } $alreadyDenied $unusedRecord
    Assert ($alreadyDenied.Applies -eq 0 -and -not [IO.File]::Exists($unusedRecord)) 'already denied file stays untouched without creating a record'
    $file = New-Fixture
    & $module { param($File, $Record) Invoke-JobsPermissionChange $File 'fixture-sid' Grant $Record } $file $record
    Assert ($file.Sddl -ceq 'base|Grant' -and $file.Applies -eq 1) 'grant adds only our allowed state'
    & $module { param($File, $Record) Invoke-JobsPermissionChange $File 'fixture-sid' Grant $Record } $file $record
    Assert ($file.Applies -eq 1) 'repeated grant does not rewrite'
    $file.Hash = 'edited-content'
    & $module { param($File, $Record) Invoke-JobsPermissionChange $File 'fixture-sid' Revoke $Record } $file $record
    Assert ($file.Sddl -ceq 'base|Revoke') 'normal same-file content edit does not prevent revoke'
    & $module { param($File, $Record) Invoke-JobsPermissionChange $File 'fixture-sid' Grant $Record } $file $record
    Assert ($file.Sddl -ceq 'base|Grant') 'grant after revoke removes only our deny and restores original base'
    $old = $file.Sddl
    $file.Sddl = 'external-acl'
    Throws { & $module { param($File, $Record) Invoke-JobsPermissionChange $File 'fixture-sid' Revoke $Record } $file $record } 'external DACL edit stops'
    Assert ($file.Sddl -ceq 'external-acl') 'conflict never overwrites external rules'
    $file.Sddl = $old
    $file.Identity = 'replaced-file'
    Throws { & $module { param($File, $Record) Invoke-JobsPermissionChange $File 'fixture-sid' Revoke $Record } $file $record } 'replaced identity rejected'
    $file = New-Fixture
    $failureRecord = Join-Path $temporary 'failure.json'
    $file.ForceDeny = $true
    Throws { & $module { param($File, $Record) Invoke-JobsPermissionChange $File 'fixture-sid' Grant $Record } $file $failureRecord } 'effective group denial fails grant'
    Assert ($file.Sddl -ceq 'base' -and -not [IO.File]::Exists($failureRecord)) 'failed grant precisely restores ACL and prior record absence'
    $file = New-Fixture
    $prepared = Join-Path $temporary 'prepared.json'
    @{ Version = 1; Identity = $file.Identity; Hash = $file.Hash; Path = $file.Path; Sid = 'fixture-sid'; OriginalSddl = 'base'; BeforeSddl = 'base'; ExpectedSddl = 'base|Revoke'; Mode = 'Revoke'; Stage = 'Prepared' } | ConvertTo-Json | Set-Content -LiteralPath $prepared -Encoding UTF8
    $file.Sddl = 'base|Revoke'
    & $module { param($File, $Record) Invoke-JobsPermissionChange $File 'fixture-sid' Grant $Record } $file $prepared
    Assert ($file.Sddl -ceq 'base|Grant') 'interrupted applied Prepared state can switch without stacking ACEs'
    Remove-Module $module
    $module = Import-Module (Join-Path $root 'JobsRunAuthorizer/Scripts/Action.psm1') -PassThru -DisableNameChecking
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $target = Join-Path $temporary '普通文件 & 100%.exe'
        [IO.File]::WriteAllText($target, 'inert fixture, never executed')
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $realRecord = Join-Path $temporary 'real.json'
        $held = $null
        $baseline = ''
        try {
            $held = New-Object Jobs.RunPermissionFile($target)
            $baseline = $held.Capture()
            & $module { param($Path) Assert-JobsPermissionPath $Path } $target | Out-Null
            & $module { param($File, $Sid, $Record) Invoke-JobsPermissionChange $File $Sid Revoke $Record } $held $sid $realRecord
            Assert (-not $held.HasExecute()) 'real native new ExecuteFile open denied after revoke'
            $denied = $held.Capture()
            $raw = New-Object Security.AccessControl.RawSecurityDescriptor($denied)
            Assert ($raw.DiscretionaryAcl[0].AccessMask -eq 32 -and $raw.DiscretionaryAcl[0].SecurityIdentifier.Value -ceq $sid) 'real DACL adds only current SID execute deny at front'
            $held.Dispose(); $held = $null
            [IO.File]::AppendAllText($target, ' ordinary edit')
            $held = New-Object Jobs.RunPermissionFile($target)
            & $module { param($File, $Sid, $Record) Invoke-JobsPermissionChange $File $Sid Grant $Record } $held $sid $realRecord
            Assert ($held.HasExecute()) 'real edited file regains direct execution access without executing'
            $allowed = $held.Capture()
            $baselineRaw = New-Object Security.AccessControl.RawSecurityDescriptor($baseline)
            $allowedRaw = New-Object Security.AccessControl.RawSecurityDescriptor($allowed)
            Assert ($allowedRaw.DiscretionaryAcl.Count -eq $baselineRaw.DiscretionaryAcl.Count + 1) 'real roundtrip leaves original ACE count plus one own allow'
            $held.Apply($allowed, $baseline)
            Assert ($held.Capture() -ceq $baseline) 'real exact original ACL restoration for fixture cleanup'
            Throws { $stream = [IO.File]::Open($target, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::Read); $stream.Dispose() } 'held file excludes concurrent content writes'
        } finally {
            if ($null -ne $held) {
                try { $now = $held.Capture(); if ($baseline -and $now -cne $baseline) { $held.Apply($now, $baseline) } } finally { $held.Dispose() }
            }
        }
        $hardLink = Join-Path $temporary 'hard-link.exe'
        New-Item -ItemType HardLink -Path $hardLink -Target $target | Out-Null
        Throws { $linked = New-Object Jobs.RunPermissionFile($target); $linked.Dispose() } 'hard-link target rejected'
        Throws { & $module { param($Path) Assert-JobsPermissionPath $Path } $temporary } 'directory rejected'
        Write-Host 'Windows temporary NTFS ACL behavior verified; no user file or executable launch.'
    } else { Write-Host 'SKIP: real NTFS ACL/API branch requires Windows; native compile and isolated transaction tests completed.' }
    foreach ($name in @('JobsRunAuthorizer', 'JobsRunAuthorizationRevoker')) {
        $installer = Import-Module (Join-Path $root ($name + '/Scripts/PackageInstaller.psm1')) -PassThru -DisableNameChecking
        $manifest = Get-Content -LiteralPath (Join-Path $root ($name + '/Extension.json')) -Raw -Encoding UTF8 | ConvertFrom-Json
        $plan = @(& $installer { param($Manifest) Get-JobsPackageRegistryPlan $Manifest '/temporary/release' 'powershell.exe' } $manifest)
        Assert ($plan.Count -eq 2 -and $plan[0].Key.Contains('Classes\*\shellex\')) 'single-file native registration only'
    }
    Write-Host ('PASS: RunPermissions (' + $script:count + ' assertions)')
} finally {
    Remove-Module $module -ErrorAction SilentlyContinue
    if ([IO.Directory]::Exists($temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
