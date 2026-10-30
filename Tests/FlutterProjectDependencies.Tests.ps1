# FlutterProjectDependencies.Tests.ps1 | 分层依赖、取消与真实解析门禁隔离回归。
# Created by Jobs on 2026年10月29日，星期四.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$count = 0
function Assert($Value,[string]$Message) { $script:count++; if (-not $Value) { throw $Message } }
function Assert-Throws([scriptblock]$Body,[string]$Message) { $failed=$false; try { & $Body | Out-Null } catch { $failed=$true }; Assert $failed $Message }
$base = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { [IO.Path]::GetTempPath() } else { '/private/tmp' }
$temp = Join-Path $base ('jobs-dependency-layers-' + [guid]::NewGuid().ToString('N'))
$project = Join-Path $temp '项目 空格 & $literal'
[void][IO.Directory]::CreateDirectory((Join-Path $project 'lib'))
[IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'),"name: fixture`ndependencies:`n  flutter:`n    sdk: flutter`n")
$module = Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetup.psm1') -PassThru -DisableNameChecking
try {
    & $module {
        param($base)
        $script:fixture = $base
        $script:calls = New-Object 'System.Collections.Generic.List[string]'
        $script:fixtureResult = ''
        $script:failCommand = ''
        $script:cancel = $false
        function script:Invoke-JobsSetupProcess {
            param($File,[string[]]$Arguments,$Directory,$TimeoutSeconds)
            $command = $Arguments -join ' '
            $script:calls.Add($File+'|'+$command+'|'+$Directory)
            if ($script:failCommand -and $command.StartsWith($script:failCommand)) { throw 'fixture command failure' }
            $output = switch -Regex ($command) {
                '^jobsResolveDependencyArtifacts' { if($script:fixtureResult){$script:fixtureResult}else{'JOBS_ARTIFACTS_RESOLVED|3'}; break }
                '^precache --help$' { '--[no-]android --[no-]windows --[no-]web --[no-]ohos'; break }
                '^build .+ --help$' { 'flutter '+($command -replace ' --help$',''); break }
                '^--help$' { '--sync Synchronize project dependencies'; break }
                '^--version$' { '9.1.0'; break }
                default { 'fixture success' }
            }
            return [pscustomobject]@{ExitCode=0;StdOut=$output;StdErr=''}
        }
        function script:Find-JobsExecutable { param($Name,$Candidates) 'tool-'+$Name }
        function script:Get-JobsInstallRoot { $script:fixture }
        function script:Test-JobsSetupInteractive { $true }
        function script:Read-Host { param($Prompt) if($script:cancel){'cancel'}else{''} }
        function script:Read-JobsSetupInput { param($Prompt,$Node) Read-Host $Prompt }
        function script:Get-JobsSetupFzf { param($p) $script:calls.Add('fzf'); 'fixture-fzf' }
        function script:Get-JobsDependencyFlutter { param($p,$f) $script:calls.Add('flutter-health'); [pscustomobject]@{Mode='fvm';Flutter='flutter.bat';Dart='dart.exe';Root='fixture-sdk'} }
        function script:Get-JobsDependencyJava { param($p,$f) $script:calls.Add('java-health'); [pscustomobject]@{Mode='system';Home='fixture-java';Major=17} }
        function script:Set-JobsSetupJavaProcess { param($p,$j) $script:calls.Add('java-bind'); $env:GRADLE_OPTS='fixture-changed' }
        function script:Initialize-JobsSetupAndroid { param($p,$f,$j,$z) $script:calls.Add('android-tools') }
        function script:Initialize-JobsSetupWindowsDesktop { param($p,$z) $script:calls.Add('windows-tools') }
        function script:Install-JobsSetupGradle { param($p,$j,$z) $script:calls.Add('gradle-wrapper'); 'gradlew.bat' }
        function script:Select-JobsSetupChoice { param($Fzf,$Title,$Choices,$Back) $Choices[0] }
    } $temp

    $before = @(Get-ChildItem -LiteralPath $temp -Recurse -Force | ForEach-Object FullName)
    & $module { param($p) Invoke-JobsProjectDependencyAction $p android-dependencies -Check } $project
    Assert ((& $module { $script:calls.Count }) -eq 0) 'Check 不调用命令、选择器或 SDK'
    Assert ((@(Get-ChildItem -LiteralPath $temp -Recurse -Force | ForEach-Object FullName) -join '|') -ceq ($before -join '|')) 'Check 不写文件'
    & $module { $script:cancel=$true }
    Assert-Throws { & $module { param($p) Invoke-JobsProjectDependencyAction $p pub-get } $project } '初始取消传播'
    Assert ((& $module { $script:calls.Count }) -eq 0) '取消无 SDK/下载副作用'
    & $module { $script:cancel=$false }
    & $module { param($p) Invoke-JobsProjectDependencyAction $p pub-get } $project
    $calls = @(& $module { $script:calls.ToArray() })
    Assert ($calls.Count -eq 2 -and $calls[0] -ceq 'flutter-health' -and $calls[1] -like '*|pub get|*') 'Pub 只检查 SDK 并获取 Pub，不调用其它平台或 fzf'
    & $module { $script:calls.Clear(); $script:failCommand='pub get' }
    Assert-Throws { & $module { param($p) Invoke-JobsProjectDependencyAction $p pub-get } $project } 'Pub 失败传播'
    & $module { $script:failCommand=''; $script:calls.Clear() }
    & $module { param($p) Invoke-JobsProjectDependencyAction $p web-dependencies } $project
    Assert ((& $module { $script:calls.Count }) -eq 0) '无 package.json 的 Web 不安装 Node 或 SDK'

    [void][IO.Directory]::CreateDirectory((Join-Path $project 'android'))
    $savedOpts = [Environment]::GetEnvironmentVariable('GRADLE_OPTS','Process')
    & $module { param($p) Invoke-JobsProjectDependencyAction $p android-dependencies } $project
    $calls = @(& $module { $script:calls.ToArray() })
    Assert (($calls -join ';') -match 'pub get' -and ($calls -join ';') -match 'jobsResolveDependencyArtifacts') 'Android 真正解析 Pub 后 Maven artifacts'
    Assert (-not (($calls -join ';') -match '\|help\b')) 'Android 不把 Gradle help 当原生库下载'
    Assert ([Environment]::GetEnvironmentVariable('GRADLE_OPTS','Process') -ceq $savedOpts) '成功后恢复进程 Gradle 环境'
    & $module { $script:calls.Clear(); $script:fixtureResult='dependency graph only' }
    Assert-Throws { & $module { param($p) Invoke-JobsProjectDependencyAction $p android-dependencies } $project } '没有真实解析标记不得报成功'
    Assert ([Environment]::GetEnvironmentVariable('GRADLE_OPTS','Process') -ceq $savedOpts) '失败后恢复进程环境'
    & $module { $script:fixtureResult=''; $script:calls.Clear(); $script:failCommand='jobsResolveDependencyArtifacts' }
    Assert-Throws { & $module { param($p) Invoke-JobsProjectDependencyAction $p android-dependencies } $project } '任一 configuration 解析失败停止'
    & $module { $script:failCommand=''; $script:calls.Clear() }
    $init = & $module { param($d) New-JobsDependencyGradleInit $d } $temp
    $groovy = [IO.File]::ReadAllText($init)
    Assert ($groovy.Contains('it.canBeResolved') -and $groovy.Contains('configuration.resolve()') -and $groovy.Contains('artifact.exists()')) 'init 同时请求真实 artifact 文件并检验存在'
    Assert ($groovy.Contains('project.buildscript.configurations') -and $groovy.Contains('project.configurations')) '构建插件与项目 configurations 同时覆盖'
    Assert (-not $groovy.Contains('lenient') -and -not $groovy.Contains('catch')) '未宽松吞掉配置解析错误'

    & $module { param($p) Invoke-JobsProjectDependencyAction $p flutter-precache } $project
    $calls = @(& $module { $script:calls.ToArray() })
    Assert (($calls -join ';') -match 'precache --android') 'SDK 产物按所选目标 precache'
    Assert (-not (($calls -join ';') -match 'java-health|android-tools|gradle-wrapper|pub get|build apk')) 'precache 不混入 SDK manager 之外的平台工具或 Pub/构建'

    [IO.File]::WriteAllText((Join-Path $project 'package.json'),'{}')
    [IO.File]::WriteAllText((Join-Path $project 'package-lock.json'),'{}')
    & $module { $script:calls.Clear() }
    & $module { param($p) Invoke-JobsDependencyWeb $p } $project
    Assert ((& $module { $script:calls -join ';' }) -match 'tool-npm.cmd\|ci\|') 'npm 锁文件使用 ci，生命周期输出不关闭'
    [IO.File]::Delete((Join-Path $project 'package-lock.json'))
    [IO.File]::WriteAllText((Join-Path $project 'pnpm-lock.yaml'),'lockfileVersion: 9')
    & $module { $script:calls.Clear() }
    & $module { param($p) Invoke-JobsDependencyWeb $p } $project
    Assert ((& $module { $script:calls -join ';' }) -match 'tool-pnpm.cmd\|install --frozen-lockfile\|') 'pnpm 使用冻结锁'
    [IO.File]::WriteAllText((Join-Path $project 'yarn.lock'),'fixture')
    Assert-Throws { & $module { param($p) Invoke-JobsDependencyWeb $p } $project } '多个管理器锁拒绝猜测'
    [IO.File]::Delete((Join-Path $project 'pnpm-lock.yaml'))
    & $module { $script:calls.Clear() }
    & $module { param($p) Invoke-JobsDependencyWeb $p } $project
    Assert ((& $module { $script:calls -join ';' }) -match 'tool-yarn.cmd\|install --immutable\|') '现代 Yarn 使用 immutable'
    [IO.File]::WriteAllText((Join-Path $project 'package.json'),'{"packageManager":"npm@9.1.0"}')
    Assert-Throws { & $module { param($p) Invoke-JobsDependencyWeb $p } $project } 'packageManager 与锁文件冲突拒绝'
    [IO.File]::WriteAllText((Join-Path $project 'package.json'),'{"packageManager":"yarn@9.2.0"}')
    Assert-Throws { & $module { param($p) Invoke-JobsDependencyWeb $p } $project } '已装管理器不符合精确版本拒绝'
    [IO.File]::WriteAllText((Join-Path $project 'package.json'),'{}')

    & $module { $script:calls.Clear() }
    $arguments = @('build','apk','--debug','--target','lib/main_custom.dart','--flavor','demo','--dart-define-from-file=C:\config space\env.json')
    $result = & $module { param($p,$a) Invoke-JobsDependencyNative $p ([pscustomobject]@{Flutter='flutter.bat'}) 'fixture-fzf' 'Android' $a } $project $arguments
    Assert (($result -join '|') -ceq ($arguments -join '|')) '实际 native 构建返回原选定入口/flavor/define'
    $calls = @(& $module { $script:calls.ToArray() })
    Assert ($calls[0] -match '\|build apk --help\|' -and $calls[1] -match '\|build apk --debug --target lib/main_custom.dart --flavor demo') '构建前先验证目标命令能力'
    Assert (-not (($calls -join ';') -match '\|run\b')) 'native 准备不会启动应用'

    $packager = Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/Actions/package/Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $packager { function script:Initialize-JobsPackagerHarmonyEnvironment { } }
    $ohos = Join-Path $project 'ohos'
    [void][IO.Directory]::CreateDirectory((Join-Path $ohos 'hvigor'))
    [IO.File]::WriteAllText((Join-Path $ohos 'oh-package.json5'),'{}')
    [IO.File]::WriteAllText((Join-Path $ohos 'hvigor/hvigor-config.json5'),'{}')
    [IO.File]::WriteAllText((Join-Path $ohos 'hvigorw.bat'),'fixture wrapper')
    & $module { $script:calls.Clear() }
    & $module { param($p) Invoke-JobsDependencyOhos $p } $project
    $calls = @(& $module { $script:calls.ToArray() })
    Assert ($calls.Count -eq 4 -and $calls[0] -match 'ohpm.bat\|--version' -and $calls[1] -match 'hvigorw.bat\|--help') 'OHOS 先核验现有工具与工程 wrapper 能力'
    Assert ($calls[2] -match 'ohpm.bat\|install\|' -and $calls[3] -match 'hvigorw.bat\|--sync\|') 'OHOS 原生库和固定插件分别实际执行'
    Assert (@($calls | Where-Object { $_ -notlike ('*|'+$ohos) }).Count -eq 0) 'ohpm 与 Hvigor 均在目标 ohos 目录运行'
    & $module { $script:calls.Clear(); $script:failCommand='install' }
    Assert-Throws { & $module { param($p) Invoke-JobsDependencyOhos $p } $project } 'ohpm 失败停止 Hvigor'
    Assert (-not ((& $module { $script:calls -join ';' }) -match '\|--sync\|')) 'ohpm 失败后未继续插件同步'
    & $module { $script:failCommand=''; $script:calls.Clear() }
    [IO.File]::Delete((Join-Path $ohos 'hvigorw.bat'))
    Assert-Throws { & $module { param($p) Invoke-JobsDependencyOhos $p } $project } '缺少项目 wrapper 不安装全局最新 Hvigor'
    Assert ((& $module { $script:calls.Count }) -eq 0) 'wrapper 缺失没有联网命令'

    [IO.File]::WriteAllText((Join-Path $project 'lib/main_custom.dart'),'void main() {}')
    $plan = & $module { param($p) Get-JobsSetupRunArguments $p 'fzf' '' 'Windows' -ForBuild } $project
    Assert (($plan -join '|') -ceq 'build|windows|--debug|--target|lib/main_custom.dart') '原生准备不强制不存在的 lib/main.dart'
    $release = Join-Path $temp 'release'
    $installer = Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    & $installer { param($p,$d) New-JobsPackageRelease -PackagePath $p -Destination $d } (Join-Path $root 'JobsFlutterTools') $release | Out-Null
    Assert ((Get-FileHash (Join-Path $release 'Scripts/ProjectDependencies.ps1')).Hash -ceq (Get-FileHash (Join-Path $root 'JobsFlutterTools/Scripts/ProjectDependencies.ps1')).Hash) '独立发布携带同字节依赖内核'
    Assert ((Get-FileHash (Join-Path $release 'Scripts/HarmonySdk.psm1')).Hash -ceq (Get-FileHash (Join-Path $root 'JobsFlutterTools/Scripts/HarmonySdk.psm1')).Hash) '独立发布携带同字节鸿蒙取消契约'

    # SDK 缺失/损坏复用真实管理模块的完成契约，外部安装过程换成测试函数。
    $fresh = Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetup.psm1') -Force -PassThru -DisableNameChecking
    $sdk = Join-Path $temp 'version-sdk'
    [void][IO.Directory]::CreateDirectory((Join-Path $sdk 'bin/cache/dart-sdk/bin'))
    foreach ($relative in @('bin/flutter.bat','bin/cache/dart-sdk/bin/dart.exe')) { [IO.File]::WriteAllText((Join-Path $sdk $relative),'fixture file, not executed') }
    & $fresh {
        function script:Invoke-JobsSetupProcess {
            param($File,$Arguments,$Directory,$TimeoutSeconds)
            $text = if ($Arguments -contains '--machine') { '{"frameworkVersion":"3.29.3","dartSdkVersion":"3.7.2"}' } else { 'Dart SDK version: 3.7.2 (stable) on "windows_x64"' }
            [pscustomobject]@{StdOut=$text;StdErr='';ExitCode=0}
        }
    }
    $metadata = & $fresh { param($file,$p) Get-JobsSetupFlutter $file $p 'system' } (Join-Path $sdk 'bin/flutter.bat') $project
    Assert ($metadata.FrameworkVersion -ceq '3.29.3' -and $metadata.Architecture -ceq 'windows_x64') '从真实格式输出解析归档所需SDK版本与架构'
    $manager = Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/Actions/sdk-manage/Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $manager {
        $script:preparations=0
        $script:cancelPreparation=$false
        function script:Invoke-JobsFlutterVersionAction {
            param($Directory,[switch]$RequireCompletion)
            if(-not $RequireCompletion){throw 'dependency chain did not require completion'}
            $script:preparations++
            if($script:cancelPreparation){throw 'fixture SDK cancelled'}
            [IO.File]::WriteAllText((Join-Path $Directory '.fvmrc'),'{"flutter":"3.29.3"}')
        }
    }
    & $fresh {
        $script:healthCalls=0
        $script:healthFailure=$false
        function script:Get-JobsSetupFlutter { param($f,$p,$m) $script:healthCalls++; if($script:healthFailure){throw 'fixture broken runtime'};[pscustomobject]@{Mode=$m;Flutter=$f;Root='fixture'} }
    }
    & $fresh { param($p) Get-JobsDependencyFlutter $p '' } $project | Out-Null
    Assert ((& $manager {$script:preparations}) -eq 1 -and (& $fresh {$script:healthCalls}) -eq 1) '缺SDK走安装后真实复检一次'
    & $fresh { param($p) Get-JobsDependencyFlutter $p '' } $project | Out-Null
    Assert ((& $manager {$script:preparations}) -eq 1) '健康已绑定不重复准备'
    & $fresh { $script:healthFailure=$true }
    Assert-Throws { & $fresh { param($p) Get-JobsDependencyFlutter $p '' } $project } '准备后健康复检仍失败即停止'
    Assert ((& $manager {$script:preparations}) -eq 2) '损坏 SDK 只修复一次'
    & $manager { $script:cancelPreparation=$true }
    Assert-Throws { & $fresh { param($p) Get-JobsDependencyFlutter $p '' } $project } 'SDK 取消不继续复检/下游'
    Remove-Module $fresh
    Write-Host ('PASS: FlutterProjectDependencies.Tests.ps1 ('+$count+' assertions; mock tools only, no install/network/native build/registry)')
} finally {
    Remove-Module ProjectSetup -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $temp -Recurse -Force
}
