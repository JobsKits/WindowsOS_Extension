# ProjectDependencies.ps1 | 随 ProjectSetup 加载的分层依赖准备内核。
# Created by Jobs on 2026年10月29日，星期四.
# 只处理所选工程及工具缓存；保留工程版本、认证和仓库配置，不启动应用。

# 只列当前 Windows 宿主可处理、且工程真实存在的平台。
function Get-JobsDependencyPlatforms {
    param([string]$Project)
    return @(@('Android','Windows','Web','Ohos') | Where-Object { [IO.Directory]::Exists((Join-Path $Project $_.ToLowerInvariant())) })
}

# 记录只用于本机的显式系统选择；没有记录时仅认工程自身 FVM，不借用 PATH Flutter。
function Get-JobsDependencyFlutter {
    param([string]$Project, [string]$Fzf, [switch]$Ohos)
    $modern = Join-Path $Project '.fvmrc'
    $legacy = Join-Path $Project '.fvm/fvm_config.json'
    $failure = ''
    $pin = ''
    try {
        if ([IO.File]::Exists($modern) -or [IO.File]::Exists($legacy)) {
            $configPath = if ([IO.File]::Exists($modern)) { $modern } else { $legacy }
            Assert-JobsSetupFile $configPath
            $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $pin = if ($config.PSObject.Properties['flutter']) { $config.flutter } elseif ($config.PSObject.Properties['flutterSdkVersion']) { $config.flutterSdkVersion } else { $null }
            if ($pin -isnot [string] -or [string]::IsNullOrWhiteSpace($pin)) { throw 'FVM 版本声明无效。' }
            return Get-JobsSetupFlutter (Join-Path $Project '.fvm/flutter_sdk/bin/flutter.bat') $Project 'fvm'
        }
        $profile = Get-JobsSetupProfile $Project
        if ($profile -and $profile.FlutterMode -ceq 'system') { return Get-JobsSetupFlutter $profile.FlutterPath $Project 'system' }
        throw '目标工程没有已确认的 Flutter SDK 绑定。'
    } catch { $failure = $_.Exception.Message }
    Write-JobsSetupMessage ('项目 SDK 尚未就绪：' + $failure + '；进入现有安装/切换流程，成功后复检。')
if ($Ohos -or $pin -cmatch '^custom_jobs_ohos_') {
    $manager = Import-Module (Join-Path $PSScriptRoot 'HarmonySdk.psm1') -PassThru -DisableNameChecking
    & $manager { param($p) Invoke-JobsHarmonySdkAction -Target $p -RequireCompletion } $Project
} else {
    $manager = Import-Module (Join-Path $PSScriptRoot 'Actions/sdk-manage/Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $manager { param($p) Invoke-JobsFlutterVersionAction -Directory $p -RequireCompletion } $Project
}
    # 管理器返回成功也必须重新读取真实声明和运行链，不能依赖旧对象。
    $configPath = if ([IO.File]::Exists($modern)) { $modern } else { $legacy }
    Assert-JobsSetupFile $configPath
    if (-not [IO.File]::Exists($configPath)) { throw 'SDK 准备后没有项目 FVM 声明，未继续。' }
    return Get-JobsSetupFlutter (Join-Path $Project '.fvm/flutter_sdk/bin/flutter.bat') $Project 'fvm'
}

# Java 沿本机已确认记录或工程声明复用；不健康才进入既有选择器。
function Get-JobsDependencyJava {
    param([string]$Project, [string]$Fzf)
    $profile = Get-JobsSetupProfile $Project
    if ($profile) {
        try { $java = Get-JobsSetupJava $profile.JavaHome $Project; $java | Add-Member Mode $profile.JavaMode; return $java }
        catch { Write-JobsSetupMessage ('已记录 JDK 不可用：' + $_.Exception.Message) }
    }
    $file = Join-Path $Project '.jobs/java-environment.json'
    if ([IO.File]::Exists($file)) {
        Assert-JobsSetupFile $file
        $saved = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($saved.Platform -ceq 'Windows' -and $saved.JavaMode -cin @('system','jenv')) {
            try { $java = Get-JobsSetupJava $saved.JavaHome $Project; $java | Add-Member Mode $saved.JavaMode; return $java }
            catch { Write-JobsSetupMessage ('已记录 Java 选择不可用：' + $_.Exception.Message) }
        }
    }
    return Select-JobsSetupJava $Project $Fzf
}

# 临时 Gradle task 强制请求真实文件，不能用 dependencies/help 的图或成功文字代替下载。
function New-JobsDependencyGradleInit {
    param([string]$Directory)
    $file = Join-Path $Directory 'jobs-resolve-artifacts.gradle'
    $source = @'
gradle.projectsEvaluated {
    def root = gradle.rootProject
    if (root.tasks.findByName('jobsResolveDependencyArtifacts') != null) {
        throw new GradleException('jobsResolveDependencyArtifacts task name already exists; refusing to replace it')
    }
    root.tasks.create('jobsResolveDependencyArtifacts') {
        doLast {
            int resolved = 0
            root.allprojects.each { project ->
                [project.buildscript.configurations, project.configurations].each { configurations ->
                    configurations.findAll { it.canBeResolved }.each { configuration ->
                        println('JOBS_RESOLVE|' + project.path + '|' + configuration.name)
                        configuration.resolve().each { artifact ->
                            if (!artifact.exists()) {
                                throw new GradleException('Resolved artifact is missing: ' + artifact)
                            }
                        }
                        resolved++
                    }
                }
            }
            if (resolved == 0) { throw new GradleException('No resolvable Gradle configurations were found') }
            println('JOBS_ARTIFACTS_RESOLVED|' + resolved)
        }
    }
}
'@
    [IO.File]::WriteAllText($file, $source, (New-Object Text.UTF8Encoding($false)))
    return $file
}

function Invoke-JobsDependencyAndroid {
    param([string]$Project, $Flutter, $Java, [string]$Fzf, [string]$Gradle)
    if (-not [IO.Directory]::Exists((Join-Path $Project 'android'))) { throw '工程没有 Android 平台。' }
    Set-JobsSetupLocalProperty $Project 'flutter.sdk' $Flutter.Root
    Set-JobsSetupJavaProcess $Project $Java
    if (-not $Gradle) { $Gradle = Install-JobsSetupGradle $Project $Java $Fzf }
    $temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsAndroidDependencies-' + [guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($temporary)
    try {
        $init = New-JobsDependencyGradleInit $temporary
        Set-JobsSetupProgress deps.plugins running '下载工程全部可解析 Maven 原生库与构建插件'
        $parameters = @('jobsResolveDependencyArtifacts','--no-daemon','--stacktrace','--init-script',$init)
        if ((Get-Variable SetupMavenFallback -Scope Script -ErrorAction SilentlyContinue) -and $script:SetupMavenFallback) { $parameters += @('--init-script',(New-JobsSetupMirrorInit $temporary)) }
        $result = Invoke-JobsSetupProcess $Gradle $parameters (Join-Path $Project 'android') 1800
        if (($result.StdOut + $result.StdErr) -notmatch '(?m)^JOBS_ARTIFACTS_RESOLVED\|[1-9][0-9]*\s*$') { throw 'Gradle 未返回本次真实 artifact 解析完成标记。' }
        Set-JobsSetupProgress deps.plugins done 'Maven 原生库与构建插件已实际解析'
    } finally { if ([IO.Directory]::Exists($temporary)) { [IO.Directory]::Delete($temporary,$true) } }
}

# 使用工程 wrapper 与现有 DevEco 工具；不安装任意最新 npm/Hvigor。
function Invoke-JobsDependencyOhos {
    param([string]$Project)
    $directory = Join-Path $Project 'ohos'
    foreach ($relative in @('oh-package.json5','hvigor/hvigor-config.json5')) {
        $file = Join-Path $directory $relative
        Assert-JobsSetupFile $file
        if (-not [IO.File]::Exists($file)) { throw ('缺少鸿蒙工程声明：' + $file) }
    }
    $packager = Import-Module (Join-Path $PSScriptRoot 'Actions/package/Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $packager { Initialize-JobsPackagerHarmonyEnvironment }
    $ohpm = Find-JobsExecutable 'ohpm.bat' @('ohpm.cmd','ohpm')
    $wrapper = $null
    foreach ($name in @('hvigorw.bat','hvigorw.cmd','hvigorw')) {
        $candidate = Join-Path $directory $name
        if ([IO.File]::Exists($candidate)) { Assert-JobsSetupFile $candidate; $wrapper = $candidate; break }
    }
    if (-not $ohpm -or -not $wrapper) { throw '缺少可用 ohpm 或工程自己的 Hvigor wrapper；请准备匹配工程版本的 DevEco 工具，未安装全局 npm 包。' }
    [void](Invoke-JobsSetupProcess $ohpm @('--version') $directory 30)
    $help = Invoke-JobsSetupProcess $wrapper @('--help') $directory 120
    if (($help.StdOut + $help.StdErr) -notmatch '(?i)(?:^|\s)--sync(?:\s|[=,]|$)') { throw '此工程 Hvigor wrapper 未声明 --sync，请根据工程固定版本确认同步命令。' }
    Set-JobsSetupProgress deps.plugins running 'ohpm 原生库与工程固定 Hvigor 插件同步'
    [void](Invoke-JobsSetupProcess $ohpm @('install') $directory 1800)
    [void](Invoke-JobsSetupProcess $wrapper @('--sync') $directory 1800)
    Set-JobsSetupProgress deps.plugins done 'ohpm 安装与 Hvigor 同步均成功'
}

# 有 JS 清单时才执行；锁文件决定管理器，生命周期脚本与其失败按原样传播。
function Invoke-JobsDependencyWeb {
    param([string]$Project)
    $directories = @(@($Project,(Join-Path $Project 'web')) | Select-Object -Unique | Where-Object { [IO.File]::Exists((Join-Path $_ 'package.json')) })
    if (-not $directories.Count) { Write-JobsSetupMessage 'Web/JS 依赖不适用：工程根和 web/ 均无 package.json；Flutter Web 的 Dart 包仍由 Pub 管理。'; return }
    foreach ($directory in $directories) {
        Assert-JobsSetupFile (Join-Path $directory 'package.json')
        $manifest = Get-Content -LiteralPath (Join-Path $directory 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $locks = @(@('package-lock.json','npm-shrinkwrap.json','pnpm-lock.yaml','yarn.lock') | Where-Object { [IO.File]::Exists((Join-Path $directory $_)) })
        foreach ($name in $locks) { Assert-JobsSetupFile (Join-Path $directory $name) }
        $managers = @($locks | ForEach-Object { if ($_ -in @('package-lock.json','npm-shrinkwrap.json')) { 'npm' } elseif ($_ -eq 'pnpm-lock.yaml') { 'pnpm' } else { 'yarn' } } | Select-Object -Unique)
        if ($managers.Count -ne 1) { throw ('JS 工程必须提供唯一管理器的锁文件（npm/pnpm/yarn），未猜测安装方式：' + $directory) }
        $manager = $managers[0]
        if ($manifest.PSObject.Properties['packageManager'] -and [string]$manifest.packageManager -notmatch ('^' + $manager + '@')) { throw 'packageManager 与锁文件不一致。' }
        $node = Find-JobsExecutable 'node.exe' @('node')
        $tool = Find-JobsExecutable ($manager + '.cmd') @(($manager + '.bat'),($manager + '.exe'),$manager)
        if (-not $node -or -not $tool) { throw ('缺少本项目所需 Node / ' + $manager + '，请按工程版本准备，不会全局安装最新版本。') }
        [void](Invoke-JobsSetupProcess $node @('--version') $directory 30)
        $version = Invoke-JobsSetupProcess $tool @('--version') $directory 30
        if ($manifest.PSObject.Properties['packageManager'] -and [string]$manifest.packageManager -match '@([0-9]+\.[0-9]+\.[0-9]+)') {
            if (($version.StdOut + $version.StdErr).Trim() -cne $Matches[1]) { throw '已安装 JS 包管理器与 packageManager 固定版本不一致。' }
        }
        $arguments = @('ci')
        if ($manager -ceq 'pnpm') { $arguments = @('install','--frozen-lockfile') }
        elseif ($manager -ceq 'yarn') {
            if (($version.StdOut + $version.StdErr) -notmatch '(?m)^([0-9]+)\.') { throw '无法确认 Yarn 主版本，未猜测命令。' }
            $arguments = if ([int]$Matches[1] -ge 2) { @('install','--immutable') } else { @('install','--frozen-lockfile') }
        }
        Write-JobsSetupMessage ('按工程锁文件安装 JS 依赖；保留生命周期脚本：' + $directory)
        [void](Invoke-JobsSetupProcess $tool $arguments $directory 1800)
    }
}

function Invoke-JobsDependencyPrecache {
    param([string]$Project, $Flutter, [string]$Platform)
    $help = Invoke-JobsSetupProcess $Flutter.Flutter @('precache','--help') $Project 120
    $flag = '--' + $Platform.ToLowerInvariant()
    $capability = '--(?:\[no-\])?' + [regex]::Escape($Platform.ToLowerInvariant()) + '\b'
    if (($help.StdOut + $help.StdErr) -notmatch $capability) { throw ('本 SDK 不支持平台缓存选项：' + $flag) }
    [void](Invoke-JobsSetupProcess $Flutter.Flutter @('precache',$flag) $Project 1800)
}

function Invoke-JobsDependencyNative {
    param([string]$Project, $Flutter, [string]$Fzf, [string]$Platform, [string[]]$BuildArguments)
    if (-not $BuildArguments) { $BuildArguments = Get-JobsSetupRunArguments $Project $Fzf '' $Platform -ForBuild }
    $help = Invoke-JobsSetupProcess $Flutter.Flutter @('build',$BuildArguments[1],'--help') $Project 120
    if (($help.StdOut + $help.StdErr) -notmatch ('(?i)flutter\s+build\s+' + [regex]::Escape($BuildArguments[1]) + '\b')) { throw '此 SDK 未确认支持所选平台构建，未执行原生准备。' }
    Write-JobsSetupMessage '将以所选入口/flavor/define 执行 debug 构建，触发 CMake/NuGet/FFI hooks 与平台库准备；可能编译并生成产物，不安装或启动应用，不保证后续完全离线。'
    Set-JobsSetupProgress deps.native running ('通过实际 debug 构建准备 ' + $Platform + ' 原生产物')
    [void](Invoke-JobsSetupProcess $Flutter.Flutter $BuildArguments $Project 3600)
    Set-JobsSetupProgress deps.native done '所选构建与原生产物准备成功；未启动应用'
    return ,$BuildArguments
}

# 一键配置复用相同内核，并把构建参数交给最终运行，避免两次选择不同入口。
function Invoke-JobsSetupTargetDependencies {
    param([string]$Project, $Flutter, $Java, [string]$Fzf, [string]$Platform, [string]$Gradle)
    if ($Platform -ceq 'Android') { Invoke-JobsDependencyAndroid $Project $Flutter $Java $Fzf $Gradle }
    elseif ($Platform -ceq 'Ohos') { Invoke-JobsDependencyOhos $Project }
    if ($Platform -ceq 'Web') { Invoke-JobsDependencyWeb $Project }
    return Invoke-JobsDependencyNative $Project $Flutter $Fzf $Platform
}

# 两个易混淆入口逐行交代实际层级，正文使用纯文本以兼容 CMD 与非彩色输出。
function Show-JobsDependencyActionDetails {
    param([string]$Action)
    if ($Action -ceq 'flutter-precache') {
        Write-Host '本项：下载Flutter平台资源（flutter precache）'
        Write-Host '  1、调用：使用当前项目 SDK 执行 flutter precache --所选目标。'
        Write-Host '  2、下载对象：当前 Flutter SDK 所选目标的引擎和工具。'
        Write-Host '      Android：引擎二进制，也可能包含 Flutter 自身的 android_maven 制品。'
        Write-Host '      Web：对应的渲染资源与工具。'
        Write-Host '      Apple：例如 iOS Flutter.xcframework 仅 macOS 入口提供；Windows 不提供 iOS 目标。'
        Write-Host '  3、范围：不解析工程全部 Maven / 第三方包，不替代 Pub / Pods 拉取。'
        Write-Host '  4、前提：不等于安装完整 Android SDK 或 Xcode。'
        Write-Host '  5、结果：只准备所选平台的 Flutter SDK 缓存，不编译、安装或启动应用。'
    } elseif ($Action -ceq 'native-dependencies') {
        Write-Host '本项：准备原生库与构建依赖（组合操作）'
        Write-Host '  1、必要前置：先获取当前工程 Pub 依赖，并准备所选目标需要的工具。'
        Write-Host '  2、平台包层：按所选目标处理 Android Maven、OpenHarmony OHPM 或 Web 工程包。'
        Write-Host '  3、构建层：执行所选入口 / flavor / dart-define 对应的 flutter build。'
        Write-Host '      构建会触发对应平台的 CMake、NuGet、FFI hooks 或延迟下载制品。'
        Write-Host '  4、影响：会实际编译并生成产物，不安装或启动应用。'
        Write-Host '  5、范围：只处理本次所选目标，不把所有平台全量都拉取，也不保证后续完全离线。'
    }
}

# 公开只读计划与单项执行，共享同一绑定、取消及进程环境恢复边界。
function Invoke-JobsProjectDependencyAction {
    param([string]$Target, [ValidateSet('pub-get','android-dependencies','ohos-dependencies','native-dependencies','flutter-precache','web-dependencies')][string]$Action, [switch]$Check)
    $project = Resolve-JobsTarget $Target
    Assert-JobsSetupDirectory $project
    $identity = Import-Module (Join-Path $PSScriptRoot 'Actions/sdk-manage/Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $identity { param($p) Assert-JobsFlutterProject $p } $project
    $platforms = @(Get-JobsDependencyPlatforms $project)
    if ($Check) {
        Write-Host ('只读计划：' + $Action + '；工程：' + $project + '；Windows可处理已有平台：' + ($platforms -join ', '))
        Write-Host '未运行工具、联网、安装、写日志或修改工程。Apple 平台须 macOS，Linux 须 Linux 宿主。'
        return
    }
    if ($Action -cin @('flutter-precache','native-dependencies') -and
        ((Get-JobsSetupEnvironmentSnapshot @('NO_COLOR'))['NO_COLOR'].Exists -or [Console]::IsOutputRedirected)) {
        Write-Host ('Flutter 分层依赖准备：' + $Action)
    } else {
        Write-Host ('Flutter 分层依赖准备：' + $Action) -ForegroundColor Red
    }
    if ($Action -cin @('flutter-precache','native-dependencies')) {
        Show-JobsDependencyActionDetails $Action
        Write-Host '  SDK 前提：缺少可用绑定时进入现有安装/切换，复检成功后继续；保留工程版本、认证、仓库和全局代理。'
    } else {
        Write-Host '仅处理当前工程及工具缓存；可下载/执行锁定依赖的生命周期脚本或原生构建钩子，native 可能编译但不启动应用。缺少 SDK 时进入现有安装/切换。保留版本、认证、仓库和全局代理。'
    }
    Write-Host 'Esc/Ctrl+C 取消；取消只停止后续，保留已完成的安装或缓存。Apple/Linux 平台需对应宿主，本动作不保证完全离线。'
    if (-not (Test-JobsSetupInteractive)) { throw '需要真实交互终端。' }
    if ((Read-Host '回车继续；任意非空输入取消') -ne '') { throw '已取消，未执行依赖操作。' }
    if ($Action -eq 'web-dependencies' -and -not @(@($project,(Join-Path $project 'web')) | Where-Object { [IO.File]::Exists((Join-Path $_ 'package.json')) }).Count) { Invoke-JobsDependencyWeb $project; return }
    if ($Action -eq 'android-dependencies' -and 'Android' -cnotin $platforms) { throw '工程没有 Android 平台。' }
    if ($Action -eq 'ohos-dependencies' -and 'Ohos' -cnotin $platforms) { throw '工程没有 ohos 平台。' }
    $saved = Get-JobsSetupEnvironmentSnapshot @('JAVA_HOME','PATH','GRADLE_OPTS','ANDROID_HOME','ANDROID_SDK_ROOT','TOOL_HOME','DEVECO_SDK_HOME','NO_COLOR','FORCE_COLOR','CLICOLOR','ANSI_COLORS_DISABLED','npm_config_color')
    try {
        $logs = Join-Path (Get-JobsInstallRoot) 'logs'; [void][IO.Directory]::CreateDirectory($logs)
        $script:SetupLog = Join-Path $logs ('dependencies-' + [guid]::NewGuid().ToString('N') + '.log')
        Write-JobsSetupMessage ('工程：' + $project + '；动作：' + $Action + '；日志：' + $script:SetupLog)
        $fzf = $null
        if ($Action -notin @('pub-get','web-dependencies','ohos-dependencies')) { $fzf = Get-JobsSetupFzf $project }
        if ($Action -eq 'web-dependencies') { Invoke-JobsDependencyWeb $project; return }
        if ($Action -eq 'pub-get') { $flutter = Get-JobsDependencyFlutter $project $fzf; [void](Invoke-JobsSetupProcess $flutter.Flutter @('pub','get') $project 900); return }
        $platform = switch ($Action) { 'android-dependencies' { 'Android' } 'ohos-dependencies' { 'Ohos' } default { Select-JobsSetupChoice $fzf '选择工程已有的目标平台' $platforms } }
        $flutter = Get-JobsDependencyFlutter $project $fzf -Ohos:($platform -ceq 'Ohos')
        if ($Action -eq 'flutter-precache') { Invoke-JobsDependencyPrecache $project $flutter $platform; return }
        $java = $null
        if ($platform -ceq 'Android') {
            $java = Get-JobsDependencyJava $project $fzf
            Set-JobsSetupJavaProcess $project $java
            Initialize-JobsSetupAndroid $project $flutter $java $fzf
        } elseif ($platform -ceq 'Windows' -and $Action -eq 'native-dependencies') { Initialize-JobsSetupWindowsDesktop $project $fzf }
        [void](Invoke-JobsSetupProcess $flutter.Flutter @('pub','get') $project 900)
        switch ($Action) {
            'android-dependencies' { Invoke-JobsDependencyAndroid $project $flutter $java $fzf }
            'ohos-dependencies' { Invoke-JobsDependencyOhos $project }
            'native-dependencies' {
                if ($platform -ceq 'Android') { Invoke-JobsDependencyAndroid $project $flutter $java $fzf }
                elseif ($platform -ceq 'Ohos') { Invoke-JobsDependencyOhos $project }
                elseif ($platform -ceq 'Web') { Invoke-JobsDependencyWeb $project }
                Invoke-JobsDependencyPrecache $project $flutter $platform
                [void](Invoke-JobsDependencyNative $project $flutter $fzf $platform)
            }
        }
        Write-JobsSetupMessage '所选依赖阶段已完成；其它平台与应用运行未作保证。'
    } finally {
        Restore-JobsSetupEnvironment $saved
        Remove-Variable SetupLog -Scope Script -ErrorAction SilentlyContinue
    }
}
