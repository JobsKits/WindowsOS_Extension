# Action.psm1 | JobsSourcetreeOpener
# Created by Jobs on 2026年10月26日，星期一.
# 安装检测与目标复核完成后，仅把最近 Git 工作树交给 Sourcetree。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

# 元数据与工作树都拒绝链接，避免打开越过用户所选边界。
function Assert-JobsSourcetreePlainPath {
    param([string]$Path, [bool]$Directory)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ([bool]$item.PSIsContainer -ne $Directory) { throw '路径类型不符。' }
    $current = $item
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '不处理链接、目录联接或重解析路径。' }
        if ($current -is [IO.DirectoryInfo]) { $current = $current.Parent } else { $current = $current.Directory }
    }
    return $item.FullName
}
# 限量读取单行 UTF8 元数据，不把任意目录当成 Git。
function Read-JobsSourcetreeMetadata {
    param([string]$Path)
    [void](Assert-JobsSourcetreePlainPath $Path $false)
    if ((Get-Item -LiteralPath $Path -Force).Length -gt 8192) { throw 'Git 元数据超过支持大小。' }
    $text = (New-Object Text.UTF8Encoding($false, $true)).GetString([IO.File]::ReadAllBytes($Path)).TrimEnd("`r", "`n")
    if (-not $text -or $text -match '[\r\n\x00]') { throw 'Git 元数据格式无效。' }
    return $text
}
# 元数据只接受确定的本地绝对路径或相对路径，拒绝 UNC 和驱动器相对写法。
function Resolve-JobsSourcetreeMetadataPath {
    param([string]$Base, [string]$Value)
    if (-not $Value -or $Value -match '^[\\/]{2}' -or $Value -match '^[A-Za-z]:($|[^\\/])') { throw '不支持网络或驱动器相对 Git 元数据路径。' }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and $Value -match '^[\\/]') { throw 'Git 元数据必须使用明确驱动器。' }
    if (-not [IO.Path]::IsPathRooted($Value)) { $Value = Join-Path $Base $Value }
    return [IO.Path]::GetFullPath($Value)
}
# 支持普通 gitdir、子模块 gitfile 和 worktree commondir。
function Test-JobsSourcetreeMetadata {
    param([string]$Directory)
    try {
        [void](Assert-JobsSourcetreePlainPath $Directory $true)
        $head = Read-JobsSourcetreeMetadata (Join-Path $Directory 'HEAD')
        if ($head -notmatch '^(ref: refs/[^\s~^:?*\[\\]+|[0-9a-fA-F]{40}|[0-9a-fA-F]{64})$' -or $head -match '\.\.|@\{' -or $head.EndsWith('/') -or $head.EndsWith('.')) { return $false }
        $common = $Directory
        $commonFile = Join-Path $Directory 'commondir'
        if (Test-Path -LiteralPath $commonFile) {
            $common = Read-JobsSourcetreeMetadata $commonFile
            $common = Resolve-JobsSourcetreeMetadataPath $Directory $common
        }
        [void](Assert-JobsSourcetreePlainPath $common $true)
        [void](Assert-JobsSourcetreePlainPath (Join-Path $common 'objects') $true)
        $references = Join-Path $common 'refs'
        if (-not (Test-Path -LiteralPath $references -PathType Container)) { $references = Join-Path $common 'reftable' }
        [void](Assert-JobsSourcetreePlainPath $references $true)
        [void](Assert-JobsSourcetreePlainPath (Join-Path $common 'config') $false)
        return $true
    } catch { return $false }
}
# 最近内层 .git 一旦出现必须有效；无效时禁止继续向上误操作父仓。
function Get-JobsSourcetreeBoundary {
    param([string]$Target)
    if (-not [IO.Path]::IsPathRooted($Target) -or $Target -match '^[\\/]{2}') { throw '目标必须为本地绝对目录，不支持网络共享。' }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and $Target -notmatch '^[A-Za-z]:[\\/]') { throw '目标必须包含明确的本地驱动器。' }
    $directory = Assert-JobsSourcetreePlainPath $Target $true
    $scan = New-Object IO.DirectoryInfo $directory
    while ($null -ne $scan) {
        if ($scan.Name -ieq '.git' -or (Test-JobsSourcetreeMetadata $scan.FullName)) { throw 'Git 元数据内部和裸仓不提供打开。' }
        $marker = Join-Path $scan.FullName '.git'
        if (Test-Path -LiteralPath $marker) {
            $item = Get-Item -LiteralPath $marker -Force
            if ($item.PSIsContainer) { $metadata = Assert-JobsSourcetreePlainPath $marker $true }
            else {
                $text = Read-JobsSourcetreeMetadata $marker
                if (-not $text.StartsWith('gitdir: ', [StringComparison]::Ordinal) -or $text.Length -le 8) { throw '内层 .git 文件无效；不打开父仓。' }
                $metadata = $text.Substring(8)
                $metadata = Resolve-JobsSourcetreeMetadataPath $scan.FullName $metadata
            }
            if (-not (Test-JobsSourcetreeMetadata $metadata)) { throw '最近工作树的 Git 元数据无效；不打开父仓。' }
            return [pscustomobject]@{ Root = $scan.FullName; Metadata = $metadata }
        }
        $scan = $scan.Parent
    }
    throw '目标不在有效 Git 工作树内。'
}

function Get-JobsSourcetreeCandidates {
    $candidates = @()
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        foreach ($key in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\SourceTree.exe', 'HKLM:\Software\Microsoft\Windows\CurrentVersion\App Paths\SourceTree.exe')) {
            if (Test-Path -LiteralPath $key) {
                $value = (Get-Item -LiteralPath $key).GetValue('')
                if ($value -is [string]) { $candidates += [Environment]::ExpandEnvironmentVariables($value.Trim('"')) }
            }
        }
    }
    foreach ($base in @([Environment]::GetEnvironmentVariable('LOCALAPPDATA'), [Environment]::GetFolderPath('ProgramFiles'), [Environment]::GetFolderPath('ProgramFilesX86'))) {
        if ([string]::IsNullOrWhiteSpace($base)) { continue }
        foreach ($relative in @('SourceTree/SourceTree.exe', 'Atlassian/SourceTree/SourceTree.exe')) { $candidates += Join-Path $base $relative }
    }
    return $candidates
}

function Get-JobsSourcetree {
    foreach ($candidate in @(Get-JobsSourcetreeCandidates)) {
        if ([IO.Path]::IsPathRooted($candidate) -and [IO.Path]::GetFileName($candidate) -ieq 'SourceTree.exe' -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
            $item = Get-Item -LiteralPath $candidate -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { return $item.FullName }
        }
    }
    return $null
}

function Start-JobsSourcetree {
    param([string]$Executable, [string]$Directory)
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $Executable
    $start.Arguments = 'log -f ' + (Quote-JobsArgument $Directory)
    $start.WorkingDirectory = $Directory
    $start.UseShellExecute = $false
    [void][Diagnostics.Process]::Start($start)
}

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)
    $path = Resolve-JobsTarget -Target $Target
    $repository = Get-JobsSourcetreeBoundary -Target $path
    $executable = Get-JobsSourcetree
    if (-not $executable) { throw 'Sourcetree 已卸载或安装路径不可用，请重新打开右键菜单。' }
    Start-JobsSourcetree -Executable $executable -Directory $repository.Root
}

Export-ModuleMember -Function Invoke-JobsFeature
