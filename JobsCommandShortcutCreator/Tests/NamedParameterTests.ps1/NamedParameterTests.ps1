# NamedParameterTests.ps1 | JobsCommandShortcutCreator
# Created by Jobs on 2026年11月14日，星期六.
# 仅比较临时源脚本和所生成入口；不显示界面、不注册菜单、不读写管理偏好。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Scripts/CommandShortcut.ps1')
$script:Assertions = 0
function Assert-NamedShortcut {
    param([bool]$Value, [string]$Reason)
    $script:Assertions++
    if (-not $Value) { throw $Reason }
}
function Invoke-NamedShortcutFixture {
    param([string]$Path, [string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    $pwsh = (Get-Process -Id $PID).Path
    $output = @(& $pwsh -NoLogo -NoProfile -NonInteractive -File $Path @Arguments 2>&1)
    $code = $LASTEXITCODE
    return [pscustomobject]@{ Code = $code; Output = ($output -join "`n") }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ('JobsNamedShortcut-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$cases = @(
    @{ Id = 'named-switch'; Body = 'param([string]$Name,[switch]$Flag,[string]$Empty); [pscustomobject]@{Name=$Name;Flag=[bool]$Flag;Empty=$Empty;Args=@($args)}|ConvertTo-Json -Compress'; Arguments = @('-Name','中文 value','-Flag','-Empty','') },
    @{ Id = 'switch-false'; Body = 'param([string]$Name,[switch]$Flag); [pscustomobject]@{Name=$Name;Flag=[bool]$Flag}|ConvertTo-Json -Compress'; Arguments = @('-Name','hello','-Flag:False') },
    @{ Id = 'position'; Body = 'param([string]$Name,[string]$Second); [pscustomobject]@{Name=$Name;Second=$Second;Args=@($args)}|ConvertTo-Json -Compress'; Arguments = @('first','second','extra') },
    @{ Id = 'alias'; Body = 'param([Alias("n")][string]$Name); [pscustomobject]@{Name=$Name;Args=@($args)}|ConvertTo-Json -Compress'; Arguments = @('-n','hello') },
    @{ Id = 'empty-mandatory'; Body = 'param([Parameter(Mandatory=$true)][AllowEmptyString()][string]$Name); [pscustomobject]@{Name=$Name}|ConvertTo-Json -Compress'; Arguments = @('-Name','') },
    @{ Id = 'remaining'; Body = 'param([string]$Name,[Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest); [pscustomobject]@{Name=$Name;Rest=@($Rest)}|ConvertTo-Json -Compress'; Arguments = @('-Name','main','one','two') },
    @{ Id = 'named-rest'; Body = 'param([string]$Name,[Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest); [pscustomobject]@{Name=$Name;Rest=@($Rest)}|ConvertTo-Json -Compress'; Arguments = @(); NamedRemaining = $true },
    @{ Id = 'exit'; Body = 'param([string]$Name); [pscustomobject]@{Name=$Name}|ConvertTo-Json -Compress; exit 23'; Arguments = @('-Name','exit-value') },
    @{ Id = 'reserved-common'; Body = 'param([string]$Verbose); [pscustomobject]@{Value=$Verbose}|ConvertTo-Json -Compress'; Arguments = @('-Verbose','word'); Reject = $true }
)
try {
    foreach ($case in $cases) {
        $directory = Join-Path $root ($case.Id + '.ps1')
        [void][IO.Directory]::CreateDirectory($directory)
        $source = Join-Path $directory ($case.Id + '.ps1')
        [IO.File]::WriteAllText($source, $case.Body, (New-Object Text.UTF8Encoding($true)))
        $original = (Get-FileHash -LiteralPath $source).Hash
        $launcher = New-JobsCommandShortcut $directory ($case.Id + '-launcher.ps1')
        if ($case.ContainsKey('NamedRemaining') -and $case.NamedRemaining) {
            $driver = Join-Path $root 'named-rest-driver.ps1'
            [IO.File]::WriteAllText($driver, 'param([string]$Target); & $Target -Name main -Rest @(''one'',''two'')', (New-Object Text.UTF8Encoding($true)))
            $direct = Invoke-NamedShortcutFixture $driver @('-Target', $source)
            $proxy = Invoke-NamedShortcutFixture $driver @('-Target', $launcher)
        } else {
            $direct = Invoke-NamedShortcutFixture $source $case.Arguments
            $proxy = Invoke-NamedShortcutFixture $launcher $case.Arguments
        }
        $expectedCode = if ($case.Id -eq 'exit') { 23 } else { 0 }
        Assert-NamedShortcut ($direct.Code -eq $expectedCode) ('Direct source baseline works: ' + $case.Id)
        if ($case.ContainsKey('Reject') -and $case.Reject) {
            Assert-NamedShortcut ($proxy.Code -ne 0) 'A conflicting plain-script common parameter is rejected explicitly.'
            Assert-NamedShortcut ($proxy.Output -match 'reserved launcher parameter') 'The conflict is diagnosed instead of silently becoming a switch.'
        } else {
            Assert-NamedShortcut ($proxy.Code -eq $direct.Code) ('Source exit code is retained: ' + $case.Id)
            Assert-NamedShortcut ($proxy.Output -ceq $direct.Output) ('Named values and binding match the source: ' + $case.Id + '; direct=' + $direct.Output + '; launcher=' + $proxy.Output)
        }
        Assert-NamedShortcut ((Get-FileHash -LiteralPath $source).Hash -ceq $original) ('Source bytes remain unchanged: ' + $case.Id)
    }
    Write-Output ('PASS: ' + $script:Assertions + ' named parameter launcher assertions')
} finally {
    if ([IO.Directory]::Exists($root)) { [IO.Directory]::Delete($root, $true) }
}
