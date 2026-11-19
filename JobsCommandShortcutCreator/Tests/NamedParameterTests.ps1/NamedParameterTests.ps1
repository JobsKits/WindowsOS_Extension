# NamedParameterTests.ps1 | JobsCommandShortcutCreator
# Created by Jobs on 2026年11月14日，星期六.
# 仅比较临时源脚本和所生成入口；不显示界面、不注册菜单、不读写管理偏好。

# 源包装与已发布 flat 布局共用路径，兼容旧收据且不跟随包装目录链接。
function Resolve-JobsScriptLayoutPath {
    param([Parameter(Mandatory=$true)][string]$Path)
    if ([IO.Path]::GetExtension($Path) -notin @('.ps1','.cmd','.vbs')) { return $Path }
    if (Test-Path -LiteralPath $Path -PathType Container) {
        $directory = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw ('脚本包装不能是链接：' + $Path) }
        return Join-Path $Path $directory.Name
    }
    return $Path
}
# 仅新源码包装压平到原发布名称；原有 SDK 资源包与 README 布局保持原意。
function Convert-JobsReleaseLayoutRelativePath {
    param([string]$Package, [string]$Relative)
    $parts = @($Relative -split '[\\/]')
    if ($parts.Count -lt 2) { return $Relative }
    $last = $parts[$parts.Count - 1]
    $parent = $parts[$parts.Count - 2]
    if ($last -ceq 'README.md' -and [IO.Path]::GetExtension($parent) -in @('.ps1','.cmd','.vbs')) {
        $sibling = Join-Path (Join-Path $Package (($parts[0..($parts.Count-2)]) -join '/')) $parent
        if ((Test-Path -LiteralPath $sibling -PathType Leaf) -and ([IO.File]::ReadAllText($sibling) -match '(?m)^(?:#|rem|\x27) JOBS_SOURCE_LAYOUT_ROOT_V1')) { return $null }
    }
    if ($last -ceq $parent -and [IO.Path]::GetExtension($last) -in @('.ps1','.cmd','.vbs')) {
        $source = Join-Path $Package $Relative
        if ((Test-Path -LiteralPath $source -PathType Leaf) -and ([IO.File]::ReadAllText($source) -match '(?m)^(?:#|rem|\x27) JOBS_SOURCE_LAYOUT_ROOT_V1')) {
            return (($parts[0..($parts.Count-2)]) -join '/')
        }
    }
    return $Relative
}
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Resolve-JobsScriptLayoutPath (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Scripts/CommandShortcut.ps1'))
$script:Assertions = 0
function Assert-NamedShortcut {
    param([bool]$Value, [string]$Reason)
    $script:Assertions++
    if (-not $Value) { throw $Reason }
}
function Invoke-NamedShortcutFixture {
    param([string]$Path, [string[]]$Arguments)
    # 在子解释器内绑定参数，避开 5.1 的原生 -File 丢空串和布尔开关限制。
    $invocation = @('&', ("'" + $Path.Replace("'", "''") + "'"))
    foreach ($argument in $Arguments) {
        if ($argument -match '^-(?<Name>[A-Za-z][A-Za-z0-9]*)(?::(?<Boolean>True|False))?$') {
            $token = '-' + $Matches.Name
            if ($Matches.ContainsKey('Boolean')) { $token += ':$' + $Matches.Boolean.ToLowerInvariant() }
            $invocation += $token
        } else {
            $invocation += "'" + $argument.Replace("'", "''") + "'"
        }
    }
    $driver = @'
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$OutputEncoding = New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding = $OutputEncoding
$global:LASTEXITCODE = 0
try {
    __INVOCATION__
    $succeeded = $?
    if (-not $succeeded -and $LASTEXITCODE -eq 0) { exit 1 }
    exit $LASTEXITCODE
} catch {
    [Console]::Error.WriteLine(($_ | Out-String))
    exit 1
}
'@
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($driver.Replace('__INVOCATION__', ($invocation -join ' '))))
    $process = New-Object Diagnostics.Process
    $process.StartInfo.FileName = (Get-Process -Id $PID).Path
    $process.StartInfo.Arguments = '-NoLogo -NoProfile -NonInteractive -InputFormat Text -OutputFormat Text -EncodedCommand ' + $encoded
    $process.StartInfo.WorkingDirectory = Split-Path -Parent $Path
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.CreateNoWindow = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.StandardOutputEncoding = New-Object Text.UTF8Encoding($false)
    $process.StartInfo.StandardErrorEncoding = New-Object Text.UTF8Encoding($false)
    $started = $false
    try {
        [void]$process.Start()
        $started = $true
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(30000)) { throw 'PowerShell parameter fixture timed out.' }
        if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr), 3000)) { throw 'PowerShell parameter fixture output did not close.' }
        $output = $stdout.GetAwaiter().GetResult().TrimEnd([char[]]"`r`n")
        $errorOutput = $stderr.GetAwaiter().GetResult().TrimEnd([char[]]"`r`n")
        return [pscustomobject]@{ Code = $process.ExitCode; StdOut = $output; StdErr = $errorOutput }
    } finally {
        if ($started -and -not $process.HasExited) { $process.Kill(); [void]$process.WaitForExit(3000) }
        $process.Dispose()
    }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ('JobsNamedShortcut-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
$cases = @(
    @{ Id = 'named-switch'; Body = 'param([string]$Name,[switch]$Flag,[string]$Empty); [pscustomobject]@{Name=$Name;Flag=[bool]$Flag;Empty=$Empty;Args=@($args)}|ConvertTo-Json -Compress'; Arguments = @('-Name','中文 value','-Flag','-Empty','') },
    @{ Id = 'switch-false'; Body = 'param([string]$Name,[switch]$Flag); [pscustomobject]@{Name=$Name;Flag=[bool]$Flag}|ConvertTo-Json -Compress'; Arguments = @('-Name','hello','-Flag:False') },
    @{ Id = 'position'; Body = 'param([string]$Name,[string]$Second); [pscustomobject]@{Name=$Name;Second=$Second;Args=@($args)}|ConvertTo-Json -Compress'; Arguments = @('first','second','extra') },
    @{ Id = 'literal-boundaries'; Body = 'ConvertTo-Json -InputObject @($args) -Compress'; Arguments = @('空格 参数','','单''引号','"double"','trailing\','$();&!%','|') },
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
        Assert-NamedShortcut ($direct.Code -eq $expectedCode) ('Direct source baseline works: ' + $case.Id + '; code=' + $direct.Code + '; stdout=' + $direct.StdOut + '; stderr=' + $direct.StdErr)
        Assert-NamedShortcut ($direct.StdErr -ceq '') ('Direct source stderr is empty: ' + $case.Id + '; stderr=' + $direct.StdErr)
        if ($case.Id -eq 'named-switch') {
            $baseline = $direct.StdOut | ConvertFrom-Json
            Assert-NamedShortcut ($baseline.Name -ceq '中文 value' -and $baseline.Flag -eq $true -and $baseline.Empty -ceq '' -and @($baseline.Args).Count -eq 0) 'The direct baseline binds the named switch and its explicit empty value.'
        } elseif ($case.Id -eq 'switch-false') {
            Assert-NamedShortcut (($direct.StdOut | ConvertFrom-Json).Flag -eq $false) 'The direct baseline retains an explicitly false switch.'
        } elseif ($case.Id -eq 'empty-mandatory') {
            Assert-NamedShortcut (($direct.StdOut | ConvertFrom-Json).Name -ceq '') 'The direct baseline supplies an empty mandatory argument.'
        } elseif ($case.Id -eq 'literal-boundaries') {
            $baseline = $direct.StdOut | ConvertFrom-Json
            $baseline = @($baseline)
            Assert-NamedShortcut ($baseline.Count -eq $case.Arguments.Count) 'The direct baseline retains every literal argument, including an empty string.'
            for ($index = 0; $index -lt $case.Arguments.Count; $index++) {
                Assert-NamedShortcut ($baseline[$index] -ceq $case.Arguments[$index]) ('The direct baseline retains literal argument ' + $index + '.')
            }
        }
        if ($case.ContainsKey('Reject') -and $case.Reject) {
            Assert-NamedShortcut ($proxy.Code -ne 0) 'A conflicting plain-script common parameter is rejected explicitly.'
            Assert-NamedShortcut ($proxy.StdErr -match 'reserved launcher parameter') 'The conflict is diagnosed on stderr instead of silently becoming a switch.'
        } else {
            Assert-NamedShortcut ($proxy.Code -eq $direct.Code) ('Source exit code is retained: ' + $case.Id)
            Assert-NamedShortcut ($proxy.StdErr -ceq '') ('Launcher stderr is empty: ' + $case.Id + '; stderr=' + $proxy.StdErr)
            Assert-NamedShortcut ($proxy.StdOut -ceq $direct.StdOut) ('Named values and binding match the source: ' + $case.Id + '; direct=' + $direct.StdOut + '; launcher=' + $proxy.StdOut)
        }
        Assert-NamedShortcut ((Get-FileHash -LiteralPath $source).Hash -ceq $original) ('Source bytes remain unchanged: ' + $case.Id)
    }
    Write-Output ('PASS: ' + $script:Assertions + ' named parameter launcher assertions')
} finally {
    if ([IO.Directory]::Exists($root)) { [IO.Directory]::Delete($root, $true) }
}
