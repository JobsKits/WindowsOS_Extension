# Action.psm1
# JobsGitRemoteOpener
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

function ConvertTo-JobsWebUrl {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Remote)

    $value = $Remote.Trim()
    if ([string]::IsNullOrWhiteSpace($value) -or $value -match '[\x00-\x20\x7f\\]') {
        throw '该 Git 远端不能转换为仓库网页地址。'
    }
    $scheme = 'https'
    $hostName = ''
    $repositoryPath = ''
    $portSuffix = ''
    if ($value -match '^[A-Za-z][A-Za-z0-9+.-]*://') {
        $uri = $null
        if (-not [Uri]::TryCreate($value, [UriKind]::Absolute, [ref]$uri)) {
            throw 'Git 远端 URL 格式不正确。'
        }
        if ($uri.Scheme -notin @('https', 'http', 'ssh', 'git')) {
            throw '仅支持 HTTP、HTTPS、SSH 与 Git 协议的仓库网页地址。'
        }
        if ([string]::IsNullOrWhiteSpace($uri.Host)) {
            throw 'Git 远端缺少服务器名称。'
        }
        $hostName = $uri.Host
        if ($hostName.Contains(':') -and -not $hostName.StartsWith('[')) {
            $hostName = '[' + $hostName + ']'
        }
        $repositoryPath = $uri.AbsolutePath
        if ($uri.Scheme -in @('http', 'https')) {
            $scheme = $uri.Scheme
            # 保留用户显式指定的 HTTP 端口，SSH/Git 传输端口不适用于浏览器。
            $authority = [regex]::Match($value, '^[^:]+://(?<authority>[^/?#]+)').Groups['authority'].Value
            $authority = $authority.Substring($authority.LastIndexOf('@') + 1)
            if ($authority -match ':(?<port>[0-9]+)$') {
                $portSuffix = ':' + $Matches['port']
            }
        }
    }
    elseif ($value -match '^[A-Za-z]:' -or $value -match '^(?i:https?|ssh|git|file|ext|local|ftp|ftps|sftp|mailto|data|javascript|powershell):') {
        throw '本地路径和非仓库网络协议不能作为网页打开。'
    }
    elseif ($value -match '^(?:[^@/:\s]+@)?(?<host>\[[^\]]+\]|[^@/:\s]+):(?<path>.+)$') {
        $hostName = $Matches['host']
        $repositoryPath = $Matches['path']
        if ($repositoryPath.StartsWith(':')) {
            throw '不支持 Git 远端的外部命令协议。'
        }
    }
    else {
        throw '该 Git 远端不是可打开的网络仓库地址。'
    }

    $repositoryPath = ($repositoryPath -split '[?#]', 2)[0].TrimEnd('/')
    if ($repositoryPath.EndsWith('.git', [StringComparison]::OrdinalIgnoreCase)) {
        $repositoryPath = $repositoryPath.Substring(0, $repositoryPath.Length - 4)
    }
    $repositoryPath = $repositoryPath.TrimStart('/')
    if ([string]::IsNullOrEmpty($repositoryPath)) {
        throw 'Git 远端缺少仓库路径。'
    }
    if ($hostName -in @('ssh.dev.azure.com', 'vs-ssh.visualstudio.com') -and $repositoryPath -match '^v3/(?<organization>[^/]+)/(?<project>[^/]+)/(?<repository>.+)$') {
        $hostName = 'dev.azure.com'
        $repositoryPath = $Matches['organization'] + '/' + $Matches['project'] + '/_git/' + $Matches['repository']
        $portSuffix = ''
    }

    $webUri = $null
    $webUrl = $scheme + '://' + $hostName + $portSuffix + '/' + $repositoryPath
    if (-not [Uri]::TryCreate($webUrl, [UriKind]::Absolute, [ref]$webUri) -or $webUri.HostNameType -eq [UriHostNameType]::Unknown -or $webUri.UserInfo) {
        throw '转换后的仓库网页地址不合法。'
    }
    # 浏览器地址不保留 userinfo、查询串或片段，避免把凭据带到浏览器及历史记录。
    return $webUrl
}

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)

    $directory = Get-JobsDirectory -Target $Target
    $url = ConvertTo-JobsWebUrl -Remote (Get-JobsGitRemote -Directory $directory)
    Start-Process -FilePath $url
}

Export-ModuleMember -Function Invoke-JobsFeature
