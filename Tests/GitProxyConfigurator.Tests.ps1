# GitProxyConfigurator.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月22日，星期四.
# Only temporary files, mocked HKCU PATH, and native read-only Git metadata are used.
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$script:Assertions=0
$root=Split-Path -Parent $PSScriptRoot
$package=Join-Path $root 'JobsGitProxyConfigurator'
$temporary=Join-Path ([IO.Path]::GetTempPath()) ('JobsGitProxy-'+[guid]::NewGuid().ToString('N'))
$savedLocal=$env:LOCALAPPDATA
$savedPriority=$env:JOBS_GIT_ROUTE_PRIORITY
$savedNoProxy=$env:NO_PROXY
$savedGitDir=$env:GIT_DIR
function Assert-Proxy {
    param([bool]$Condition,[string]$Message)
    $script:Assertions++
    if (-not $Condition) { throw ('FAIL: '+$Message) }
}
function Assert-ProxyThrows {
    param([scriptblock]$Body,[string]$Message)
    $threw=$false
    try { & $Body | Out-Null } catch { $threw=$true }
    Assert-Proxy $threw $Message
}
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    Add-Type -Path (Join-Path $package 'Scripts/GitShim.cs')
    $common=Import-Module (Join-Path $package 'Scripts/Common.psm1') -PassThru -DisableNameChecking
    foreach($value in @('','plain','C:\','C:\中文 & %value%\path\','a"b','a\"b\')) {
        $expected=& $common {param($Value) Quote-JobsArgument $Value} $value
        Assert-Proxy ([JobsGitProxy.Bridge]::Quote($value) -ceq $expected) 'native EXE preserves Windows quoting'
    }
    $original=[string[]]@('clone','https://example.test/a.git','中文 & %PATH%','','trailing\')
    $decoded=[JobsGitProxy.Bridge]::Decode([JobsGitProxy.Bridge]::Encode($original))
    Assert-Proxy ($decoded.Count -eq $original.Count) 'argument transport preserves empty arguments'
    for($index=0;$index -lt $original.Count;$index++){ Assert-Proxy ($decoded[$index] -ceq $original[$index]) 'argument bytes roundtrip' }
    Assert-Proxy (-not [JobsGitProxy.Bridge]::IsNetwork(@('status','--porcelain'))) 'local commands bypass PowerShell routing'
    Assert-Proxy ([JobsGitProxy.Bridge]::IsNetwork(@('-c','core.quotepath=false','--no-optional-locks','ls-remote','https://example.test/a.git'))) 'Sourcetree argv recognized'
    $installer=Import-Module (Join-Path $package 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    $manifest=Get-Content -LiteralPath (Join-Path $package 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $plan=@(& $installer {param($Manifest,$Release) Get-JobsPackageRegistryPlan $Manifest $Release 'powershell.exe'} $manifest $temporary)
    Assert-Proxy ($plan.Count -eq 1) 'one menu only'
    Assert-Proxy ($plan[0].Key -ceq 'Software\Classes\DesktopBackground\shell\Jobs.WindowsExtension.git-proxy-configure') 'desktop background only; no directory or selected item'
    Assert-Proxy ($plan[0].Command.Contains('Invoke.ps1') -and $plan[0].Command.Contains($temporary)) 'menu uses own release'
    $policy=Import-Module (Join-Path $package 'Scripts/NetworkPolicy.psm1') -PassThru -DisableNameChecking
    $parsed=& $policy { Get-JobsGitInvocation @('-c','diff.mnemonicprefix=false','-c','core.quotepath=false','--no-optional-locks','ls-remote','https://example.test/a.git') }
    Assert-Proxy ($parsed.Command -eq 'ls-remote' -and $parsed.Global.Count -eq 5) 'global config pairs preserved'
    foreach($case in @(
        @{Arg=@('push','-u','origin','main');Repo='origin'},
        @{Arg=@('clone','--depth','1','--branch','main','https://example.test/a.git','space path');Repo='https://example.test/a.git'},
        @{Arg=@('ls-remote','-h','https://example.test/a.git');Repo='https://example.test/a.git'}
    )) {
        $result=& $policy {param($List) $inv=Get-JobsGitInvocation $List;Get-JobsGitRepositoryArgument $inv} $case.Arg
        Assert-Proxy ($result.Repository -ceq $case.Repo) 'common repository argument resolves'
    }
    foreach($list in @(
        @('fetch','--all'),@('fetch','--multiple','one','two'),
        @('clone','--recurse-submodules','https://example.test/a.git'),@('clone','--bundle-uri','https://example.test/bundle','https://example.test/a.git'),
        @('fetch','--unknown','origin'),@('ls-remote','--get-url','https://example.test/a.git')
    )) {
        $result=& $policy {param($List) Get-JobsGitRepositoryArgument (Get-JobsGitInvocation $List)} $list
        Assert-Proxy ($null -eq $result) 'unknown/multiple/recursive/read-only form stays native'
    }
    $target=& $policy {
        function script:Get-JobsGitConfig {
            param($Git,$Invocation,$Query)
            [pscustomobject]@{ExitCode=0;Output='https://user:fixture-secret@git.example.test:8443/private.git?q=fixture';Error=''}
        }
        Get-JobsGitTarget 'git' (Get-JobsGitInvocation @('ls-remote','https://git.example.test/a.git'))
    }
    Assert-Proxy ($target.Root -ceq 'https://git.example.test:8443/') 'probe root strips credentials, path and query'
    $env:GIT_DIR='explicit-environment'
    $clone=& $policy { Get-JobsGitTarget 'git' (Get-JobsGitInvocation @('clone','https://example.test/a.git')) }
    Assert-Proxy ($null -eq $clone) 'explicit Git directory environment keeps clone native'
    $env:GIT_DIR=$savedGitDir
    $candidates=@(& $policy { Get-JobsGitProxyCandidates @{Enabled=$true;Server='https=proxy.example.test:8765;http=proxy.example.test:8765;socks=[::1]:9876';Bypass=''} })
    Assert-Proxy ($candidates.Count -eq 2 -and $candidates[0] -eq 'http://proxy.example.test:8765' -and $candidates[1] -eq 'socks5h://[::1]:9876') 'WinINET candidates deduplicate in priority order'
    foreach($case in @(
        @{Enabled=$true;Server='https=secure.example.test:8765;http=plain.example.test:8766;socks=[::1]:9876';Expected='http://secure.example.test:8765|http://plain.example.test:8766|socks5h://[::1]:9876'},
        @{Enabled=$true;Server=' https = proxy.example.test:8765 ; http = ;socks=[::1]:0';Expected='http://proxy.example.test:8765'},
        @{Enabled=$true;Server='https=proxy.example.test:80=unexpected;http=plain.example.test:8080';Expected='http://plain.example.test:8080'},
        @{Enabled=$true;Server='proxy.example.test:9876';Expected='http://proxy.example.test:9876'},
        @{Enabled=$false;Server='https=proxy.example.test:8765';Expected=''}
    )) {
        $actual=@(& $policy {param($Snapshot) Get-JobsGitProxyCandidates $Snapshot} $case)
        Assert-Proxy (($actual -join '|') -ceq $case.Expected) 'Framework-compatible WinINET parsing preserves endpoint rules'
    }
    foreach($case in @(
        @{Host='a.example.test';Rules='.example.test';Value=$true},
        @{Host='a.example.test';Rules='*.example.test';Value=$true},
        @{Host='printer';Rules='<local>';Value=$true},
        @{Host='10.2.3.4';Rules='10.0.0.0/8';Value=$true},
        @{Host='2001:db8::1';Rules='2001:db8::/32';Value=$true},
        @{Host='outside.test';Rules='.example.test';Value=$false}
    )) {
        $actual=& $policy {param($HostName,$Rules) Test-JobsGitBypass $HostName $Rules} $case.Host $case.Rules
        Assert-Proxy ($actual -eq $case.Value) 'bypass declaration respected'
    }
    & $policy {
        $script:FixtureTarget=@{Url='https://example.test/repo.git';Root='https://example.test/';Host='example.test';Port=443;Remote='origin'}
        function script:Get-JobsGitTarget {param($Git,$Invocation) return $script:FixtureTarget}
        function script:Test-JobsGitExplicitProxy {param($Git,$Invocation,$Target) return $script:Explicit}
        function script:Get-JobsGitCurl {param($Git) return 'fixture-curl'}
        function script:Get-JobsGitSystemProxy {return @{Enabled=$true;Server='proxy.test:7654';Bypass=$script:Bypass}}
        function script:Invoke-JobsGitProbe {
            param($Curl,$Target,$Proxy)
            $script:Probes+=@{Proxy=$Proxy;Root=$Target.Root}
            $result=$script:Queue[0]
            if($script:Queue.Count -gt 1){$script:Queue=@($script:Queue[1..($script:Queue.Count-1)])}else{$script:Queue=@()}
            return $result
        }
        function script:Invoke-JobsGitBusiness {
            param($Git,$Invocation,$Target,$Proxy,$Mode)
            $script:Businesses+=@{Proxy=$Proxy;Mode=$Mode;Original=$Invocation.Original}
            return 17
        }
        function script:Write-JobsGitRouteAudit {param($Mode,$Target,$Code)}
    }
    $env:NO_PROXY=''
    $routes=@(
        @{Name='default-system';Priority='';Queue=@(@{ExitCode=0;Output='200'});Mode='proxy';Count=1;Exit=17;Explicit=$false;Bypass=''},
        @{Name='proxy-failure-direct';Priority='system';Queue=@(@{ExitCode=7;Output='000'},@{ExitCode=0;Output='401'});Mode='direct';Count=1;Exit=17;Explicit=$false;Bypass=''},
        @{Name='proxy-auth-direct';Priority='system';Queue=@(@{ExitCode=0;Output='407'},@{ExitCode=0;Output='200'});Mode='direct';Count=1;Exit=17;Explicit=$false;Bypass=''},
        @{Name='proxy-tls-native';Priority='system';Queue=@(@{ExitCode=60;Output='000'});Mode='proxy';Count=1;Exit=17;Explicit=$false;Bypass=''},
        @{Name='both-fail';Priority='system';Queue=@(@{ExitCode=7;Output='000'},@{ExitCode=28;Output='000'});Mode='';Count=0;Exit=128;Explicit=$false;Bypass=''},
        @{Name='explicit';Priority='system';Queue=@();Mode='explicit';Count=1;Exit=17;Explicit=$true;Bypass=''},
        @{Name='bypass';Priority='system';Queue=@(@{ExitCode=0;Output='200'});Mode='direct';Count=1;Exit=17;Explicit=$false;Bypass='example.test'},
        @{Name='direct-first';Priority='direct';Queue=@(@{ExitCode=0;Output='200'});Mode='direct';Count=1;Exit=17;Explicit=$false;Bypass=''}
    )
    foreach($case in $routes) {
        $env:JOBS_GIT_ROUTE_PRIORITY=$case.Priority
        $result=& $policy {
            param($Case)
            $script:Explicit=$Case.Explicit;$script:Bypass=$Case.Bypass;$script:Queue=@($Case.Queue);$script:Probes=@();$script:Businesses=@()
            $code=Invoke-JobsGitNetworkPolicy 'git' @('fetch','origin')
            return @{Code=$code;Probes=@($script:Probes);Businesses=@($script:Businesses)}
        } $case
        Assert-Proxy ($result.Code -eq $case.Exit) ($case.Name+' exit preserved')
        Assert-Proxy ($result.Businesses.Count -eq $case.Count) ($case.Name+' at most one business')
        if($case.Count){Assert-Proxy ($result.Businesses[0].Mode -eq $case.Mode) ($case.Name+' route')}
        if($case.Name -eq 'default-system'){Assert-Proxy ($result.Probes.Count -eq 1 -and $result.Probes[0].Proxy) 'default never probes direct first'}
        if($case.Name -eq 'explicit'){Assert-Proxy ($result.Probes.Count -eq 0) 'explicit proxy never probes'}
    }
    $configuration=Import-Module (Join-Path $package 'Scripts/ProxyInstaller.psm1') -PassThru -DisableNameChecking
    $env:LOCALAPPDATA=Join-Path $temporary 'UserData'
    $real=Join-Path $temporary 'original-git.exe'
    [IO.File]::WriteAllText($real,'fixture original')
    & $configuration {
        param($Original)
        $script:OriginalGit=$Original
        $script:FixturePath=@{Exists=$true;Kind='ExpandString';Value='C:\before;;%CUSTOM%\bin;'}
        $script:FixtureVersion='A';$script:Writes=0;$script:FailOnce=$false;$script:FailStateOnce=$false
        $script:ActualWriteState=(Get-Item Function:Write-JobsProxyActive).ScriptBlock
        function script:Write-JobsProxyActive {
            param($Paths,$State,$Expected)
            if($script:FailStateOnce){$script:FailStateOnce=$false;throw 'fixture atomic state write failure'}
            & $script:ActualWriteState $Paths $State $Expected
        }
        function script:Read-JobsProxyUserPath {return $script:FixturePath}
        function script:Write-JobsProxyUserPath {
            param($State)
            $script:Writes++
            if($script:FailOnce){$script:FailOnce=$false;throw 'fixture PATH write failure'}
            $script:FixturePath=@{Exists=$State.Exists;Kind=$State.Kind;Value=$State.Value}
        }
        function script:Find-JobsProxyRealGit {param($Runtime) return $script:OriginalGit}
        function script:Get-JobsProxySourceHash {return $script:FixtureVersion}
        function script:Build-JobsProxyShim {param($Output) [IO.File]::WriteAllText($Output,'shim-'+$script:FixtureVersion)}
    } $real
    $missing=Test-JobsGitProxyInstallation
    Assert-Proxy (-not $missing -and -not (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'JobsGitNetworkStrategy'))) 'uninstalled check is read-only'
    $first=Install-JobsGitProxy
    Assert-Proxy ($first.AfterPath.Value.EndsWith('C:\before;;%CUSTOM%\bin;',[StringComparison]::Ordinal)) 'PATH original empty segments and suffix preserved'
    $paths=& $configuration {Get-JobsProxyPaths}
    $beforeCheck=@(Get-ChildItem $paths.Root -Recurse -File | ForEach-Object {(Get-FileHash $_.FullName).Hash}) -join ':'
    Assert-Proxy (Test-JobsGitProxyInstallation) 'installed check succeeds'
    $afterCheck=@(Get-ChildItem $paths.Root -Recurse -File | ForEach-Object {(Get-FileHash $_.FullName).Hash}) -join ':'
    Assert-Proxy ($beforeCheck -ceq $afterCheck) 'installed check changes no files'
    $repeat=Install-JobsGitProxy
    Assert-Proxy ($repeat.Snapshot -ceq $first.Snapshot) 'repeat install creates no snapshot'
    & $configuration {$script:FixtureVersion='B'}
    $second=Install-JobsGitProxy
    Assert-Proxy ($second.Snapshot -cne $first.Snapshot) 'upgrade has own exact snapshot'
    Restore-JobsGitProxy
    Assert-Proxy (Test-JobsGitProxyInstallation) 'restored upgrade still recognizes prior active version'
    $restoredBytes=[IO.File]::ReadAllText((Join-Path $paths.Bin 'git.exe'))
    Assert-Proxy ($restoredBytes -ceq 'shim-A') 'upgrade restore returns previous runtime'
    Restore-JobsGitProxy
    Assert-Proxy ([IO.File]::ReadAllText((Join-Path $paths.Bin 'git.exe')) -ceq 'shim-A') 'repeat restore does not uninstall previous version'
    $upgradedAgain=Install-JobsGitProxy
    & $configuration {$script:FailOnce=$true}
    Assert-ProxyThrows {Restore-JobsGitProxy} 'restore write failure reports failure'
    Assert-Proxy (Test-JobsGitProxyInstallation) 'failed restore rolls back managed files and PATH to after-state'
    Assert-Proxy ([IO.File]::ReadAllText((Join-Path $paths.Bin 'git.exe')) -ceq 'shim-B') 'failed restore keeps current runtime intact'
    $activeBefore=[IO.File]::ReadAllBytes($paths.Active)
    & $configuration {$script:FailStateOnce=$true}
    Assert-ProxyThrows {Restore-JobsGitProxy} 'restore state write failure reports failure'
    Assert-Proxy (Test-JobsGitProxyInstallation) 'failed state commit rolls runtime and PATH back to installed version'
    Assert-Proxy ([Convert]::ToBase64String([IO.File]::ReadAllBytes($paths.Active)) -ceq [Convert]::ToBase64String($activeBefore)) 'failed state commit leaves original active bytes intact'
    $stateToken=[Convert]::ToBase64String($activeBefore)
    [IO.File]::AppendAllText($paths.Active,[Environment]::NewLine)
    $concurrentState=[Convert]::ToBase64String([IO.File]::ReadAllBytes($paths.Active))
    Assert-ProxyThrows {& $configuration {param($Paths,$State,$Expected) Write-JobsProxyActive $Paths $State $Expected} $paths $upgradedAgain $stateToken} 'atomic writer rejects concurrently changed active state'
    Assert-Proxy ([Convert]::ToBase64String([IO.File]::ReadAllBytes($paths.Active)) -ceq $concurrentState) 'unknown active state bytes are preserved'
    [IO.File]::WriteAllBytes($paths.Active,$activeBefore)
    $savedState=& $configuration {Read-JobsProxyActive (Get-JobsProxyPaths)}
    & $configuration {$script:FixturePath.Value+=';concurrent-user'}
    Assert-ProxyThrows {Restore-JobsGitProxy} 'concurrent PATH blocks all restoration'
    Assert-Proxy ([IO.File]::ReadAllText((Join-Path $paths.Bin 'git.exe')) -ceq 'shim-B') 'PATH conflict did not touch runtime'
    & $configuration {param($State) $script:FixturePath=$State.AfterPath} $savedState
    $policyPath=Join-Path $paths.Bin 'Policy.ps1'
    [IO.File]::AppendAllText($policyPath,'concurrent user')
    Assert-ProxyThrows {Restore-JobsGitProxy} 'concurrent runtime edit blocks restoration'
    Assert-Proxy ([IO.File]::ReadAllText($policyPath).EndsWith('concurrent user')) 'runtime conflict is not overwritten'
    & $configuration {param($State) Set-JobsProxyRuntimeFiles (Get-JobsProxyPaths).Bin $State.AfterFiles} $savedState
    Restore-JobsGitProxy
    Assert-Proxy (Test-JobsGitProxyInstallation) 'successful retry restores previous version'
    $unknown=Join-Path $paths.Bin 'unknown.txt'
    [IO.File]::WriteAllText($unknown,'keep')
    Assert-ProxyThrows {Install-JobsGitProxy} 'unknown runtime content never overwritten'
    Assert-Proxy ([IO.File]::ReadAllText($unknown) -ceq 'keep') 'unknown content preserved'
    Write-Host ('PASS: GitProxyConfigurator.Tests.ps1 ('+$script:Assertions+' assertions)')
} finally {
    $env:LOCALAPPDATA=$savedLocal
    $env:JOBS_GIT_ROUTE_PRIORITY=$savedPriority
    $env:NO_PROXY=$savedNoProxy
    $env:GIT_DIR=$savedGitDir
    if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Recurse -Force}
}
