# HarmonySimulatorRepairer.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月24日，星期六.
# Mock official CLI state; no devices, downloads, registry or real processes are modified.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$module = Import-Module (Join-Path $root 'JobsHarmonySimulatorRepairer/Scripts/Action.psm1') -PassThru -DisableNameChecking
$script:count = 0
function Assert { param([bool]$Value, [string]$Why); if (-not $Value) { throw ('FAIL: ' + $Why) }; $script:count++ }
function Throws { param([scriptblock]$Body, [string]$Why); $caught = $false; try { & $Body | Out-Null } catch { $caught = $true }; Assert $caught $Why }
function Reset-Fixture {
    & $module {
        $script:Calls = @(); $script:Running = $false; $script:Fail = ''; $script:Unknown = $false; $script:Race = $false; $script:Cancel = $false; $script:NoTransition = $false; $script:FileIdentity = 'directory-file-id|configuration-file-id'
        function script:Get-JobsHarmonyRepairFileIdentity { param($Directory); return $script:FileIdentity }
        function script:Read-JobsHarmonyInput { param($Prompt); if ($script:Cancel) { return 'no' }; if ($Prompt -match 'YES') { return 'YES' }; return '' }
        function script:Start-Sleep { param($Milliseconds) }
        function script:Invoke-JobsProcess {
            param($FilePath, $Arguments, $TimeoutSeconds)
            $output = ''
            switch ($Arguments[0]) {
                '-help' { $output = '-list -details -imageList -start -stop -bootMode' }
                '-imageList' { $output = '[]' }
                '-list' {
                    $running = $script:Running
                    if ($script:Unknown) { $running = 'unknown' }
                    $name = 'Jobs phone'; if ($script:Race) { $name = 'Changed' }
                    $output = ConvertTo-Json -InputObject @([pscustomobject]@{ name = $name; instancePath = [IO.Path]::GetTempPath(); deviceType = 'phone'; os = @{ osVersion = 'HarmonyOS 6.1.0(24)' }; isRunning = $running }) -Depth 8 -Compress
                }
            }
            return [pscustomobject]@{ ExitCode = 0; StdOut = $output; StdErr = '' }
        }
        function script:Invoke-JobsHarmonyInteractive {
            param($Emulator, $Arguments)
            $script:Calls += ,@($Arguments)
            if ($script:Fail -ceq $Arguments[0]) { throw 'fixture failed' }
            if (-not $script:NoTransition) { $script:Running = $Arguments[0] -ceq '-start' }
        }
    }
}
Reset-Fixture
try {
    & $module { Assert-JobsHarmonyCapabilities 'Emulator.exe' }
    Assert (@(& $module { Get-JobsHarmonyInstances 'Emulator.exe' }).Count -eq 1) 'official JSON array parses'
    $identity = & $module { Get-JobsHarmonyRepairIdentity (@(Get-JobsHarmonyInstances 'Emulator.exe')[0]) }
    Assert (-not $identity.Running -and $identity.Name -ceq 'Jobs phone') 'unique stopped identity'
    foreach ($running in @('true', 'false')) {
        $value = & $module { param($Text) $record = @(Get-JobsHarmonyInstances 'Emulator.exe')[0]; $record.isRunning = $Text; Get-JobsHarmonyRepairIdentity $record } $running
        Assert ($value.Running -eq ($running -ceq 'true')) 'official string state accepted'
    }
    foreach ($field in @('name', 'instancePath', 'deviceType', 'isRunning')) {
        Throws { & $module { param($Field) $record = @(Get-JobsHarmonyInstances 'Emulator.exe')[0]; $record.PSObject.Properties.Remove($Field); Get-JobsHarmonyRepairIdentity $record } $field } ('missing identity field stops: ' + $field)
    }
    & $module { $script:Unknown = $true }
    Throws { & $module { Get-JobsHarmonyRepairIdentity (@(Get-JobsHarmonyInstances 'Emulator.exe')[0]) } } 'unknown state rejected'
    Reset-Fixture
    & $module { param($Identity) Invoke-JobsHarmonyRepairOperation 'Emulator.exe' $Identity } $identity
    $calls = & $module { ,$script:Calls }
    Assert ($calls.Count -eq 1 -and ($calls[0] -join '|') -ceq '-start|Jobs phone|-bootMode|coldboot') 'stopped instance uses official coldboot preserving data'
    Reset-Fixture
    & $module { $script:Running = $true }
    $running = & $module { Get-JobsHarmonyRepairIdentity (@(Get-JobsHarmonyInstances 'Emulator.exe')[0]) }
    & $module { param($Identity) Invoke-JobsHarmonyRepairOperation 'Emulator.exe' $Identity } $running
    $calls = & $module { ,$script:Calls }
    Assert ($calls.Count -eq 2 -and ($calls[0] -join '|') -ceq '-stop|Jobs phone' -and $calls[1][0] -ceq '-start') 'running instance stop state then coldboot'
    Reset-Fixture
    & $module { $script:Running = $true; $script:Cancel = $true }
    Throws { & $module { param($Identity) Invoke-JobsHarmonyRepairOperation 'Emulator.exe' $Identity } $running } 'cancel leaves running instance untouched'
    Assert (@(& $module { $script:Calls }).Count -eq 0) 'cancel invokes no CLI mutation'
    Reset-Fixture
    & $module { $script:Running = $true; $script:Fail = '-stop' }
    Throws { & $module { param($Identity) Invoke-JobsHarmonyRepairOperation 'Emulator.exe' $Identity } $running } 'failed stop prevents start'
    Assert (@(& $module { $script:Calls }).Count -eq 1) 'stop failure no retry'
    Reset-Fixture
    & $module { $script:Race = $true }
    Throws { & $module { param($Identity) Invoke-JobsHarmonyRepairOperation 'Emulator.exe' $Identity } $identity } 'identity disappears before write'
    Assert (@(& $module { $script:Calls }).Count -eq 0) 'changed identity no mutation'
    Reset-Fixture
    & $module { $script:FileIdentity = 'same-path-recreated-file-id' }
    Throws { & $module { param($Identity) Invoke-JobsHarmonyRepairOperation 'Emulator.exe' $Identity } $identity } 'same-name same-path replacement rejected by real filesystem identity'
    Assert (@(& $module { $script:Calls }).Count -eq 0) 'recreated instance no mutation'
    Reset-Fixture
    & $module { $script:NoTransition = $true }
    Throws { & $module { param($Identity) Invoke-JobsHarmonyRepairOperation 'Emulator.exe' $Identity } $identity } 'successful start without running readback fails'
    Assert (@(& $module { $script:Calls }).Count -eq 1) 'no automatic start retry'
    $installer = Import-Module (Join-Path $root 'JobsHarmonySimulatorRepairer/Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    $manifest = Get-Content -LiteralPath (Join-Path $root 'JobsHarmonySimulatorRepairer/Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $plan = @(& $installer { param($Manifest) Get-JobsPackageRegistryPlan $Manifest '/temporary/release' 'powershell.exe' } $manifest)
    Assert ($plan.Count -eq 2 -and $plan[0].Key -ceq 'Software\Classes\DesktopBackground\shellex\ContextMenuHandlers\Jobs.WindowsExtension.harmony-simulator-repair') 'desktop only independent registration'
    Write-Host ('PASS: HarmonySimulatorRepairer (' + $script:count + ' assertions)')
} finally { Remove-Module $module -ErrorAction SilentlyContinue }
