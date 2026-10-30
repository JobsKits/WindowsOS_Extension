# SourcetreeOpener.Tests.ps1 | JobsSourcetreeOpener
# Created by Jobs on 2026年10月26日，星期一.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:assertions = 0
function Assert-Sourcetree {
    param([bool]$Condition, [string]$Message)
    ++$script:assertions
    if (-not $Condition) { throw $Message }
}
function New-FixtureRepository {
    param([string]$Directory)
    foreach ($name in @('.git/objects', '.git/refs')) { [void][IO.Directory]::CreateDirectory((Join-Path $Directory $name)) }
    [IO.File]::WriteAllText((Join-Path $Directory '.git/HEAD'), "ref: refs/heads/main`n")
    [IO.File]::WriteAllText((Join-Path $Directory '.git/config'), '[core]')
}
$temporaryBase = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $temporaryBase = '/private/tmp' }
$temporary = Join-Path $temporaryBase ('Sourcetree 中文 & [safe] ' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temporary)
$module = Import-Module (Join-Path $PSScriptRoot '../JobsSourcetreeOpener/Scripts/Action.psm1') -PassThru -DisableNameChecking
try {
    New-FixtureRepository $temporary
    $child = Join-Path $temporary 'child'
    [void][IO.Directory]::CreateDirectory($child)
    $resolved = & $module { param($Target) Get-JobsSourcetreeBoundary $Target } $child
    Assert-Sourcetree ($resolved.Root -eq $temporary) '普通子目录打开最近 Git 根目录'
    New-FixtureRepository $child
    $resolved = & $module { param($Target) Get-JobsSourcetreeBoundary $Target } $child
    Assert-Sourcetree ($resolved.Root -eq $child) '内层 Git 不被父仓覆盖'
    $leaf = Join-Path $child 'invalid'
    [void][IO.Directory]::CreateDirectory($leaf)
    [IO.File]::WriteAllText((Join-Path $leaf '.git'), 'malformed')
    $rejected = $false
    try { & $module { param($Target) Get-JobsSourcetreeBoundary $Target } $leaf } catch { $rejected = $true }
    Assert-Sourcetree $rejected '畸形内层 Git 不越过边界'
    $missing = Join-Path $temporary 'missing/SourceTree.exe'
    & $module {
        param($Executable)
        $script:Candidate = $Executable
        function script:Get-JobsSourcetreeCandidates { return @($script:Candidate) }
        function script:Start-JobsSourcetree { param($Executable, $Directory) $script:Launch = @($Executable, $Directory) }
        $script:Launch = $null
    } $missing
    $found = & $module { Get-JobsSourcetree }
    Assert-Sourcetree ($null -eq $found) '不存在的安装路径不可用'
    $rejected = $false
    try { & $module { param($Target) Invoke-JobsFeature $Target } $child } catch { $rejected = $true }
    Assert-Sourcetree $rejected '菜单打开后应用卸载时拒绝启动'
    $launch = & $module { $script:Launch }
    Assert-Sourcetree ($null -eq $launch) '缺应用不启动其它进程'
    $application = Join-Path $temporary 'installed/SourceTree.exe'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $application))
    [IO.File]::WriteAllText($application, 'isolated executable placeholder; never executed')
    & $module { param($Executable) $script:Candidate = $Executable } $application
    & $module { param($Target) Invoke-JobsFeature $Target } $child
    $launch = & $module { $script:Launch }
    Assert-Sourcetree ($launch.Count -eq 2 -and $launch[0] -eq $application -and $launch[1] -eq $child) '已安装时按原始参数打开内层仓库'
    $native = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../JobsSourcetreeOpener/Scripts/ContextMenu.cpp') -Raw -Encoding UTF8
    Assert-Sourcetree (-not $native.Contains('InsertMenuW(') -and -not $native.Contains('CreateProcessW(')) '退役 COM 不插入菜单或派发旧命令'
    $installer = Import-Module (Join-Path $PSScriptRoot '../JobsSourcetreeOpener/Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    $rejected = $false
    try { & $installer { Invoke-JobsPackageChange -PackagePath 'unused' -Mode Install } } catch { $rejected = $_.Exception.Message.Contains('已移除') }
    Assert-Sourcetree $rejected '旧独立包不能重新安装已移除的入口'
    Remove-Module $installer

    Write-Host ('PASS: SourcetreeOpener.Tests.ps1 (' + $script:assertions + ' assertions)')
} finally {
    Remove-Module $module
    Remove-Item -LiteralPath $temporary -Recurse -Force
}
