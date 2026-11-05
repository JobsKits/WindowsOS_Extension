# FlutterProjectToolchains.Tests.ps1 | 平台工具链缺失、修复、复检与取消的隔离回归。
# Created by Jobs on 2026年11月4日，星期三.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tempBase = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {[IO.Path]::GetTempPath()} else {'/private/tmp'}
$temp = Join-Path $tempBase ('JobsToolchainTest-'+[guid]::NewGuid().ToString('N'))
$count = 0
function Assert($Value,[string]$Message) { $script:count++; if (-not $Value) { throw $Message } }
function Assert-Throws([scriptblock]$Body,[string]$Message) { $threw=$false;try{& $Body|Out-Null}catch{$threw=$true};Assert $threw $Message }
function Fixture-File([string]$Path) { [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path));[IO.File]::WriteAllText($Path,'fixture') }
[void][IO.Directory]::CreateDirectory($temp)
$module = Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetup.psm1') -PassThru -DisableNameChecking
$saved = & $module { Get-JobsSetupEnvironmentSnapshot @('PATH','JAVA_HOME','GRADLE_OPTS','DEVECO_STUDIO_HOME','TOOL_HOME','DEVECO_SDK_HOME','LOCALAPPDATA','ProgramFiles(x86)') }
try {
    $project = Join-Path $temp '项目 空格'
    Fixture-File (Join-Path $project 'lib/main.dart')
    [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'),"name: fixture`ndependencies:`n  flutter:`n    sdk: flutter`n")
    $flutter = [pscustomobject]@{Mode='system';Flutter='fixture-flutter'}
    & $module {param($p,$f)Save-JobsSetupProfile $p $f $null} $project $flutter
    $profile = & $module {param($p)Get-JobsSetupProfile $p} $project
    Assert ($profile.JavaMode -ceq 'none' -and $profile.JavaHome -ceq '') '无 Java 的平台配置可正常保存和重读'
    $java = [pscustomobject]@{Mode='system';Home='old-android-java'}
    & $module {param($p,$f,$j)Save-JobsSetupProfile $p $f $j;Save-JobsSetupProfile $p $f $null} $project $flutter $java
    $profile = & $module {param($p)Get-JobsSetupProfile $p} $project
    Assert ($profile.JavaHome -ceq 'old-android-java') 'Web 保存不会抹掉已选 Android JDK'

    # 外部运行边界全用替身，Web / Windows / Ohos 不进入无关 Java 选择器。
    & $module {
        param($base)
        $script:fixture=$base;$script:events=New-Object 'System.Collections.Generic.List[string]'
        function script:Test-JobsSetupInteractive {$true}
        function script:Read-Host {param($Prompt) ''}
        function script:Get-JobsInstallRoot {$script:fixture}
        function script:Get-JobsSetupFzf {param($p) 'fixture-fzf'}
        function script:Select-JobsSetupPlatform {param($p,$f)$script:platform}
        function script:Select-JobsSetupFlutter {param($p,$f,$t)[pscustomobject]@{Mode='system';Flutter='fixture';Root='fixture'}}
        function script:Select-JobsSetupJava {throw 'unexpected Java installation'}
        function script:Initialize-JobsSetupPlatform {param($p,$f,$j,$z,$t)if($null-ne$j){throw 'irrelevant Java passed'};$script:events.Add('platform')}
        function script:Invoke-JobsSetupDependencies {param($p,$f,$g)$script:events.Add('pub')}
        function script:Invoke-JobsSetupTargetDependencies {param($p,$f,$j,$z,$t,$g)$script:events.Add('target');return ,@('build','web','--debug')}
        function script:Get-JobsSetupReadiness {param($p,$f)[pscustomobject]@{Ready=$true}}
        function script:Invoke-JobsSetupRunVerification {param($p,$f,$z,$t,$a)$script:events.Add('run')}
    } $temp
    foreach ($platform in @('Web','Windows','Ohos')) {
        & $module {param($p)$script:platform=$p;$script:events.Clear()} $platform
        & $module {param($p)Invoke-JobsProjectSetupAction $p 'project-setup'} $project
        Assert ((& $module {$script:events -join ','}) -ceq 'platform,pub,target,run') ($platform+' 不要求或使用无关 Java，仍完成后续流程')
    }
    Remove-Module $module
    $module=Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetup.psm1') -PassThru -DisableNameChecking
    & $module {
        param($base)
        $script:fixture=$base;$script:managerVersion='4.5.0';$script:failEngine=$false;$script:failRepair=$false;$script:installs=0;$script:choices=0
        function script:Get-JobsInstallRoot {$script:fixture}
        function script:Find-JobsExecutable {param($Name,$Candidates)Join-Path $script:fixture ('fixture-'+$Name)}
        function script:Invoke-JobsSetupProcess {
            param($File,$Arguments,$Directory,$TimeoutSeconds)
            if($Arguments[0]-ceq'-e'){if($script:failEngine){throw 'Node engine mismatch'};$out='JOBS_NODE_ENGINE_OK'}
            elseif($File-match'node.exe$'){$out='v22.1.0'}else{$out=$script:managerVersion}
            [pscustomobject]@{ExitCode=0;StdOut=$out;StdErr=''}
        }
        function script:Get-JobsSetupFzf {param($p)'fixture-fzf'}
        function script:Select-JobsSetupChoice {param($Fzf,$Title,$Choices)$script:choices++;if($script:cancel){throw 'fixture cancel'};$Choices[1]}
        function script:Install-JobsSetupWebManager {param($p,$m,$v)$script:installs++;if(-not$script:failRepair){$script:managerVersion=$v}}
        function script:Install-JobsSetupWebNode {throw 'unexpected Node installation'}
        $script:cancel=$false
    } $temp
    $manifest='{"packageManager":"yarn@4.5.0","engines":{"node":">=20 <23"}}'|ConvertFrom-Json
    $tools=& $module {param($p,$m)Initialize-JobsSetupWebTools $p $m 'yarn'} $project $manifest
    Assert ($tools.Version -ceq '4.5.0' -and (& $module {$script:choices}) -eq 0) '健康 Node 与锁定管理器直接复用，不安装'
    & $module {$script:managerVersion='1.22.22'}
    $tools=& $module {param($p,$m)Initialize-JobsSetupWebTools $p $m 'yarn'} $project $manifest
    Assert ($tools.Version -ceq '4.5.0' -and (& $module {$script:installs}) -eq 1) '管理器版本不符经选择安装精确版本并复检'
    & $module {$script:managerVersion='1.22.22';$script:failRepair=$true}
    Assert-Throws {& $module {param($p,$m)Initialize-JobsSetupWebTools $p $m 'yarn'} $project $manifest} '安装后版本仍不匹配时停止'
    & $module {$script:failRepair=$false;$script:cancel=$true;$script:installs=0}
    Assert-Throws {& $module {param($p,$m)Initialize-JobsSetupWebTools $p $m 'yarn'} $project $manifest} '工具修复选择取消传播'
    Assert ((& $module {$script:installs}) -eq 0) '取消不执行管理器安装'
    & $module {$script:cancel=$false;$script:managerVersion='4.5.0';$script:failEngine=$true}
    Assert-Throws {& $module {param($p,$m)Initialize-JobsSetupWebTools $p $m 'yarn'} $project $manifest} 'Node engines 不满足时不能靠安装管理器冒充健康'
    [IO.File]::WriteAllText((Join-Path $project '.node-version'),'22.1.0')
    $constraints=@(& $module {param($p,$m)Get-JobsSetupNodeConstraints $p $m} $project $manifest)
    Assert ($constraints.Count -eq 2 -and $constraints -ccontains '22.1.0') '读取 engines 和版本文件共同约束'
    [IO.File]::WriteAllText((Join-Path $project '.node-version'),'lts/*')
    Assert-Throws {& $module {param($p,$m)Get-JobsSetupNodeConstraints $p $m} $project $manifest} '不能确认的 Node 别名停止，不盲装 latest'
    [IO.File]::Delete((Join-Path $project '.node-version'))
    $nodeArch=if($env:PROCESSOR_ARCHITECTURE-ceq'ARM64'-or$env:PROCESSOR_ARCHITEW6432-ceq'ARM64'){'arm64'}else{'x64'}
    $cachedNode=Join-Path $temp ('toolchains/node-22.1.0-'+$nodeArch+'/sdk/node-v22.1.0-win-'+$nodeArch+'/node.exe')
    Fixture-File $cachedNode
    Fixture-File (Join-Path (Split-Path -Parent $cachedNode) 'npm.cmd')
    & $module {
        $script:failEngine=$false
        function script:Find-JobsExecutable {param($Name,$Candidates)if($Name-cne'node.exe'){Join-Path $script:fixture ('fixture-'+$Name)}}
    }
    $cached=& $module {param($p)Get-JobsSetupWebNode $p @('>=20 <23')} $project
    Assert ($cached.Node -ceq $cachedNode) '新进程 PATH 无 Node 时发现并复用上轮匹配架构的工具缓存'
    [IO.Directory]::Delete((Join-Path $temp ('toolchains/node-22.1.0-'+$nodeArch)),$true)


    Remove-Module $module
    $module=Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetup.psm1') -PassThru -DisableNameChecking
    & $module {
        param($base)
        $script:fixture=$base;$script:calls=New-Object 'System.Collections.Generic.List[string]';$script:installedVersion=''
        function script:Get-JobsInstallRoot {$script:fixture}
        function script:Find-JobsExecutable {param($Name,$Candidates)Join-Path $script:fixture ('fixture-'+$Name)}
        function script:Invoke-JobsSetupProcess {
            param($File,$Arguments,$Directory,$TimeoutSeconds)
            $script:calls.Add($File+'|'+($Arguments -join '|'))
            if($Arguments[0]-ceq'install'){
                $prefix=$Arguments[[array]::IndexOf($Arguments,'--prefix')+1];[IO.File]::WriteAllText((Join-Path $prefix 'yarn.cmd'),'fixture')
                $script:installedVersion=($Arguments[-1]-split'@')[-1]
            }
            $out=if($Arguments[0]-ceq'config'){'https://registry.npmjs.org/'}elseif($script:installedVersion){$script:installedVersion}else{'10.8.0'}
            [pscustomobject]@{ExitCode=0;StdOut=$out;StdErr=''}
        }
    } $temp
    & $module {param($p)Install-JobsSetupWebManager $p 'yarn' '4.5.0'} $project
    $calls=& $module {$script:calls -join ';'}
    Assert ($calls -match '@yarnpkg/cli-dist@4.5.0' -and $calls -match '--global\|--prefix\|') '现代 Yarn 用 cli-dist 精确包，安装仅指向独立用户 prefix'
    Assert ($calls -notmatch '@latest') '安装命令没有 latest 标签'
    & $module {
        function script:Invoke-JobsSetupProcess {param($File,$Arguments,$Directory,$TimeoutSeconds)$out=if($File.EndsWith('node.exe')){'v22.1.0'}else{'4.5.0'};[pscustomobject]@{ExitCode=0;StdOut=$out;StdErr=''}}
    }
    $tools=& $module {param($p)Get-JobsSetupWebTools $p 'yarn' '4.5.0' @()} $project
    Assert ($tools.Tool -ceq (Join-Path $temp 'toolchains/js-yarn-4.5.0/yarn.cmd')) '精确 packageManager 自动发现独立用户 prefix，后续进程不强制重装'


    Remove-Module $module
    $module=Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetup.psm1') -PassThru -DisableNameChecking
    & $module {
        param($base)
        $script:fixture=$base;$script:downloadCalls=0;$script:expands=0;$script:badHash=$false;$script:nodeAnswer='22.1.0';$script:nodeVersion='v22.1.0';$script:failNodeConstraint=$false
        function script:Get-JobsInstallRoot {$script:fixture}
        function script:Read-JobsSetupInput {param($p,$n)$script:nodeAnswer}
        function script:Get-JobsSetupWebNode {param($p,$c)if($script:failNodeConstraint){throw 'fixture Node engines mismatch'};[pscustomobject]@{Node='fixture-node';Version='22.1.0'}}
        function script:Invoke-JobsSetupProcess {param($File,$Arguments,$Directory,$TimeoutSeconds)$out=if($File.EndsWith('node.exe')){$script:nodeVersion}else{'10.8.0'};[pscustomobject]@{ExitCode=0;StdOut=$out;StdErr=''}}
        function script:Receive-JobsSetupFile {
            param($Urls,$Destination,$TimeoutSeconds)
            $script:downloadCalls++
            if($Destination.EndsWith('SHASUMS256.txt')){
                $bytes=[Text.Encoding]::UTF8.GetBytes('fixture-node-zip');$hash=[Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
                $checksum=([BitConverter]::ToString($hash)).Replace('-','').ToLowerInvariant();if($script:badHash){$checksum='0'*64}
                $arch=if($env:PROCESSOR_ARCHITECTURE-ceq'ARM64'-or$env:PROCESSOR_ARCHITEW6432-ceq'ARM64'){'arm64'}else{'x64'}
                [IO.File]::WriteAllText($Destination,($checksum+'  node-v22.1.0-win-'+$arch+'.zip'))
            }else{[IO.File]::WriteAllText($Destination,'fixture-node-zip')}
            $Urls[0]
        }
        function script:Expand-JobsSetupZip {
            param($Archive,$Destination)
            $script:expands++;$name=[IO.Path]::GetFileNameWithoutExtension($Archive);$bin=Join-Path $Destination $name
            [void][IO.Directory]::CreateDirectory($bin)
            foreach($file in @('node.exe','npm.cmd')){[IO.File]::WriteAllText((Join-Path $bin $file),'fixture')}
        }
    } $temp
    & $module {param($p)Install-JobsSetupWebNode $p @('>=20 <23')} $project
    Assert ((& $module {$script:downloadCalls}) -eq 2 -and (& $module {$script:expands}) -eq 1) 'Node 官方校验清单与归档分别获取，SHA 通过才解压'
    Assert ($env:PATH -match 'node-22.1.0' -and $env:PATH -match 'sdk[/\\]node-v22.1.0') 'Node 安装后仅刷新进程 PATH 到本轮精确版本'
    & $module {param($p)Install-JobsSetupWebNode $p @()} $project
    Assert ((& $module {$script:downloadCalls}) -eq 2 -and (& $module {$script:expands}) -eq 1) '重复准备精确 Node 版本直接复用健康缓存，不重复下载解压'
    $nodeBin=($env:PATH -split [regex]::Escape([string][IO.Path]::PathSeparator))[0]
    [IO.File]::Delete((Join-Path $nodeBin 'npm.cmd'))
    & $module {$script:badHash=$true;$script:expands=0}
    Assert-Throws {& $module {param($p)Install-JobsSetupWebNode $p @()} $project} 'Node 摘要不符停止'
    Assert ((& $module {$script:expands}) -eq 0) '摘要不符不解压不执行下载载荷'
    & $module {$script:badHash=$false;$script:nodeVersion='v22.2.0'}
    Assert-Throws {& $module {param($p)Install-JobsSetupWebNode $p @()} $project} '解压后 Node 实际版本错误时精确复检阻断'
    & $module {$script:nodeVersion='v22.1.0';$script:failNodeConstraint=$true}
    Assert-Throws {& $module {param($p)Install-JobsSetupWebNode $p @('>=24')} $project} '已安装的精确 Node 不符合项目 engines 也不得通过'
    & $module {$script:nodeAnswer='';$script:downloadCalls=0}
    Assert-Throws {& $module {param($p)Install-JobsSetupWebNode $p @()} $project} 'Node 选版空输入取消'
    Assert ((& $module {$script:downloadCalls}) -eq 0) 'Node 选版取消不联网'

    Remove-Module $module
    $module=Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetup.psm1') -PassThru -DisableNameChecking
    ${env:ProgramFiles(x86)}=Join-Path $temp 'ProgramFiles'
    $vs=Join-Path ${env:ProgramFiles(x86)} 'VS'
    Fixture-File (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe')
    Fixture-File (Join-Path $vs 'VC/Tools/MSVC/14.40.1/bin/Hostx64/x64/cl.exe')
    Fixture-File (Join-Path $vs 'VC/Tools/MSVC/14.40.1/bin/Hostarm64/arm64/cl.exe')
    & $module {
        param($p)
        $script:vs=$p;$script:failCmake=$false;$script:repairCount=0;$script:completed=0
        function script:Invoke-JobsSetupProcess {
            param($File,$Arguments,$Directory,$TimeoutSeconds)
            if($File-match'cmake.exe$'){if($script:failCmake){throw 'broken CMake'};$out='cmake version 3.30.1'}
            elseif($Arguments-contains'installationVersion'){$out='17.11.0'}else{$out=$script:vs}
            [pscustomobject]@{ExitCode=0;StdOut=$out;StdErr=''}
        }
        function script:Set-JobsSetupProgress {param($Node,$State,$Detail,$Version)if($State-ceq'done'){$script:completed++}}
        function script:Select-JobsSetupChoice {param($Fzf,$Title,$Choices)$Choices[1]}
    } $vs
    $tools=& $module {param($p)Get-JobsSetupWindowsDesktopTools $p} $project
    Assert (-not $tools.Ready -and ($tools.Issues -join ',') -match 'CMake|cmake' -and ($tools.Issues -join ',') -match 'Windows SDK') 'VC 存在但 SDK/CMake 缺失时不健康'
    Assert-Throws {& $module {param($p)Initialize-JobsSetupWindowsDesktop $p 'fixture-fzf'} $project} '手动处理后复检仍缺工具即停止'
    Assert ((& $module {$script:completed}) -eq 0) '工具链未健康不能发出完成状态'
    Fixture-File (Join-Path $vs 'Common7/IDE/CommonExtensions/Microsoft/CMake/CMake/bin/cmake.exe')
    $arch=if($env:PROCESSOR_ARCHITECTURE-ceq'ARM64'-or$env:PROCESSOR_ARCHITEW6432-ceq'ARM64'){'arm64'}else{'x64'}
    $sdk=Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10'
    foreach($file in @('Include/10.0.26100.0/um/Windows.h','Include/10.0.26100.0/shared/sdkddkver.h','Include/10.0.26100.0/ucrt/stdio.h',('Lib/10.0.26100.0/um/'+$arch+'/kernel32.lib'),('Lib/10.0.26100.0/ucrt/'+$arch+'/ucrt.lib'),('bin/10.0.26100.0/'+$arch+'/rc.exe'))){Fixture-File (Join-Path $sdk $file)}
    $tools=& $module {param($p)Get-JobsSetupWindowsDesktopTools $p} $project
    Assert ($tools.Ready -and $tools.VersionText -match '10.0.26100.0.*3.30.1') '完整 VC、SDK 头库/资源工具及真实 CMake 探针才通过'
    & $module {$script:failCmake=$true}
    $tools=& $module {param($p)Get-JobsSetupWindowsDesktopTools $p} $project
    Assert (-not $tools.Ready) '存在但不能运行的 CMake 不健康'
    [IO.File]::Delete((Join-Path $sdk ('bin/10.0.26100.0/'+$arch+'/rc.exe')))
    & $module {$script:failCmake=$false}
    $tools=& $module {param($p)Get-JobsSetupWindowsDesktopTools $p} $project
    Assert (-not $tools.Ready) 'SDK 仅有头文件和库、缺 rc.exe 也不能通过'
    Fixture-File (Join-Path $sdk ('bin/10.0.26100.0/'+$arch+'/rc.exe'))
    Fixture-File (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/setup.exe')
    $worker=Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/Actions/sdk-manage/Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $worker {function script:Update-JobsFvmSessionPath {}}
    & $module {
        $script:repairArguments=@()
        function script:Invoke-JobsSdkAcquire {param($Label,$Operation)& $Operation}
        function script:Invoke-JobsSetupProcessOnce {param($File,$Arguments,$Directory,$TimeoutSeconds,[switch]$SdkAcquisitionAttempt,[switch]$AllowInstallerExitCodes)$script:repairArguments=@($File)+$Arguments;[pscustomobject]@{ExitCode=0;StdOut='';StdErr=''}}
    }
    & $module {param($p,$t)Install-JobsSetupWindowsDesktopTools $p $t} $project $tools
    $arguments=@(& $module {$script:repairArguments})
    Assert ($arguments -ccontains 'modify' -and $arguments -ccontains $vs) '已有 VS 实例通过官方 Installer modify 修复，避免 winget 已安装后直接跳过'
    Assert ($arguments -ccontains 'Microsoft.VisualStudio.Component.VC.CMake.Project' -and $arguments -ccontains 'Microsoft.VisualStudio.Component.Windows11SDK.26100') 'VS 修复命令明确补 CMake 与 Windows SDK'

    Remove-Module $module
    $module=Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetup.psm1') -PassThru -DisableNameChecking
    foreach($name in @('oh-package.json5','hvigor/hvigor-config.json5','hvigorw.bat')){Fixture-File (Join-Path $project ('ohos/'+$name))}
    & $module {
        param($base)
        $script:fixture=$base;$script:attempts=0;$script:done=0;$script:failAgain=$false
        function script:Get-JobsSetupOhosTools {param($p)$script:attempts++;if($script:attempts-eq1-or$script:failAgain){throw 'missing DevEco SDK'};[pscustomobject]@{Ohpm='fixture-ohpm';Wrapper='fixture-wrapper';VersionText='fixture versions'}}
        function script:Get-JobsSetupFzf {param($p)'fixture-fzf'}
        function script:Select-JobsSetupChoice {param($Fzf,$Title,$Choices)$Choices[0]}
        function script:Read-JobsSetupInput {param($p,$n)''}
        function script:Set-JobsSetupProgress {param($Node,$State,$Detail,$Version)if($State-ceq'done'){$script:done++}}
    } $temp
    $tools=& $module {param($p)Initialize-JobsSetupOhos $p 'fixture-fzf'} $project
    Assert ($tools.Ohpm-ceq'fixture-ohpm' -and (& $module {$script:attempts}) -eq 2) 'OHOS 缺失经目录引导后完整二次复检'
    & $module {$script:attempts=0;$script:done=0;$script:failAgain=$true}
    Assert-Throws {& $module {param($p)Initialize-JobsSetupOhos $p 'fixture-fzf'} $project} 'OHOS 二次复检失败阻断'
    Assert ((& $module {$script:done}) -eq 0) 'OHOS 缺失不再标记工具链完成'
    & $module {function script:Select-JobsSetupChoice {param($Fzf,$Title,$Choices)$Choices[2]};$script:attempts=0}
    Assert-Throws {& $module {param($p)Initialize-JobsSetupOhos $p 'fixture-fzf'} $project} 'OHOS 用户停止传播，不运行依赖同步'
    Assert ((& $module {$script:attempts}) -eq 1) '取消无下游二次执行'

    Write-Host ('PASS: FlutterProjectToolchains.Tests.ps1 ('+$count+' assertions; mocked tools only, no installs/downloads/builds/registry)')
} finally {
    & $module {param($s)Restore-JobsSetupEnvironment $s} $saved
    Remove-Module $module
    if([IO.Directory]::Exists($temp)){[IO.Directory]::Delete($temp,$true)}
}
