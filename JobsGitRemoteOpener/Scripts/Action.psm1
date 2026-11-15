# Action.psm1
# JobsGitRemoteOpener
# Created by Jobs on 2026年10月18日，星期日.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

# 解析工作树；单远端直接使用，多远端只接受用户明确选择。
function Get-JobsGitRemote {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Directory, [switch]$Interactive)

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

    $selectedRemote = $remotes[0]
    if ($remotes.Count -gt 1) {
        if (-not $Interactive) {
            Start-JobsGitRemoteSelector -Directory $targetDirectory
            return $null
        }
        $selectedRemote = Select-JobsGitRemoteName -Git $git -Directory $targetDirectory -Remotes $remotes
        if ($null -eq $selectedRemote) { return $null }
    }
    # 保持既有地址转换语义，读取配置原值，不应用 insteadOf。
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

# 仅多远端启动可见控制台，单远端仍由原隐藏入口直接打开。
function Start-JobsGitRemoteSelector {
    param([string]$Directory)
    $entry = Join-Path $PSScriptRoot 'Invoke.ps1'
    $shell = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell/v1.0/powershell.exe'
    if (-not (Test-Path -LiteralPath $shell -PathType Leaf)) { throw '未找到系统 Windows PowerShell，无法显示远端选择器。' }
    $arguments = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Normal', '-File',
        (Quote-JobsArgument -Value $entry), '-Target', (Quote-JobsArgument -Value $Directory), '-SelectRemote')
    Start-Process -FilePath $shell -ArgumentList ($arguments -join ' ') -WorkingDirectory $Directory -WindowStyle Normal
}
# 用远端名与脱敏网页地址展示候选，取消及无效结果均不打开浏览器。
function Select-JobsGitRemoteName {
    param([string]$Git, [string]$Directory, [string[]]$Remotes)
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { throw '远端选择需要可交互控制台，请重新从右键菜单启动。' }
    $fzf = Find-JobsExecutable -Name 'fzf.exe' -Candidates @('fzf')
    if (-not $fzf) { throw '缺少 fzf；请先安装或修复 fzf（winget install --id junegunn.fzf --exact）后重新打开菜单。' }
    $cancel = '[取消本轮]'
    $entries = @($cancel)
    foreach ($name in $Remotes) {
        if ($name -match '[\x00-\x20\x7f]') { throw 'Git 远端名称包含无法显示的字符。' }
        $configured = Invoke-JobsProcess -FilePath $Git -Arguments @('-C', $Directory, 'config', '--null', '--get-all', ('remote.' + $name + '.url'))
        $label = '[无法转换为网页的地址]'
        if ($configured.ExitCode -eq 0) {
            try { $label = ConvertTo-JobsWebUrl -Remote $configured.StdOut.Split([char]0)[0] } catch { }
        }
        $entries += $name + "`t" + $label
    }
    $savedOptions = [Environment]::GetEnvironmentVariable('FZF_DEFAULT_OPTS')
    $savedFile = [Environment]::GetEnvironmentVariable('FZF_DEFAULT_OPTS_FILE')
    $hadOptions = Test-Path Env:FZF_DEFAULT_OPTS
    $hadFile = Test-Path Env:FZF_DEFAULT_OPTS_FILE
    $savedOutputEncoding = $OutputEncoding
    $savedConsoleEncoding = [Console]::OutputEncoding
    $savedErrorPreference = $ErrorActionPreference
    try {
        $env:FZF_DEFAULT_OPTS = ''
        $env:FZF_DEFAULT_OPTS_FILE = ''
        $health = Invoke-JobsProcess -FilePath $fzf -Arguments @('--version') -TimeoutSeconds 10
        $help = Invoke-JobsProcess -FilePath $fzf -Arguments @('--help') -TimeoutSeconds 10
        if ($health.ExitCode -ne 0 -or $help.ExitCode -ne 0 -or $help.StdOut -notmatch '--bind') { throw 'fzf 版本或所需选项不可用，请修复后重试。' }
        # Windows PowerShell 5.1 默认 ASCII 管道会损坏中文候选。
        $OutputEncoding = New-Object Text.UTF8Encoding($false)
        [Console]::OutputEncoding = $OutputEncoding
        $ErrorActionPreference = 'Continue'
        $result = @($entries | & $fzf --no-sort --reverse --no-multi --height=60% --prompt '打开 Git 远端 > ' --header '↑/↓ 或 Tab 选择，回车确认；← / Esc / Ctrl+C 取消' --bind 'up:up,down:down,tab:down,btab:up,left:abort')
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $savedErrorPreference
        $OutputEncoding = $savedOutputEncoding
        [Console]::OutputEncoding = $savedConsoleEncoding
        if ($hadOptions) { [Environment]::SetEnvironmentVariable('FZF_DEFAULT_OPTS', $savedOptions) }
        else { Remove-Item Env:FZF_DEFAULT_OPTS -ErrorAction SilentlyContinue }
        if ($hadFile) { [Environment]::SetEnvironmentVariable('FZF_DEFAULT_OPTS_FILE', $savedFile) }
        else { Remove-Item Env:FZF_DEFAULT_OPTS_FILE -ErrorAction SilentlyContinue }
    }
    if ($code -in @(1, 130)) { return $null }
    if ($code -ne 0) { throw ('fzf 选择失败，退出码：' + $code) }
    if ($result.Count -eq 0 -or ($result.Count -eq 1 -and ($result[0] -ceq $cancel -or -not $result[0]))) { return $null }
    if ($result.Count -ne 1 -or $result[0] -cnotin $entries) { throw 'fzf 返回无效选项，未打开任何远端。' }
    return ($result[0] -split "`t", 2)[0]
}
# 将网络 Git 地址转换为不含凭据的浏览器网页地址。
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

# 打开选定远端，转交控制台或取消时不启动浏览器。
function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target, [switch]$Interactive)

    $directory = Get-JobsDirectory -Target $Target
    $remote = Get-JobsGitRemote -Directory $directory -Interactive:$Interactive
    if ($null -eq $remote) { return }
    $url = ConvertTo-JobsWebUrl -Remote $remote
    Start-Process -FilePath $url
}

Export-ModuleMember -Function Invoke-JobsFeature
