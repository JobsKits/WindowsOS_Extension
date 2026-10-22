# ProxyInstaller.psm1 | JobsGitProxyConfigurator
# Created by Jobs on 2026年10月22日，星期四.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:ProxyOwner='Jobs.GitDynamicProxy.v1'
# Separate runtime from menu releases, so menu updates do not replace live Git.
function Get-JobsProxyPaths {
    $root=Join-Path $env:LOCALAPPDATA 'JobsGitNetworkStrategy'
    return @{Root=$root;Bin=(Join-Path $root 'runtime/bin');Active=(Join-Path $root 'active.clixml');Snapshots=(Join-Path $root 'snapshots');Log=(Join-Path $root 'install.log')}
}
# This one current-user value is the only environment configuration we change.
function Read-JobsProxyUserPath {
    $key=[Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment')
    if ($null -eq $key) { return @{Exists=$false;Kind='ExpandString';Value=''} }
    try {
        if ('Path' -notin @($key.GetValueNames())) { return @{Exists=$false;Kind='ExpandString';Value=''} }
        $kind=$key.GetValueKind('Path').ToString()
        if ($kind -notin @('String','ExpandString')) { throw '用户 PATH 类型未知，停止修改。' }
        return @{Exists=$true;Kind=$kind;Value=[string]$key.GetValue('Path',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)}
    } finally { $key.Dispose() }
}
# Restore missing, empty and typed values without clearing other environment entries.
function Write-JobsProxyUserPath {
    param($State)
    $key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
    try {
        if ($State.Exists) { $key.SetValue('Path',[string]$State.Value,[Microsoft.Win32.RegistryValueKind]([Enum]::Parse([Microsoft.Win32.RegistryValueKind],$State.Kind))) }
        else { $key.DeleteValue('Path',$false) }
    } finally { $key.Dispose() }
}
# Snapshots can contain PATH; restrict the directory to the current user.
function New-JobsProxyPrivateDirectory {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $item=Get-Item -LiteralPath $Path -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '配置路径不是可信普通目录。' }
    } else { [void][IO.Directory]::CreateDirectory($Path) }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent().User
        $acl=New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true,$false)
        $rule=New-Object Security.AccessControl.FileSystemAccessRule($identity,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
        $acl.AddAccessRule($rule)
        [IO.Directory]::SetAccessControl($Path,$acl)
    }
}
# Links, directories and unknown additions prevent replacement of the runtime.
function Get-JobsProxyRuntimeFiles {
    param([string]$Directory)
    $files=@{}
    if (-not (Test-Path -LiteralPath $Directory)) { return $files }
    $root=Get-Item -LiteralPath $Directory -Force
    if (-not $root.PSIsContainer -or ($root.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '运行态目录不是普通目录。' }
    $allowed=@('git.exe','Policy.ps1','NetworkPolicy.psm1','real-git.path','OpenGitCmd.cmd','OpenGitPowerShell.cmd','owner.json')
    foreach ($item in Get-ChildItem -LiteralPath $Directory -Force) {
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Name -notin $allowed) { throw '运行态存在未知或链接条目，停止覆盖。' }
        $files[$item.Name]=[Convert]::ToBase64String([IO.File]::ReadAllBytes($item.FullName))
    }
    return $files
}
# Stable source digests avoid recompiling or creating snapshots on repeat installs.
function Get-JobsProxySourceHash {
    $values=@()
    foreach ($name in @('GitShim.cs','Policy.ps1','NetworkPolicy.psm1')) {
        $path=Join-Path $PSScriptRoot $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw ('独立包缺少运行源码：'+$name) }
        $values += (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    }
    return ($values -join ':')
}
# Find a real executable outside our runtime; never replace a Git installation.
function Find-JobsProxyRealGit {
    param([string]$Runtime)
    $candidates=@(Get-Command git.exe -CommandType Application -All -ErrorAction SilentlyContinue | ForEach-Object { $_.Source })
    foreach ($base in @($env:ProgramFiles,([Environment]::GetEnvironmentVariable('ProgramFiles(x86)')),$env:LOCALAPPDATA)) {
        if ($base) { $candidates += Join-Path $base 'Git/cmd/git.exe'; $candidates += Join-Path $base 'Programs/Git/cmd/git.exe' }
    }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (-not $candidate -or [IO.Path]::GetFullPath($candidate).StartsWith([IO.Path]::GetFullPath($Runtime),[StringComparison]::OrdinalIgnoreCase)) { continue }
        if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
        $version=(& $candidate --version 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -eq 0 -and $version -match '^git version ') { return [IO.Path]::GetFullPath($candidate) }
    }
    throw '未找到健康的 Git for Windows；请先安装 Git，再运行配置。'
}
# Framework CodeDOM builds a true console EXE that GUI clients can select.
function Build-JobsProxyShim {
    param([string]$Output)
    Add-Type -Path (Join-Path $PSScriptRoot 'GitShim.cs') -OutputAssembly $Output -OutputType ConsoleApplication -ErrorAction Stop
    [void][Reflection.AssemblyName]::GetAssemblyName($Output)
}
# Launchers prepend only their own process PATH, ahead of machine Git entries.
function New-JobsProxyStage {
    param([string]$Directory,[string]$RealGit,[string]$Hash)
    New-JobsProxyPrivateDirectory $Directory
    Build-JobsProxyShim (Join-Path $Directory 'git.exe')
    foreach ($name in @('Policy.ps1','NetworkPolicy.psm1')) { Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $Directory }
    [IO.File]::WriteAllText((Join-Path $Directory 'real-git.path'),$RealGit,[Text.Encoding]::UTF8)
    $cmd='@echo off'+[Environment]::NewLine+'set "PATH=%~dp0;%PATH%"'+[Environment]::NewLine+'cmd.exe /d /k'+[Environment]::NewLine
    $ps='@echo off'+[Environment]::NewLine+'set "PATH=%~dp0;%PATH%"'+[Environment]::NewLine+
        '"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NoExit'+[Environment]::NewLine
    [IO.File]::WriteAllText((Join-Path $Directory 'OpenGitCmd.cmd'),$cmd,[Text.Encoding]::ASCII)
    [IO.File]::WriteAllText((Join-Path $Directory 'OpenGitPowerShell.cmd'),$ps,[Text.Encoding]::ASCII)
    [IO.File]::WriteAllText((Join-Path $Directory 'owner.json'),(@{Owner=$script:ProxyOwner;SourceHash=$Hash}|ConvertTo-Json),[Text.Encoding]::UTF8)
}
# Compare both registry value and type before any restore writes.
function Test-JobsProxyPathEqual {
    param($Left,$Right)
    return ([bool]$Left.Exists -eq [bool]$Right.Exists -and [string]$Left.Kind -ceq [string]$Right.Kind -and [string]$Left.Value -ceq [string]$Right.Value)
}
# State contains exact binary maps, and never supplies arbitrary restore paths.
function Read-JobsProxyActive {
    param($Paths)
    if (-not (Test-Path -LiteralPath $Paths.Active)) { return $null }
    $item=Get-Item -LiteralPath $Paths.Active -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '安装状态不可信。' }
    $state=Import-Clixml -LiteralPath $Paths.Active
    if ($state.Owner -cne $script:ProxyOwner -or [string]$state.Snapshot -notmatch '^[0-9A-Za-z-]+$') { throw '安装状态身份不匹配。' }
    return $state
}
# Preserve a byte token so an unrelated state edit is never overwritten.
function Get-JobsProxyActiveToken {
    param($Paths)
    if (-not (Test-Path -LiteralPath $Paths.Active)) { return $null }
    $item=Get-Item -LiteralPath $Paths.Active -Force
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '安装状态不可信。' }
    return [Convert]::ToBase64String([IO.File]::ReadAllBytes($Paths.Active))
}
function Assert-JobsProxyActiveToken {
    param($Paths,$Expected)
    if ((Get-JobsProxyActiveToken $Paths) -cne $Expected) { throw '安装状态已有并发修改；停止，不覆盖。' }
}
# Serialize away from active, then replace it atomically after the concurrency check.
function Write-JobsProxyActive {
    param($Paths,$State,$Expected)
    $temporary=$Paths.Active+'.new-'+[guid]::NewGuid().ToString('N')
    try {
        $State | Export-Clixml -LiteralPath $temporary -Depth 12
        Assert-JobsProxyActiveToken $Paths $Expected
        if ($null -eq $Expected) { [IO.File]::Move($temporary,$Paths.Active) }
        else { [IO.File]::Replace($temporary,$Paths.Active,[NullString]::Value) }
    } finally { if (Test-Path -LiteralPath $temporary) { [IO.File]::Delete($temporary) } }
}
# A restored upgrade leaves the previous active version in place; do not treat it as unknown.
function Get-JobsProxyEffectiveState {
    param($State)
    $visited=0
    while ($null -ne $State -and $State.Restored) {
        $visited++
        if ($visited -gt 100) { throw '恢复链异常，停止。' }
        $State=$State.Previous
    }
    if ($null -ne $State -and $State.Owner -cne $script:ProxyOwner) { throw '历史状态身份不匹配。' }
    return $State
}
# Exact maps detect modified or extra runtime files.
function Test-JobsProxyFileMapEqual {
    param($Left,$Right)
    if ($Left.Count -ne $Right.Count) { return $false }
    foreach ($name in $Left.Keys) { if (-not $Right.ContainsKey($name) -or $Left[$name] -cne $Right[$name]) { return $false } }
    return $true
}
# Validate all managed fields together before any change.
function Assert-JobsProxyCurrent {
    param($Paths,$State)
    if (-not (Test-JobsProxyPathEqual (Read-JobsProxyUserPath) $State.AfterPath)) { throw '用户 PATH 已有后续修改；停止，不覆盖。' }
    if (-not (Test-JobsProxyFileMapEqual (Get-JobsProxyRuntimeFiles $Paths.Bin) $State.AfterFiles)) { throw '运行态已有后续修改；停止，不覆盖。' }
}
# A failed install may contain either before or after bytes, but never overwrite a concurrent third value.
function Assert-JobsProxyPartialState {
    param($Paths,$State)
    $path=Read-JobsProxyUserPath
    if (-not (Test-JobsProxyPathEqual $path $State.BeforePath) -and -not (Test-JobsProxyPathEqual $path $State.AfterPath)) { throw 'PATH 并发变化，保留快照。' }
    $files=Get-JobsProxyRuntimeFiles $Paths.Bin
    foreach ($name in $files.Keys) {
        $value=$files[$name]
        if ((-not $State.BeforeFiles.ContainsKey($name) -or $State.BeforeFiles[$name] -cne $value) -and
            (-not $State.AfterFiles.ContainsKey($name) -or $State.AfterFiles[$name] -cne $value)) { throw '运行态并发变化，保留快照。' }
    }
}
# Write or delete only known files in the private runtime.
function Set-JobsProxyRuntimeFiles {
    param([string]$Directory,$Files)
    New-JobsProxyPrivateDirectory $Directory
    $current=Get-JobsProxyRuntimeFiles $Directory
    foreach ($name in $current.Keys) { if (-not $Files.ContainsKey($name)) { [IO.File]::Delete((Join-Path $Directory $name)) } }
    foreach ($name in $Files.Keys) {
        if ($name -notin @('git.exe','Policy.ps1','NetworkPolicy.psm1','real-git.path','OpenGitCmd.cmd','OpenGitPowerShell.cmd','owner.json')) { throw '快照包含未知文件名。' }
        $path=Join-Path $Directory $name; $temporary=$path+'.new-'+[guid]::NewGuid().ToString('N')
        [IO.File]::WriteAllBytes($temporary,[Convert]::FromBase64String($Files[$name]))
        try { Move-Item -LiteralPath $temporary -Destination $path -Force } finally { if (Test-Path -LiteralPath $temporary) { [IO.File]::Delete($temporary) } }
    }
}
# Audit excludes original PATH, filesystem arguments and Git credentials.
function Write-JobsProxyInstallAudit {
    param($Paths,[string]$Action,[string]$Result)
    $line=('{0} action={1} result={2}' -f [DateTime]::UtcNow.ToString('o'),$Action,$Result)
    try { [IO.File]::AppendAllText($Paths.Log,$line+[Environment]::NewLine,[Text.Encoding]::UTF8) }
    catch { Write-Warning '配置已完成，但安装审计记录写入失败；请检查配置目录权限。' }
}
# Only an explicit configurator action installs the global user entry.
function Install-JobsGitProxy {
    $paths=Get-JobsProxyPaths; $activeToken=Get-JobsProxyActiveToken $paths
    $previous=Get-JobsProxyEffectiveState (Read-JobsProxyActive $paths); $hash=Get-JobsProxySourceHash
    if ($previous -and -not $previous.Restored) {
        Assert-JobsProxyCurrent $paths $previous
        if ($previous.SourceHash -ceq $hash) { Write-Host '当前版本及配置已完整安装，无需重复修改。'; return $previous }
    } elseif ((Get-JobsProxyRuntimeFiles $paths.Bin).Count) { throw '存在未知同名运行态，停止覆盖。' }
    $real=Find-JobsProxyRealGit $paths.Bin
    New-JobsProxyPrivateDirectory $paths.Root
    New-JobsProxyPrivateDirectory $paths.Snapshots
    $number=[DateTime]::UtcNow.ToString('yyyyMMddTHHmmss')+'-'+[guid]::NewGuid().ToString('N')
    $stage=Join-Path $paths.Root ('stage-'+$number)
    try {
        New-JobsProxyStage $stage $real $hash
        $beforePath=Read-JobsProxyUserPath
        $afterPath=@{Exists=$true;Kind=$beforePath.Kind;Value=($paths.Bin+';'+[string]$beforePath.Value)}
        $state=@{Owner=$script:ProxyOwner;Snapshot=$number;Restored=$false;SourceHash=$hash;BeforePath=$beforePath;AfterPath=$afterPath;
            BeforeFiles=(Get-JobsProxyRuntimeFiles $paths.Bin);AfterFiles=(Get-JobsProxyRuntimeFiles $stage);Previous=$previous}
        $state | Export-Clixml -LiteralPath (Join-Path $paths.Snapshots ($number+'.clixml')) -Depth 12
        Assert-JobsProxyActiveToken $paths $activeToken
        if ($previous -and -not $previous.Restored) { Assert-JobsProxyCurrent $paths $previous }
        elseif (-not (Test-JobsProxyPathEqual (Read-JobsProxyUserPath) $beforePath)) { throw '用户 PATH 在配置期间变化，停止。' }
        try {
            Set-JobsProxyRuntimeFiles $paths.Bin $state.AfterFiles
            Write-JobsProxyUserPath $state.AfterPath
            Write-JobsProxyActive $paths $state $activeToken
        } catch {
            $failure=$_
            try {
                Assert-JobsProxyPartialState $paths $state
                Set-JobsProxyRuntimeFiles $paths.Bin $state.BeforeFiles
                Write-JobsProxyUserPath $state.BeforePath
            } catch {
                Write-Warning '安装失败且存在未能安全撤回的状态；已保留快照，不强制覆盖。'
            }
            throw $failure
        }
        Write-JobsProxyInstallAudit $paths 'install' 'applied'
        Write-Host ('Git 动态入口：'+(Join-Path $paths.Bin 'git.exe'))
        Write-Host '当前会话不会更新；新终端仍可能继承旧环境。请优先使用 OpenGitCmd.cmd / OpenGitPowerShell.cmd，并用 C 核对实际路径。'
        Write-Host 'Sourcetree 请保存工作并退出后，将 System Git 指向上述真实 git.exe；本工具不修改不确定的应用偏好。'
        return $state
    } finally { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force } }
}
# Read-only checks do not build, create directories or write audit.
function Test-JobsGitProxyInstallation {
    $paths=Get-JobsProxyPaths; $state=Get-JobsProxyEffectiveState (Read-JobsProxyActive $paths)
    if (-not $state) { Write-Host '当前没有生效中的 Git 动态配置。'; return $false }
    Assert-JobsProxyCurrent $paths $state
    $real=[IO.File]::ReadAllText((Join-Path $paths.Bin 'real-git.path'),[Text.Encoding]::UTF8).Trim()
    if (-not (Test-Path -LiteralPath $real -PathType Leaf)) { throw '原始 Git 路径已失效，请先恢复再重新配置。' }
    Write-Host ('配置完整；真实 shim：'+(Join-Path $paths.Bin 'git.exe'))
    $resolved=Get-Command git.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($resolved) { Write-Host ('当前进程解析的 Git：'+$resolved.Source) }
    Write-Host 'PATH 与应用选择不等于联网成功；Windows 桌面和远端需另行验证。'
    return $true
}
# Restore the latest operation once, preserving original absence, type and value.
function Restore-JobsGitProxy {
    $paths=Get-JobsProxyPaths; $activeToken=Get-JobsProxyActiveToken $paths; $state=Read-JobsProxyActive $paths
    if (-not $state -or $state.Restored) { Write-Host '没有需要恢复的最新配置。'; return }
    Assert-JobsProxyCurrent $paths $state
    Assert-JobsProxyActiveToken $paths $activeToken
    try {
        Set-JobsProxyRuntimeFiles $paths.Bin $state.BeforeFiles
        Write-JobsProxyUserPath $state.BeforePath
        $state.Restored=$true
        Write-JobsProxyActive $paths $state $activeToken
    } catch {
        $failure=$_
        try {
            Assert-JobsProxyPartialState $paths $state
            Set-JobsProxyRuntimeFiles $paths.Bin $state.AfterFiles
            Write-JobsProxyUserPath $state.AfterPath
        } catch { Write-Warning '恢复失败且存在不能安全回滚的状态；快照仍保留，不强制覆盖。' }
        throw $failure
    }
    Write-JobsProxyInstallAudit $paths 'restore' 'restored'
    Write-Host '已精确恢复最新配置前的用户 PATH 与运行态；现有进程仍可能保留旧环境，需刷新环境或重新登录；Sourcetree 请恢复原 Git 选择。'
}
Export-ModuleMember -Function Install-JobsGitProxy, Test-JobsGitProxyInstallation, Restore-JobsGitProxy
