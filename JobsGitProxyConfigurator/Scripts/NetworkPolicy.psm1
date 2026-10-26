# NetworkPolicy.psm1 | JobsGitProxyConfigurator
# Created by Jobs on 2026年10月22日，星期四.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
# Metadata queries never start an operation against the remote.
function Invoke-JobsGitMetadata {
    param([string]$Git, [string[]]$GlobalArguments, [string[]]$Query, [switch]$Clone)
    $directory = $null
    if ($Clone) {
        $directory = [IO.Path]::GetPathRoot([Environment]::CurrentDirectory)
        $clean = @()
        for ($position=0; $position -lt $GlobalArguments.Count; $position++) {
            $entry = $GlobalArguments[$position]
            if ($entry -in @('-C','--git-dir','--work-tree','--namespace','--super-prefix')) { $position++; continue }
            if ($entry -match '^(-C.|--git-dir=|--work-tree=|--namespace=|--super-prefix=|--bare$)') { continue }
            $clean += $entry
        }
        $GlobalArguments = $clean
    }
    return [JobsGitProxy.Bridge]::Capture($Git, [string[]](@($GlobalArguments)+@($Query)), $directory, 10000)
}
# Only known argv forms are routed; unknown forms retain native Git semantics.
function Get-JobsGitInvocation {
    param([string[]]$ArgumentList)
    $globals=@(); $position=0
    while ($position -lt $ArgumentList.Count) {
        $entry=$ArgumentList[$position]
        if ($entry -in @('-c','-C','--git-dir','--work-tree','--namespace','--config-env','--super-prefix')) {
            if ($position+1 -ge $ArgumentList.Count) { return $null }
            $globals += $entry; $position++; $globals += $ArgumentList[$position]; $position++; continue
        }
        if ($entry -match '^(-c.|-C.|--git-dir=|--work-tree=|--namespace=|--config-env=|--super-prefix=|--exec-path=)' -or
            $entry -in @('--no-optional-locks','--no-pager','--bare','--no-replace-objects','--literal-pathspecs','--no-lazy-fetch','--no-advice','-p','-P')) {
            $globals += $entry; $position++; continue
        }
        if ($entry -notin @('clone','fetch','pull','ls-remote','push')) { return $null }
        $tail=@()
        if ($position+1 -lt $ArgumentList.Count) { $tail=@($ArgumentList[($position+1)..($ArgumentList.Count-1)]) }
        return @{ Command=$entry; Global=[string[]]$globals; Tail=[string[]]$tail; Original=$ArgumentList }
    }
    return $null
}
# Explicit recursion, extra download sources and multi-remote invocations remain native.
function Get-JobsGitRepositoryArgument {
    param($Invocation)
    $repository=''; $positionals=@(); $tail=@($Invocation.Tail)
    $takeValue=@('--depth','--deepen','--shallow-since','--shallow-exclude','--filter','--branch','-b','--origin','-o',
        '--template','--upload-pack','-u','--reference','--reference-if-able','--separate-git-dir','--jobs','-j',
        '--server-option','--refmap','--sort','--strategy','-s','--strategy-option','-X','--cleanup','--receive-pack','--exec','--push-option','--repo')
    $flags=@('-q','--quiet','-v','--verbose','--progress','--no-progress','--no-checkout','-n','--bare','--mirror',
        '--single-branch','--no-single-branch','--no-tags','--tags','-t','--sparse','--dissociate','--no-recurse-submodules',
        '--local','--no-local','--no-hardlinks','--shared','--reject-shallow','--no-reject-shallow','--shallow-submodules',
        '--no-shallow-submodules','--remote-submodules','--no-remote-submodules','--also-filter-submodules',
        '--no-also-filter-submodules','--prune','-p','--no-prune','--prune-tags','-P','--no-prune-tags',
        '--force','-f','--keep','-k','--append','-a','--atomic','--no-atomic','--dry-run','--update-head-ok',
        '--update-shallow','--unshallow','--no-write-fetch-head','--write-fetch-head','--no-auto-gc','--auto-gc',
        '--no-auto-maintenance','--auto-maintenance','--no-write-commit-graph','--write-commit-graph','--exit-code',
        '--symref','--heads','--branches','--refs','-4','--ipv4','-6','--ipv6','--rebase','-r','--no-rebase','--ff-only',
        '--ff','--no-ff','--commit','--no-commit','--edit','--no-edit','--squash','--no-squash','--stat','--no-stat',
        '--allow-unrelated-histories','--autostash','--no-autostash','--verify','--no-verify','--signoff','--no-signoff',
        '--all','--set-upstream','-u','--delete','-d','--porcelain','--follow-tags','--no-follow-tags','--force-with-lease',
        '--force-if-includes','--no-force-if-includes','--signed','--no-signed','--thin','--no-thin','--prune')
    for ($position=0; $position -lt $tail.Count; $position++) {
        $entry=$tail[$position]
        if ($entry -eq '--help' -or ($entry -eq '-h' -and ($Invocation.Command -ne 'ls-remote' -or $tail.Count -eq 1)) -or $entry -eq '--get-url') { return $null }
        if ($entry -match '^--(recursive|recurse-submodules|recurse-submodules-default|bundle-uri)(=|$)' -and $entry -ne '--recurse-submodules=no') { return $null }
        if ($Invocation.Command -ne 'push' -and $entry -in @('--all','--multiple')) { return $null }
        if ($Invocation.Command -eq 'clone' -and $entry -match '^(-c|--config)(=|$|.)') { return $null }
        if ($entry -eq '--') {
            if ($position+1 -lt $tail.Count) { $positionals += $tail[($position+1)..($tail.Count-1)] }
            break
        }
        if ($entry -eq '-h' -and $Invocation.Command -eq 'ls-remote') { continue }
        if ($entry -eq '-u' -and $Invocation.Command -eq 'push') { continue }
        if ($entry -in $takeValue) {
            if ($position+1 -ge $tail.Count) { return $null }
            $position++
            if ($entry -eq '--repo') { $repository=$tail[$position] }
            continue
        }
        if ($entry -match '^--(depth|deepen|shallow-since|shallow-exclude|filter|branch|origin|template|upload-pack|reference|reference-if-able|separate-git-dir|jobs|server-option|refmap|sort|strategy|strategy-option|cleanup|receive-pack|exec|push-option|force-with-lease|signed|rebase|repo)=') {
            if ($entry.StartsWith('--repo=')) { $repository=$entry.Substring(7) }
            continue
        }
        if ($entry -match '^(-b|-j|-X).+' -or $entry -in $flags -or $entry -eq '--recurse-submodules=no') { continue }
        if ($entry.StartsWith('-')) { return $null }
        $positionals += $entry
    }
    if ($Invocation.Command -eq 'clone' -and ($positionals.Count -lt 1 -or $positionals.Count -gt 2)) { return $null }
    if (-not $repository -and $positionals.Count -gt 0) { $repository=$positionals[0] }
    return @{ Repository=$repository; Explicit=([bool]$repository) }
}
# Read configuration in the same scope used for the future operation.
function Get-JobsGitConfig {
    param([string]$Git, $Invocation, [string[]]$Query)
    return Invoke-JobsGitMetadata $Git $Invocation.Global $Query -Clone:($Invocation.Command -eq 'clone')
}
# Default remotes follow Git's branch and pushRemote precedence.
function Get-JobsGitDefaultRemote {
    param([string]$Git, $Invocation)
    $branch=(Get-JobsGitConfig $Git $Invocation @('symbolic-ref','--quiet','--short','HEAD')).Output.Trim()
    $keys=@()
    if ($Invocation.Command -eq 'push') {
        if ($branch) { $keys += ('branch.'+$branch+'.pushRemote') }
        $keys += 'remote.pushDefault'
    }
    if ($branch) { $keys += ('branch.'+$branch+'.remote') }
    foreach ($key in $keys) {
        $value=(Get-JobsGitConfig $Git $Invocation @('config','--get',$key)).Output.Trim()
        if ($value) { return $value }
    }
    return 'origin'
}
# Fetch-all and implicit submodule recursion may contact targets on other sites.
function Test-JobsGitMultiTarget {
    param([string]$Git, $Invocation, [bool]$Explicit)
    if ($Invocation.Command -in @('clone','ls-remote')) { return $false }
    if (-not $Explicit -and $Invocation.Command -in @('fetch','pull')) {
        $all=(Get-JobsGitConfig $Git $Invocation @('config','--bool','--get','fetch.all')).Output.Trim()
        if ($all -eq 'true') { return $true }
    }
    if (@($Invocation.Tail | Where-Object { $_ -in @('--no-recurse-submodules','--recurse-submodules=no') }).Count) { return $false }
    $key='fetch.recurseSubmodules'
    if ($Invocation.Command -eq 'push') { $key='push.recurseSubmodules' }
    foreach ($candidate in @($key,'submodule.recurse')) {
        $result=Get-JobsGitConfig $Git $Invocation @('config','--get',$candidate)
        if ($result.ExitCode -eq 0) { return ($result.Output.Trim() -notmatch '^(false|no|off|0)$') }
    }
    if ($Invocation.Command -in @('fetch','pull')) {
        return ((Get-JobsGitConfig $Git $Invocation @('ls-files','--stage')).Output -match '(?m)^160000 ')
    }
    return $false
}
# Expand aliases without a synthetic remote, so clone works outside repositories.
function Get-JobsGitTarget {
    param([string]$Git, $Invocation)
    if ($Invocation.Command -eq 'clone') {
        $environment=[Environment]::GetEnvironmentVariables('Process')
        foreach ($key in @('GIT_DIR','GIT_WORK_TREE','GIT_COMMON_DIR')) {
            if ($environment.Contains($key)) { return $null }
        }
    }
    $parsed=Get-JobsGitRepositoryArgument $Invocation
    if ($null -eq $parsed -or (Test-JobsGitMultiTarget $Git $Invocation $parsed.Explicit)) { return $null }
    $repository=$parsed.Repository
    if (-not $repository) { $repository=Get-JobsGitDefaultRemote $Git $Invocation }
    $remote=''; $query=@('remote','get-url','--all',$repository)
    if ($Invocation.Command -eq 'push') { $query=@('remote','get-url','--push','--all',$repository) }
    $result=Get-JobsGitConfig $Git $Invocation $query
    if ($Invocation.Command -ne 'clone' -and $result.ExitCode -eq 0) {
        $remote=$repository; $urls=@($result.Output.Trim() -split '\r?\n')
    } else {
        if ($Invocation.Command -eq 'push') {
            $rewrite=Get-JobsGitConfig $Git $Invocation @('config','--null','--get-regexp','^url\..*\.pushinsteadof$')
            $longest=''; $base=''
            foreach ($record in $rewrite.Output.Split([char]0)) {
                $split=$record.IndexOf([char]10)
                if ($split -lt 0) { continue }
                $prefix=$record.Substring($split+1)
                if ($prefix.Length -gt $longest.Length -and $repository.StartsWith($prefix,[StringComparison]::Ordinal)) {
                    $longest=$prefix; $base=$record.Substring(0,$split); $base=$base.Substring(4,$base.Length-4-14)
                }
            }
            if ($longest) { $repository=$base+$repository.Substring($longest.Length) }
        }
        $result=Get-JobsGitConfig $Git $Invocation @('ls-remote','--get-url',$repository)
        if ($result.ExitCode -ne 0) { return $null }
        $urls=@($result.Output.Trim() -split '\r?\n')
    }
    if ($urls.Count -ne 1 -or $urls[0] -notmatch '^https?://') { return $null }
    $uri=$null
    if (-not [Uri]::TryCreate($urls[0],[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -notin @('http','https')) { return $null }
    $site=New-Object UriBuilder($uri.Scheme,$uri.Host,$uri.Port)
    $site.UserName=''; $site.Password=''; $site.Path='/'; $site.Query=''; $site.Fragment=''
    return @{ Url=$urls[0]; Root=$site.Uri.AbsoluteUri; Host=$uri.DnsSafeHost; Port=$uri.Port; Remote=$remote }
}
# Detect explicit empty proxy as a choice, instead of silently replacing it.
function Test-JobsGitExplicitProxy {
    param([string]$Git, $Invocation, $Target)
    $variables=[Environment]::GetEnvironmentVariables('Process')
    foreach ($name in @('http_proxy','https_proxy','all_proxy','HTTP_PROXY','HTTPS_PROXY','ALL_PROXY')) {
        if ($variables.Contains($name)) { return $true }
    }
    if ((Get-JobsGitConfig $Git $Invocation @('config','--get-urlmatch','http.proxy',$Target.Url)).ExitCode -eq 0) { return $true }
    if ($Target.Remote -and (Get-JobsGitConfig $Git $Invocation @('config','--get',('remote.'+$Target.Remote+'.proxy'))).ExitCode -eq 0) { return $true }
    return $false
}
# WinINET is queried per invocation; PAC and system-wide proxy settings are never changed.
function Get-JobsGitSystemProxy {
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Microsoft\Windows\CurrentVersion\Internet Settings')
    if ($null -eq $key) { return @{ Enabled=$false; Server=''; Bypass='' } }
    try { return @{ Enabled=($key.GetValue('ProxyEnable',0) -eq 1); Server=[string]$key.GetValue('ProxyServer',''); Bypass=[string]$key.GetValue('ProxyOverride','') } }
    finally { $key.Dispose() }
}
# Respect domain, wildcard, simple-host and IP/CIDR bypass declarations.
function Test-JobsGitBypass {
    param([string]$HostName, [string]$Rules)
    $hostValue=$HostName.Trim('[',']').ToLowerInvariant()
    foreach ($entry in ($Rules -split '[,;]')) {
        $rule=$entry.Trim().ToLowerInvariant()
        if (-not $rule) { continue }
        if ($rule -eq '<local>' -and $hostValue -notmatch '[.:]') { return $true }
        if ($rule.Contains('/')) {
            $parts=$rule.Split('/'); $left=$null; $right=$null
            if ($parts.Count -ne 2 -or -not [Net.IPAddress]::TryParse($hostValue,[ref]$left) -or -not [Net.IPAddress]::TryParse($parts[0],[ref]$right)) { continue }
            $leftBytes=$left.GetAddressBytes(); $rightBytes=$right.GetAddressBytes(); $bits=0
            if ($leftBytes.Length -ne $rightBytes.Length -or -not [int]::TryParse($parts[1],[ref]$bits) -or $bits -lt 0 -or $bits -gt $leftBytes.Length*8) { continue }
            $matched=$true
            for ($index=0;$index -lt $leftBytes.Length;$index++) {
                $count=[Math]::Min(8,[Math]::Max(0,$bits-$index*8))
                $mask=0; if ($count) { $mask=(255 -shl (8-$count)) -band 255 }
                if (($leftBytes[$index] -band $mask) -ne ($rightBytes[$index] -band $mask)) { $matched=$false; break }
            }
            if ($matched) { return $true }; continue
        }
        $domain=$rule.TrimStart('.')
        if ($hostValue -eq $domain -or $hostValue.EndsWith('.'+$domain,[StringComparison]::Ordinal)) { return $true }
        if ($hostValue -like $rule) { return $true }
    }
    return $false
}
# Static HTTP/HTTPS/SOCKS endpoints are accepted without credentials or fixed product ports.
function Get-JobsGitProxyCandidates {
    param($Snapshot)
    if (-not $Snapshot.Enabled) { return @() }
    $entries=@{}
    if ($Snapshot.Server -notmatch '=') { $entries.https=$Snapshot.Server; $entries.http=$Snapshot.Server }
    else {
        foreach ($part in ($Snapshot.Server -split ';')) {
            $pair=$part.Split([char[]]'=',2,[StringSplitOptions]::None)
            if ($pair.Count -eq 2) { $entries[$pair[0].Trim().ToLowerInvariant()]=$pair[1].Trim() }
        }
    }
    $candidates=@()
    foreach ($kind in @('https','http','socks')) {
        if (-not $entries.ContainsKey($kind)) { continue }
        $endpoint=$entries[$kind]
        if ($endpoint -notmatch '^(\[[0-9a-fA-F:]+\]|[A-Za-z0-9_.-]+):([0-9]{1,5})$') { continue }
        $port=[int]$Matches[2]
        if ($port -lt 1 -or $port -gt 65535) { continue }
        $scheme='http'; if ($kind -eq 'socks') { $scheme='socks5h' }
        $candidate=$scheme+'://'+$endpoint
        if ($candidate -notin $candidates) { $candidates += $candidate }
    }
    return $candidates
}
# Curl is reused from Git for Windows or Windows itself; no dependency is downloaded.
function Get-JobsGitCurl {
    param([string]$Git)
    $base=Split-Path -Parent (Split-Path -Parent $Git)
    foreach ($path in @((Join-Path $base 'mingw64/bin/curl.exe'),(Join-Path $base 'mingw32/bin/curl.exe'),
        (Join-Path ([Environment]::GetFolderPath('System')) 'curl.exe'))) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
    }
    return $null
}
# Probe site roots without Git credentials; return codes alone never replay business.
function Invoke-JobsGitProbe {
    param([string]$Curl, $Target, [AllowEmptyString()][string]$Proxy)
    $connection=2; $total=4; $number=0
    if ([int]::TryParse($env:JOBS_GIT_CONNECT_TIMEOUT,[ref]$number) -and $number -ge 1 -and $number -le 60) { $connection=$number }
    if ([int]::TryParse($env:JOBS_GIT_PROBE_TIMEOUT,[ref]$number) -and $number -ge 1 -and $number -le 120) { $total=$number }
    $probeArguments=@('--disable','--silent','--head','--output','NUL','--write-out','%{http_code}',
        '--connect-timeout',[string]$connection,'--max-time',[string]$total,'--proto','=http,https','--proxy',$Proxy)
    if (-not $Proxy) { $probeArguments += @('--noproxy','*') }
    $probeArguments += $Target.Root
    return [JobsGitProxy.Bridge]::Capture($Curl,[string[]]$probeArguments,$null,($total+2)*1000)
}
# Audit is deliberately limited to site, mode and status; no URL/path/credentials.
function Write-JobsGitRouteAudit {
    param([string]$Mode, $Target, [int]$Code)
    try {
        $directory=Join-Path $env:LOCALAPPDATA 'JobsGitNetworkStrategy/logs'
        [void][IO.Directory]::CreateDirectory($directory)
        $hostName=$Target.Host -replace '[^A-Za-z0-9_.:\[\]-]','_'
        $line=('{0} mode={1} host={2} port={3} exit={4}' -f [DateTime]::UtcNow.ToString('o'),$Mode,$hostName,$Target.Port,$Code)
        [IO.File]::AppendAllText((Join-Path $directory 'route.log'),$line+[Environment]::NewLine,[Text.Encoding]::UTF8)
    } catch { }
}
# Native business inherits OS handles and is invoked at most once.
function Invoke-JobsGitBusiness {
    param([string]$Git,$Invocation,$Target,[AllowEmptyString()][string]$Proxy,[string]$Mode)
    $arguments=@($Invocation.Original)
    if ($Proxy) { $arguments=@($Invocation.Global)+@('-c',('http.'+$Target.Root+'.proxy='+$Proxy),$Invocation.Command)+@($Invocation.Tail) }
    $code=[JobsGitProxy.Bridge]::Execute($Git,[string[]]$arguments)
    Write-JobsGitRouteAudit $Mode $Target $code
    return $code
}
# Known TLS differences are handed to Git's own CA/mTLS configuration exactly once.
function Test-JobsGitProbeTls {
    param([int]$Code)
    return $Code -in @(35,51,58,59,60,64,66,77,80,82,83,90,91)
}
# System proxy first; direct remains available when candidates are unavailable.
function Invoke-JobsGitNetworkPolicy {
    param([string]$Git,[string[]]$ArgumentList)
    $invocation=Get-JobsGitInvocation $ArgumentList
    if ($null -eq $invocation) { return [JobsGitProxy.Bridge]::Execute($Git,$ArgumentList) }
    $target=Get-JobsGitTarget $Git $invocation
    if ($null -eq $target) { return [JobsGitProxy.Bridge]::Execute($Git,$ArgumentList) }
    if (Test-JobsGitExplicitProxy $Git $invocation $target) { return Invoke-JobsGitBusiness $Git $invocation $target '' 'explicit' }
    $curl=Get-JobsGitCurl $Git
    if (-not $curl) { return Invoke-JobsGitBusiness $Git $invocation $target '' 'no-curl-native' }
    $priority=$env:JOBS_GIT_ROUTE_PRIORITY
    if ($priority -notin @('system','direct')) { $priority='system' }
    $snapshot=$null
    if ($priority -eq 'direct') {
        $probe=Invoke-JobsGitProbe $curl $target ''
        Write-JobsGitRouteAudit 'direct-probe' $target $probe.ExitCode
        if ($probe.Output -match '^[1-5][0-9][0-9]$' -or $probe.ExitCode -notin @(6,7,28)) {
            return Invoke-JobsGitBusiness $Git $invocation $target '' 'direct'
        }
    }
    $snapshot=Get-JobsGitSystemProxy
    $rules=[string]$snapshot.Bypass+','+$env:NO_PROXY+','+$env:no_proxy
    $bypass=Test-JobsGitBypass $target.Host $rules
    if (-not $bypass) {
        foreach ($proxy in @(Get-JobsGitProxyCandidates $snapshot)) {
            $probe=Invoke-JobsGitProbe $curl $target $proxy
            Write-JobsGitRouteAudit 'proxy-probe' $target $probe.ExitCode
            if (($probe.Output -match '^[1-5][0-9][0-9]$' -and $probe.Output -ne '407') -or (Test-JobsGitProbeTls $probe.ExitCode)) {
                return Invoke-JobsGitBusiness $Git $invocation $target $proxy 'proxy'
            }
        }
    }
    if ($priority -eq 'system') {
        $probe=Invoke-JobsGitProbe $curl $target ''
        Write-JobsGitRouteAudit 'direct-probe' $target $probe.ExitCode
        if ($probe.Output -match '^[1-5][0-9][0-9]$' -or $probe.ExitCode -notin @(6,7,28)) {
            return Invoke-JobsGitBusiness $Git $invocation $target '' 'direct'
        }
    }
    [Console]::Error.WriteLine('[Jobs Git] 系统代理与直连均不可达；未执行 Git 业务，请检查网络。')
    Write-JobsGitRouteAudit 'network-unavailable' $target 128
    return 128
}
Export-ModuleMember -Function Invoke-JobsGitNetworkPolicy
