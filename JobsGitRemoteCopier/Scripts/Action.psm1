# Action.psm1
# JobsGitRemoteCopier
# Created by Jobs on 2026年10月18日，星期日.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

function Get-JobsGitRemote {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Directory)

    $targetDirectory = Get-JobsDirectory -Target $Directory
    $git = Find-JobsExecutable -Name 'git'
    if (-not $git) {
        throw '未找到 Git，请先安装 Git for Windows。'
    }
    $inside = Invoke-JobsProcess -FilePath $git -Arguments @('-C', $targetDirectory, 'rev-parse', '--is-inside-work-tree')
    if ($inside.ExitCode -ne 0 -or $inside.StdOut.Trim() -ne 'true') {
        throw '目标不在 Git 工作树内。'
    }
    $remoteResult = Invoke-JobsProcess -FilePath $git -Arguments @('-C', $targetDirectory, 'remote')
    if ($remoteResult.ExitCode -ne 0) {
        throw '无法读取 Git 远端列表。'
    }
    $remotes = @($remoteResult.StdOut -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($remotes.Count -eq 0) {
        throw '当前 Git 仓库尚未配置远端。'
    }

    $selectedRemote = $null
    $branch = Invoke-JobsProcess -FilePath $git -Arguments @('-C', $targetDirectory, 'symbolic-ref', '--quiet', '--short', 'HEAD')
    if ($branch.ExitCode -eq 0) {
        $branchName = $branch.StdOut.TrimEnd([char[]]@([char]13, [char]10))
        $tracking = Invoke-JobsProcess -FilePath $git -Arguments @('-C', $targetDirectory, 'config', '--get', ('branch.' + $branchName + '.remote'))
        if ($tracking.ExitCode -eq 0) {
            $trackingRemote = $tracking.StdOut.TrimEnd([char[]]@([char]13, [char]10))
            if ($remotes -ccontains $trackingRemote) {
                $selectedRemote = $trackingRemote
            }
        }
    }
    if (-not $selectedRemote -and $remotes -ccontains 'origin') {
        $selectedRemote = 'origin'
    }
    if (-not $selectedRemote -and $remotes.Count -eq 1) {
        $selectedRemote = $remotes[0]
    }
    if (-not $selectedRemote) {
        throw '存在多个 Git 远端，且当前分支和 origin 均未指定可用远端，请先配置。'
    }
    # remote get-url 会应用 insteadOf；复制功能必须读取配置中的原始地址。
    $remote = Invoke-JobsProcess -FilePath $git -Arguments @('-C', $targetDirectory, 'config', '--null', '--get-all', ('remote.' + $selectedRemote + '.url'))
    if ($remote.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($remote.StdOut)) {
        throw '无法读取选定 Git 远端地址。'
    }
    $configuredUrls = $remote.StdOut.Split([char]0)
    if ([string]::IsNullOrWhiteSpace($configuredUrls[0])) {
        throw '选定 Git 远端尚未配置有效地址。'
    }
    return $configuredUrls[0]
}

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)

    $directory = Get-JobsDirectory -Target $Target
    Set-Clipboard -Value (Get-JobsGitRemote -Directory $directory)
}

Export-ModuleMember -Function Invoke-JobsFeature
