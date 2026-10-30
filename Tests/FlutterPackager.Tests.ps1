# FlutterPackager.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月22日，星期四.
# 临时工程与假工具；不联网、不注册菜单、不构建真实 Flutter 工程。
[CmdletBinding()]
param([switch]$Native)
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$package = Join-Path $root 'JobsFlutterPackager'
$action = Import-Module (Join-Path $package 'Scripts/Action.psm1') -PassThru -DisableNameChecking
$installer = Import-Module (Join-Path $package 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
$script:assertions = 0
function Assert-Packager { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw ('FAIL: ' + $Message) }; $script:assertions++ }
function Assert-PackagerThrows { param([scriptblock]$Body, [string]$Message); $threw = $false; try { & $Body | Out-Null } catch { $threw = $true }; Assert-Packager $threw $Message }
$temporaryBase = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $temporaryBase = '/private/tmp' }
$temporary = Join-Path $temporaryBase ('JobsFlutterPackage-' + [guid]::NewGuid().ToString('N'))
$savedLocal = $env:LOCALAPPDATA
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $env:LOCALAPPDATA = Join-Path $temporary 'Local'
    $fixtures = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Fixtures/FlutterRunnerPubspec.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($fixture in $fixtures) {
        $result = & $action { param($Text) Test-JobsFlutterPubspec $Text } $fixture.Text
        Assert-Packager ($result -eq $fixture.Expected) ('精确识别：' + $fixture.Name)
    }
    $project = Join-Path $temporary 'Project 中文 & 100%'
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'android'))
    [void][IO.Directory]::CreateDirectory((Join-Path $project 'lib'))
    [IO.File]::WriteAllText((Join-Path $project 'pubspec.yaml'), "dependencies:`n  flutter:`n    sdk: flutter`n")
    [IO.File]::WriteAllText((Join-Path $project 'android/gradlew.bat'), '@echo fixture')
    & $action { param($Path) Assert-JobsFlutterProject $Path } $project
    Assert-PackagerThrows { & $action { param($Path) Assert-JobsFlutterProject $Path } $temporary } '不向下扫描子工程'
    Assert-PackagerThrows { & $action { param($Path) Assert-JobsFlutterProject $Path } (Join-Path $project 'android') } '不沿用父工程'
    [IO.File]::WriteAllText((Join-Path $project '.fvmrc'), '{"flutter":"3.0.0"}')
    Assert-PackagerThrows { & $action { param($Path) Get-JobsPackagerFlutter $Path } $project } 'FVM 绑定缺 SDK 不回退全局'
    $sdk = Join-Path $project '.fvm/flutter_sdk/bin'
    [void][IO.Directory]::CreateDirectory($sdk)
    [IO.File]::WriteAllText((Join-Path $sdk 'flutter.bat'), '@echo fixture')
    Assert-Packager ((& $action { param($Path) Get-JobsPackagerFlutter $Path } $project) -eq (Join-Path $sdk 'flutter.bat')) '优先项目绑定 SDK'
    Assert-PackagerThrows { & $action { Assert-JobsPackagerWindowsPlatform 'iOS' } } 'Windows iOS 明确停止'
    & $action { Assert-JobsPackagerWindowsPlatform 'Android' }
    Assert-PackagerThrows { & $action { Get-JobsPackagerOptions -Mode 'unsafe' } } '拒绝未知 mode'
    Assert-PackagerThrows { & $action { Get-JobsPackagerOptions -Flavor 'dev & whoami' } } '拒绝 CMD 元字符 flavor'
    $options = & $action { Get-JobsPackagerOptions -Mode '' -Flavor 'staging_2' }
    Assert-Packager ($options.Mode -ceq 'release' -and $options.Flavor -ceq 'staging_2') '默认 release 保留合法 flavor'

    $manifest = Get-Content -LiteralPath (Join-Path $package 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $release = Join-Path $temporary 'release'
    & $installer { param($Path, $Destination) New-JobsPackageRelease -PackagePath $Path -Destination $Destination } $package $release | Out-Null
    $plan = @(& $installer { param($Manifest, $Release) Get-JobsPackageRegistryPlan -Manifest $Manifest -ReleasePath $Release -PowerShellPath 'powershell.exe' } $manifest $release)
    Assert-Packager ($plan.Count -eq 4) '三个动态目录上下文与独立 CLSID'
    Assert-Packager (@($plan | Where-Object { $_.Key -match '\\shell\\' }).Count -eq 0) '不注册全目录静态 verb'
    Assert-Packager ($plan[3].InProcServer -eq (Join-Path $release 'bin/JobsFlutterPackagerContextMenu.dll')) '独立 DLL 不覆盖运行包'
    foreach ($name in @('ContextMenu.cpp', 'FlutterProject.h', 'ContextMenu.def', 'Build.ps1', 'OpenCmd.ps1')) {
        Assert-Packager (Test-Path -LiteralPath (Join-Path $release ('Scripts/' + $name)) -PathType Leaf) ('独立 release 完整：' + $name)
    }
    $disabled = @(& $installer { param($Manifest, $Release) Get-JobsPackageRegistryPlan -Manifest $Manifest -ReleasePath $Release -PowerShellPath 'powershell.exe' -Enabled $false } $manifest $release)
    Assert-Packager (@($disabled | Where-Object Enabled).Count -eq 0) '卸载本包处理器及 CLSID'

    # 真正启动一个失败的原生脚本，验证 stderr 不吞掉失败退出码。
    $fake = Join-Path $temporary 'fake-build'
    $body = "#!/bin/sh`necho fixture-output`necho fixture-error >&2`nexit 7`n"
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $fake += '.cmd'
        $body = "@echo off`r`necho fixture-output`r`necho fixture-error 1>&2`r`nexit /b 7`r`n"
    }
    [IO.File]::WriteAllText($fake, $body, (New-Object Text.UTF8Encoding($false)))
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { & /bin/chmod 700 $fake; if ($LASTEXITCODE -ne 0) { throw '临时假命令权限设置失败。' } }
    Assert-PackagerThrows { & $action { param($File, $Path) Invoke-JobsPackagerTool -File $File -Arguments @('build', 'apk') -Project $Path } $fake $project } '原生 stderr 和非零退出立即停止'

    # 注入单一命令边界，保留真实流程 / 产物查找，检查 APK→AAB 顺序及失败传播。
    & $action {
        $script:Calls = @()
        $script:Failure = ''
        $script:Emit = $true
        function script:Assert-JobsPackagerJava17 { param($Project) }
        function script:Invoke-JobsPackagerTool {
            param($File, $Arguments, $Project)
            $script:Calls += ($Arguments -join ' ')
            if (($Arguments -join ' ') -ceq $script:Failure) { throw 'fake failure' }
            if ($Arguments[0] -ne 'build' -or -not $script:Emit) { return }
            $type = $Arguments[1]
            $mode = $Arguments[2].Substring(2)
            $flavor = ''
            if ($Arguments.Count -gt 3) { $flavor = $Arguments[4] + '-' }
            $directory = Join-Path $Project 'build/app/outputs/flutter-apk'
            $extension = 'apk'
            if ($type -eq 'appbundle') { $directory = Join-Path $Project ('build/app/outputs/bundle/' + $flavor.TrimEnd('-') + $mode); $extension = 'aab' }
            [void][IO.Directory]::CreateDirectory($directory)
            [IO.File]::WriteAllText((Join-Path $directory ('app-' + $flavor + $mode + '.' + $extension)), 'fixture artifact')
        }
    }
    & $action { param($Path) Invoke-JobsPackagerBuild -Project $Path -Type 'all' -Mode 'profile' -Flavor 'demo' } $project
    $calls = @(& $action { $script:Calls })
    Assert-Packager (($calls -join '|') -ceq 'pub get|build apk --profile --flavor demo|build appbundle --profile --flavor demo') '依赖一次，APK 然后 AAB，mode/flavor 精确传递'
    & $action { $script:Calls = @(); $script:Failure = 'pub get' }
    Assert-PackagerThrows { & $action { param($Path) Invoke-JobsPackagerBuild -Project $Path -Type 'all' -Mode 'release' } $project } 'pub get 失败停止'
    Assert-Packager (@(& $action { $script:Calls }).Count -eq 1) 'pub get 失败不 build'
    & $action { $script:Calls = @(); $script:Failure = 'build apk --release' }
    Assert-PackagerThrows { & $action { param($Path) Invoke-JobsPackagerBuild -Project $Path -Type 'all' -Mode 'release' } $project } 'APK 失败停止'
    Assert-Packager (@(& $action { $script:Calls }).Count -eq 2) 'APK 失败不运行 AAB'
    & $action { $script:Calls = @(); $script:Failure = ''; $script:Emit = $false }
    Assert-PackagerThrows { & $action { param($Path) Invoke-JobsPackagerBuild -Project $Path -Type 'apk' -Mode 'debug' } $project } '退出 0 但缺产物不能成功'
    $apk = Join-Path $project 'build/app/outputs/flutter-apk/app-demo-profile.apk'
    $file = Get-Item -LiteralPath $apk
    $file.LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-2)
    Assert-Packager (@(& $action { param($Path) Get-JobsPackagerArtifacts -Project $Path -Type 'apk' -Mode 'profile' -Flavor 'demo' -StartedUtc ([DateTime]::UtcNow) } $project).Count -eq 1) '构建成功后允许 Gradle 复用对应的非空产物'
    Assert-PackagerThrows { & $action { param($Path) Get-JobsPackagerArtifacts -Project $Path -Type 'apk' -Mode 'profile' -Flavor '' -StartedUtc ([DateTime]::UtcNow) } $project } '无 flavor 不能误用有 flavor 产物'
    Assert-PackagerThrows { & $action { param($Path) Get-JobsPackagerArtifacts -Project $Path -Type 'appbundle' -Mode 'profile' -Flavor 'other' -StartedUtc ([DateTime]::UtcNow) } $project } 'AAB 不能误用其它 flavor 子目录'
    $legacy = Join-Path $project 'build/app/outputs/bundle/demoRelease/app.aab'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $legacy))
    [IO.File]::WriteAllText($legacy, 'legacy cached bundle')
    Assert-Packager (@(& $action { param($Path) Get-JobsPackagerArtifacts -Project $Path -Type 'appbundle' -Mode 'release' -Flavor 'demo' } $project).Count -eq 1) '兼容精确 flavor+mode 子目录中的旧 AGP app.aab'
    Assert-PackagerThrows { & $action { param($Path) Get-JobsPackagerArtifacts -Project $Path -Type 'appbundle' -Mode 'release' -Flavor '' } $project } '无 flavor AAB 不误用其它 flavor 目录'
    [IO.File]::WriteAllText($apk, '')
    Assert-PackagerThrows { & $action { param($Path) Get-JobsPackagerArtifacts -Project $Path -Type 'apk' -Mode 'profile' -Flavor 'demo' -StartedUtc ([DateTime]::UtcNow) } $project } '空产物不能成功'
    & $action {
        $script:Calls = @()
        function script:Select-JobsPackagerChoice { param($Title, $Choices) return 'iOS' }
    }
    Assert-PackagerThrows { & $action { param($Path) Invoke-JobsFlutterPackageAction $Path } $project } '实际平台流程的 iOS 选择停止'
    Assert-Packager (@(& $action { $script:Calls }).Count -eq 0) 'iOS 不触发 pub get 或 build'
    & $action { function script:Select-JobsPackagerChoice { param($Title, $Choices) return $null } }
    & $action { param($Path) Invoke-JobsFlutterPackageAction $Path } $project
    Assert-Packager (@(& $action { $script:Calls }).Count -eq 0) '取消平台不触发构建'
    # 真正调用假 fzf 进程，核对可见选择、取消、健康失败和配置隔离。
    $selector = Import-Module (Join-Path $package 'Scripts/Action.psm1') -PassThru -DisableNameChecking -Force
    Assert-PackagerThrows { & $selector { function script:Find-JobsExecutable { param($Name, $Candidates) return $null }; Select-JobsPackagerChoice '平台' @('Android', 'iOS') } } '缺 fzf 明确停止'
    $fakeFzf = Join-Path $temporary 'fake-fzf'
    $fzfBody = @'
#!/bin/sh
if [ "$1" = '--version' ]; then
    echo fixture-fzf
    exit "${JOBS_FAKE_FZF_HEALTH:-0}"
fi
if [ -n "$FZF_DEFAULT_OPTS" ] || [ -n "$FZF_DEFAULT_OPTS_FILE" ]; then exit 8; fi
printf '%s\n' "$JOBS_FAKE_FZF_CHOICE"
exit "${JOBS_FAKE_FZF_EXIT:-0}"
'@
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $fakeFzf += '.exe'
        $source = Join-Path $temporary 'FzfFixture.cs'
        $code = @'
using System;
class FzfFixture {
    static int Main(string[] args) {
        if (args.Length > 0 && args[0] == "--version") {
            Console.WriteLine("fixture-fzf");
            return Int32.Parse(Environment.GetEnvironmentVariable("JOBS_FAKE_FZF_HEALTH"));
        }
        if (!String.IsNullOrEmpty(Environment.GetEnvironmentVariable("FZF_DEFAULT_OPTS")) ||
            !String.IsNullOrEmpty(Environment.GetEnvironmentVariable("FZF_DEFAULT_OPTS_FILE"))) return 8;
        Console.In.ReadToEnd();
        Console.WriteLine(Environment.GetEnvironmentVariable("JOBS_FAKE_FZF_CHOICE"));
        return Int32.Parse(Environment.GetEnvironmentVariable("JOBS_FAKE_FZF_EXIT"));
    }
}
'@
        [IO.File]::WriteAllText($source, $code, (New-Object Text.UTF8Encoding($false)))
        $csc = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
        & $csc /nologo /target:exe ('/out:' + $fakeFzf) $source
        if ($LASTEXITCODE -ne 0) { throw '临时 fzf 夹具编译失败。' }
    } else {
        $fzfBody = $fzfBody.Replace("`r`n", "`n")
        [IO.File]::WriteAllText($fakeFzf, $fzfBody, (New-Object Text.UTF8Encoding($false)))
        & /bin/chmod 700 $fakeFzf
    }
    & $selector { param($File) $script:FzfFixture = $File; function script:Find-JobsExecutable { param($Name, $Candidates) return $script:FzfFixture } } $fakeFzf
    $savedFzfOptions = $env:FZF_DEFAULT_OPTS
    $savedFzfFile = $env:FZF_DEFAULT_OPTS_FILE
    try {
        $env:FZF_DEFAULT_OPTS = '--bind=enter:execute(unsafe)'
        $env:FZF_DEFAULT_OPTS_FILE = 'untrusted-options'
        $env:JOBS_FAKE_FZF_HEALTH = '0'
        $env:JOBS_FAKE_FZF_EXIT = '0'
        $env:JOBS_FAKE_FZF_CHOICE = 'Android'
        Assert-Packager ((& $selector { Select-JobsPackagerChoice '平台' @('Android', 'iOS') }) -ceq 'Android') 'fzf 仅返回提供的单项，并隔离用户 execute 配置'
        Assert-Packager ($env:FZF_DEFAULT_OPTS -ceq '--bind=enter:execute(unsafe)' -and $env:FZF_DEFAULT_OPTS_FILE -ceq 'untrusted-options') '选择后恢复 fzf 配置'
        $env:JOBS_FAKE_FZF_CHOICE = 'OpenHarmony'
        $consoleEncoding = [Console]::OutputEncoding.CodePage
        Assert-Packager ((& $selector { Select-JobsPackagerChoice '平台' @('Android', 'iOS', 'OpenHarmony') }) -ceq 'OpenHarmony') 'fzf UTF-8 支持中文 OpenHarmony 平台名'
        Assert-Packager ([Console]::OutputEncoding.CodePage -eq $consoleEncoding) 'fzf 选择后恢复终端输出编码'
        $env:JOBS_FAKE_FZF_CHOICE = 'injected'
        Assert-PackagerThrows { & $selector { Select-JobsPackagerChoice '平台' @('Android', 'iOS') } } '拒绝选择清单外的返回值'
        $env:JOBS_FAKE_FZF_EXIT = '130'
        Assert-Packager ($null -eq (& $selector { Select-JobsPackagerChoice '平台' @('Android', 'iOS') })) 'fzf Esc / Ctrl+C 取消'
        $env:JOBS_FAKE_FZF_HEALTH = '3'
        Assert-PackagerThrows { & $selector { Select-JobsPackagerChoice '平台' @('Android', 'iOS') } } '不健康 fzf 不进入选择'
    } finally {
        $env:FZF_DEFAULT_OPTS = $savedFzfOptions
        $env:FZF_DEFAULT_OPTS_FILE = $savedFzfFile
        foreach ($name in @('JOBS_FAKE_FZF_HEALTH', 'JOBS_FAKE_FZF_EXIT', 'JOBS_FAKE_FZF_CHOICE')) { [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
    }

    # OpenHarmony 使用真实假工具进程，保留 SDK 选择、环境配置、能力检查及产物验证。
    $harmony = Import-Module (Join-Path $package 'Scripts/Action.psm1') -PassThru -DisableNameChecking -Force
    $toolHome = Join-Path $temporary 'DevEco Studio 中文'
    $harmonySdk = Join-Path $temporary 'Harmony SDK 中文 & 100%'
    $trace = Join-Path $temporary 'harmony-tools.log'
    $environmentNames = @('PATH', 'JAVA_HOME', 'NODE_HOME', 'TOOL_HOME', 'DEVECO_STUDIO_HOME', 'DEVECO_SDK_HOME', 'HOS_SDK_HOME', 'OHOS_SDK_HOME', 'FLUTTER_OHOS_SDK', 'OHOS_BUILD_TARGET', 'BUILD_MODE', 'FLAVOR', 'NO_COLOR', 'FORCE_COLOR', 'CLICOLOR', 'ANSI_COLORS_DISABLED', 'npm_config_color', 'JOBS_OHOS_TRACE', 'JOBS_OHOS_FAIL_TOOL', 'JOBS_OHOS_FAIL_COMMAND', 'JOBS_OHOS_HELP_MODE', 'JOBS_OHOS_OUTPUT_MODE')
    $savedEnvironment = @{}
    foreach ($name in $environmentNames) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
    $harmonyTools = @('tools/node/node.exe', 'tools/node/npm.cmd', 'tools/ohpm/bin/ohpm.bat', 'tools/hvigor/bin/hvigorw.bat', 'jbr/bin/java.exe')
    $fixtureBody = @'
#!/bin/sh
name=$(basename "$0")
name=${name%.*}
printf '%s|%s|%s\n' "$name" "$*" "$PWD" >> "$JOBS_OHOS_TRACE"
if [ "$JOBS_OHOS_FAIL_TOOL" = "$name" ]; then exit 41; fi
if [ "$1" = build ] && [ "$3" = --help ]; then
    case "$JOBS_OHOS_HELP_MODE" in
        error) exit 42 ;;
        generic) echo 'Usage: flutter build <command>' ;;
        app-unsupported) if [ "$2" = app ]; then echo 'Usage: flutter build <command>'; else echo "Usage: flutter build $2"; fi ;;
        color) printf 'Usage: flutter \033[31mbuild\033[0m %s\n' "$2" ;;
        *) echo "Usage: flutter build $2" ;;
    esac
    exit 0
fi
if [ "$JOBS_OHOS_FAIL_COMMAND" = "$*" ]; then exit 37; fi
if [ "$1" = build ] && [ "$2" = app ] && [ "$JOBS_OHOS_OUTPUT_MODE" = app-removes-hap ]; then
    /bin/rm -f ohos/entry/build/default/outputs/default/entry-default-signed.hap
    printf unvalidated > ohos/entry/build/default/outputs/default/other-unvalidated.hap
fi
if [ "$1" = build ] && [ "$JOBS_OHOS_OUTPUT_MODE" != missing ] && { [ "$2" != app ] || [ "$JOBS_OHOS_OUTPUT_MODE" != missing-app ]; }; then
    dir=ohos/entry/build/default/outputs/default
    file=entry-default-signed.hap
    if [ "$2" = app ]; then dir=ohos/build/outputs/default; file=ohos-default-signed.app; fi
    mkdir -p "$dir"
    if [ "$JOBS_OHOS_OUTPUT_MODE" = empty ]; then : > "$dir/$file"; else printf fixture > "$dir/$file"; fi
fi
printf '\033[32mfixture %s\033[0m \\033[31mliteral\\033[0m\n' "$name"
'@
    try {
        if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
            $fixtureExecutable = Join-Path $temporary 'HarmonyTool.exe'
            $fixtureSource = Join-Path $temporary 'HarmonyTool.cs'
            $fixtureCode = @'
using System;
using System.IO;
using System.Linq;
class HarmonyTool {
    static int Main(string[] args) {
        string name = Path.GetFileNameWithoutExtension(Environment.GetCommandLineArgs()[0]).ToLowerInvariant();
        if (name == "harmonytool") { name = args[0]; args = args.Skip(1).ToArray(); }
        string command = String.Join(" ", args);
        File.AppendAllText(Environment.GetEnvironmentVariable("JOBS_OHOS_TRACE"), name + "|" + command + "|" + Environment.CurrentDirectory + Environment.NewLine);
        if (Environment.GetEnvironmentVariable("JOBS_OHOS_FAIL_TOOL") == name) return 41;
        if (args.Length > 2 && args[0] == "build" && args[2] == "--help") {
            string mode = Environment.GetEnvironmentVariable("JOBS_OHOS_HELP_MODE");
            if (mode == "error") return 42;
            Console.WriteLine((mode == "generic" || (mode == "app-unsupported" && args[1] == "app")) ? "Usage: flutter build <command>" : "Usage: flutter " + (mode == "color" ? "\x1b[31mbuild\x1b[0m " : "build ") + args[1]);
            return 0;
        }
        if (Environment.GetEnvironmentVariable("JOBS_OHOS_FAIL_COMMAND") == command) return 37;
        if (args.Length > 1 && args[0] == "build" && args[1] == "app" && Environment.GetEnvironmentVariable("JOBS_OHOS_OUTPUT_MODE") == "app-removes-hap") {
            File.Delete(Path.Combine(Environment.CurrentDirectory, "ohos/entry/build/default/outputs/default/entry-default-signed.hap".Replace('/', Path.DirectorySeparatorChar)));
            File.WriteAllText(Path.Combine(Environment.CurrentDirectory, "ohos/entry/build/default/outputs/default/other-unvalidated.hap".Replace('/', Path.DirectorySeparatorChar)), "unvalidated");
        }
        if (args.Length > 1 && args[0] == "build" && Environment.GetEnvironmentVariable("JOBS_OHOS_OUTPUT_MODE") != "missing" && (args[1] != "app" || Environment.GetEnvironmentVariable("JOBS_OHOS_OUTPUT_MODE") != "missing-app")) {
            string relative = args[1] == "app" ? "ohos/build/outputs/default/ohos-default-signed.app" : "ohos/entry/build/default/outputs/default/entry-default-signed.hap";
            string file = Path.Combine(Environment.CurrentDirectory, relative.Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(file));
            File.WriteAllText(file, Environment.GetEnvironmentVariable("JOBS_OHOS_OUTPUT_MODE") == "empty" ? "" : "fixture");
        }
        Console.WriteLine("\x1b[32mfixture " + name + "\x1b[0m \\033[31mliteral\\033[0m");
        return 0;
    }
}
'@
            [IO.File]::WriteAllText($fixtureSource, $fixtureCode, (New-Object Text.UTF8Encoding($false)))
            $csc = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
            & $csc /nologo /target:exe ('/out:' + $fixtureExecutable) $fixtureSource
            if ($LASTEXITCODE -ne 0) { throw '临时 OpenHarmony 工具夹具编译失败。' }
        }
        foreach ($relative in $harmonyTools + @('bin/flutter.bat')) {
            $file = Join-Path $toolHome $relative
            if ($relative -ceq 'bin/flutter.bat') { $file = Join-Path $harmonySdk $relative }
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $file))
            if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
                if ([IO.Path]::GetExtension($file) -ieq '.exe') { [IO.File]::Copy($fixtureExecutable, $file, $true) }
                else {
                    $name = [IO.Path]::GetFileNameWithoutExtension($file)
                    [IO.File]::WriteAllText($file, ('@echo off' + "`r`n" + '@"' + $fixtureExecutable + '" ' + $name + ' %*' + "`r`n" + 'exit /b %errorlevel%' + "`r`n"), (New-Object Text.UTF8Encoding($false)))
                }
            } else {
                [IO.File]::WriteAllText($file, $fixtureBody.Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
                & /bin/chmod 700 $file
                if ($LASTEXITCODE -ne 0) { throw '临时 OpenHarmony 工具权限设置失败。' }
            }
        }
        [void][IO.Directory]::CreateDirectory((Join-Path $toolHome 'sdk'))
        $env:DEVECO_STUDIO_HOME = $toolHome
        $env:FLUTTER_OHOS_SDK = $harmonySdk
        $env:JOBS_OHOS_TRACE = $trace
        foreach ($name in @('JAVA_HOME', 'NODE_HOME', 'TOOL_HOME', 'DEVECO_SDK_HOME', 'HOS_SDK_HOME', 'OHOS_SDK_HOME', 'OHOS_BUILD_TARGET', 'BUILD_MODE', 'FLAVOR', 'JOBS_OHOS_FAIL_TOOL', 'JOBS_OHOS_FAIL_COMMAND', 'JOBS_OHOS_HELP_MODE', 'JOBS_OHOS_OUTPUT_MODE')) { [Environment]::SetEnvironmentVariable($name, $null, 'Process') }
        $baseEnvironment = @{}
        foreach ($name in @('PATH', 'JAVA_HOME', 'NODE_HOME', 'TOOL_HOME', 'DEVECO_SDK_HOME', 'NO_COLOR', 'FORCE_COLOR', 'CLICOLOR', 'ANSI_COLORS_DISABLED', 'npm_config_color')) { $baseEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
        & $harmony { Assert-JobsPackagerWindowsPlatform 'OpenHarmony' }
        Assert-PackagerThrows { & $harmony { param($Path) Invoke-JobsPackagerHarmonyBuild -Project $Path } $project } '没有 ohos 平台时给出明确诊断'
        Assert-Packager (-not [IO.File]::Exists($trace)) '缺平台不调用任何工具'
        [void][IO.Directory]::CreateDirectory((Join-Path $project 'ohos'))
        foreach ($name in @('build-profile.json5', 'oh-package.json5')) { [IO.File]::WriteAllText((Join-Path $project ('ohos/' + $name)), '{}') }
        Assert-Packager ((& $harmony { param($Path, $Sdk) Get-JobsPackagerFlutter -Project $Path -SdkRoot $Sdk } $project $harmonySdk) -ceq (Join-Path $harmonySdk 'bin/flutter.bat')) '显式 OpenHarmony SDK 优先于 FVM，使用 Windows flutter.bat'
        Assert-PackagerThrows { & $harmony { param($Path) Get-JobsPackagerFlutter -Project $Path -SdkRoot 'not-absolute' } $project } '显式 SDK 无效不静默回退 FVM'
        Assert-PackagerThrows { & $harmony { Get-JobsPackagerHarmonyOptions -Type 'apk' } } 'OpenHarmony 拒绝 Android 产物类型'
        Assert-PackagerThrows { & $harmony { Get-JobsPackagerHarmonyOptions -Flavor 'demo' } } 'OpenHarmony 明确拒绝 flavor 静默退回 default 风险'
        $harmonyOptions = & $harmony { Get-JobsPackagerHarmonyOptions }
        Assert-Packager ($harmonyOptions.Type -ceq 'hap' -and $harmonyOptions.Mode -ceq 'release') 'OpenHarmony 默认 release HAP'
        & $harmony { param($Path) Invoke-JobsPackagerHarmonyBuild -Project $Path } $project
        $records = @(Get-Content -LiteralPath $trace)
        Assert-Packager (($records | Where-Object { $_ -match '^flutter\|' }) -join '~' -cmatch 'flutter\|--version\|.*~flutter\|build hap --help\|.*~flutter\|pub get\|.*~flutter\|build hap --release\|') '真实假 SDK 健康及能力通过后才依赖和 release HAP'
        foreach ($name in $baseEnvironment.Keys) { Assert-Packager ([Environment]::GetEnvironmentVariable($name, 'Process') -ceq $baseEnvironment[$name]) ('OpenHarmony 成功后恢复环境：' + $name) }
        $env:JOBS_OHOS_HELP_MODE = 'color'
        [IO.File]::WriteAllText($trace, '')
        & $harmony { param($Path) Invoke-JobsPackagerHarmonyBuild -Project $Path -Type 'all' -Mode 'profile' } $project
        $records = @(Get-Content -LiteralPath $trace)
        Assert-Packager (@($records | Where-Object { $_ -match '^flutter\|pub get\|' }).Count -eq 1) 'OpenHarmony all 只获取依赖一次'
        Assert-Packager (($records | Where-Object { $_ -match '^flutter\|build (hap|app) --profile\|' }) -join '~' -cmatch '^flutter\|build hap --profile\|.*~flutter\|build app --profile\|') 'OpenHarmony HAP→APP 顺序，profile 和彩色能力 help 可用'
        [IO.File]::WriteAllText($trace, '')
        $env:BUILD_MODE = 'debug'
        $env:OHOS_BUILD_TARGET = 'app'
        & $harmony { param($Path) Invoke-JobsPackagerHarmonyBuild -Project $Path } $project
        Assert-Packager (@(Get-Content -LiteralPath $trace | Where-Object { $_ -match '^flutter\|build app --debug\|' }).Count -eq 1) 'OpenHarmony 读取 OHOS_BUILD_TARGET 与 BUILD_MODE'
        $env:BUILD_MODE = $null
        $env:OHOS_BUILD_TARGET = $null
        foreach ($mode in @('generic', 'error')) {
            $env:JOBS_OHOS_HELP_MODE = $mode
            [IO.File]::WriteAllText($trace, '')
            Assert-PackagerThrows { & $harmony { param($Path) Invoke-JobsPackagerHarmonyBuild -Project $Path } $project } ('普通 SDK / 失败 help 拒绝：' + $mode)
            Assert-Packager (@(Get-Content -LiteralPath $trace | Where-Object { $_ -match '^flutter\|pub get\|' }).Count -eq 0) '能力检查失败不拉依赖'
            foreach ($name in $baseEnvironment.Keys) { Assert-Packager ([Environment]::GetEnvironmentVariable($name, 'Process') -ceq $baseEnvironment[$name]) ('能力失败后恢复环境：' + $name) }
        }
        $env:JOBS_OHOS_HELP_MODE = $null
        foreach ($tool in @('node', 'npm', 'ohpm', 'hvigorw', 'java')) {
            $env:JOBS_OHOS_FAIL_TOOL = $tool
            [IO.File]::WriteAllText($trace, '')
            Assert-PackagerThrows { & $harmony { param($Path) Invoke-JobsPackagerHarmonyBuild -Project $Path } $project } ('健康失败停止：' + $tool)
            $records = @(Get-Content -LiteralPath $trace)
            Assert-Packager ($records[-1] -match ('^' + $tool + '\|')) ('健康链在故障工具停止：' + $tool)
            Assert-Packager (@($records | Where-Object { $_ -match '^flutter\|pub get\|' }).Count -eq 0) '健康失败不拉依赖'
        }
        $env:JOBS_OHOS_FAIL_TOOL = $null
        foreach ($command in @('pub get', 'build hap --release')) {
            $env:JOBS_OHOS_FAIL_COMMAND = $command
            [IO.File]::WriteAllText($trace, '')
            $message = ''
            try { & $harmony { param($Path) Invoke-JobsPackagerHarmonyBuild -Project $Path -Type 'all' } $project } catch { $message = $_.Exception.Message }
            Assert-Packager ($message -match '退出码 37') ('真实子进程失败码写入诊断：' + $command)
            Assert-Packager (@(Get-Content -LiteralPath $trace | Where-Object { $_ -match '^flutter\|build app --release\|' }).Count -eq 0) '首阶段失败不构建 APP'
            foreach ($name in $baseEnvironment.Keys) { Assert-Packager ([Environment]::GetEnvironmentVariable($name, 'Process') -ceq $baseEnvironment[$name]) ('构建失败后恢复环境：' + $name) }
        }
        $env:JOBS_OHOS_FAIL_COMMAND = 'build app --release'
        [IO.File]::WriteAllText($trace, '')
        $appFailure = ''
        try { & $harmony { param($Path) Invoke-JobsPackagerHarmonyBuild -Project $Path -Type 'all' } $project } catch { $appFailure = $_.Exception.Message }
        Assert-Packager ($appFailure -match '退出码 37') 'HAP 完成后 APP 构建失败仍判整体失败'
        $records = @(Get-Content -LiteralPath $trace | Where-Object { $_ -match '^flutter\|build (hap|app) --release\|' })
        Assert-Packager ($records.Count -eq 2 -and $records[0] -match 'build hap' -and $records[1] -match 'build app') '双产物 release 按 HAP→APP 执行，不漏任一步'
        $env:JOBS_OHOS_FAIL_COMMAND = $null
        $env:JOBS_OHOS_HELP_MODE = 'app-unsupported'
        [IO.File]::WriteAllText($trace, '')
        Assert-PackagerThrows { & $harmony { param($Path) Invoke-JobsPackagerHarmonyBuild -Project $Path -Type 'all' } $project } 'SDK 只支持 HAP 不支持 APP 时拒绝双产物任务'
        Assert-Packager (@(Get-Content -LiteralPath $trace | Where-Object { $_ -match '^flutter\|pub get\|' }).Count -eq 0) '缺 APP 能力在获取依赖前停止'
        $env:JOBS_OHOS_HELP_MODE = $null
        Remove-Item -LiteralPath (Join-Path $project 'ohos/build') -Force -Recurse -ErrorAction SilentlyContinue
        $env:JOBS_OHOS_OUTPUT_MODE = 'missing-app'
        Assert-PackagerThrows { & $harmony { param($Path) Invoke-JobsPackagerHarmonyBuild -Project $Path -Type 'all' } $project } '两条构建均返回成功但没有 APP 时不能仅凭 HAP 报成功'
        $env:JOBS_OHOS_OUTPUT_MODE = 'app-removes-hap'
        Assert-PackagerThrows { & $harmony { param($Path) Invoke-JobsPackagerHarmonyBuild -Project $Path -Type 'all' } $project } 'APP 构建成功但移除先前 HAP 时整体失败，最终必须同时有两类包'
        Assert-Packager ([IO.File]::Exists((Join-Path $project 'ohos/build/outputs/default/ohos-default-signed.app'))) '最终存续回归确实完成 APP 构建'
        Assert-Packager ([IO.File]::Exists((Join-Path $project 'ohos/entry/build/default/outputs/default/other-unvalidated.hap'))) '最终检查不重新扫描并挑选未验证的其它 HAP 冒充原产物'
        $env:JOBS_OHOS_OUTPUT_MODE = $null
        foreach ($mode in @('missing', 'empty')) {
            foreach ($directory in @('ohos/entry/build', 'ohos/build')) { Remove-Item -LiteralPath (Join-Path $project $directory) -Force -Recurse -ErrorAction SilentlyContinue }
            $env:JOBS_OHOS_OUTPUT_MODE = $mode
            Assert-PackagerThrows { & $harmony { param($Path) Invoke-JobsPackagerHarmonyBuild -Project $Path } $project } ('成功命令但缺失或空 OpenHarmony 产物拒绝：' + $mode)
        }
        $env:JOBS_OHOS_OUTPUT_MODE = $null
        foreach ($relative in @('build/ohos/node_modules/pkg/outputs/fake.hap', 'ohos/entry/build/intermediates/outputs/fake.hap')) {
            $file = Join-Path $project $relative
            [void][IO.Directory]::CreateDirectory((Split-Path -Parent $file))
            [IO.File]::WriteAllText($file, 'not a final artifact')
        }
        Assert-PackagerThrows { & $harmony { param($Path) Get-JobsPackagerHarmonyArtifacts -Project $Path -Type 'hap' } $project } '依赖和 intermediates 中的 HAP 不冒充最终产物'
        $oldArtifact = Join-Path $project 'ohos/entry/build/default/outputs/default/custom-unsigned.hap'
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $oldArtifact))
        [IO.File]::WriteAllText($oldArtifact, 'cached custom artifact')
        (Get-Item -LiteralPath $oldArtifact).LastWriteTimeUtc = [DateTime]::UtcNow.AddDays(-2)
        $env:JOBS_OHOS_OUTPUT_MODE = 'missing'
        & $harmony { param($Path) Invoke-JobsPackagerHarmonyBuild -Project $Path } $project
        Assert-Packager (@(& $harmony { param($Path) Get-JobsPackagerHarmonyArtifacts -Project $Path -Type 'hap' } $project).Count -eq 1) '自定义命名和非空 Hvigor 缓存产物保留'
        $env:JOBS_OHOS_OUTPUT_MODE = $null
        $env:JOBS_OHOS_HELP_MODE = 'color'
        $probe = & $harmony { param($File, $Path) Invoke-JobsPackagerProbe -File $File -Arguments @('build', 'hap', '--help') -Project $Path } (Join-Path $harmonySdk 'bin/flutter.bat') $project
        Assert-Packager ($probe.ExitCode -eq 0 -and $probe.Output.IndexOf([char]27) -lt 0 -and -not $probe.Output.Contains('\033[')) 'Probe 去除 ANSI 后用于能力判断'
        $env:JOBS_OHOS_HELP_MODE = $null
        Assert-PackagerThrows { & $harmony { param($Path) Invoke-JobsPackagerProbe -File (Join-Path $Path 'missing-tool.exe') -Arguments @('--version') -Project $Path } $project } '无法启动工具不会沿用旧成功退出码'
        $env:FLUTTER_OHOS_SDK = $null
        $env:HOS_SDK_HOME = Join-Path $toolHome 'sdk'
        & $harmony { param($Path) Initialize-JobsPackagerHarmonyEnvironment } $project
        Assert-Packager ($env:DEVECO_SDK_HOME -ceq $env:HOS_SDK_HOME) '兼容 HOS_SDK_HOME，配置只作用当前进程'
        # 用真实平台分支检查第三选项、HAP 默认及取消；不触发真实工具。
        & $harmony {
            $script:MenuCalls = @()
            $script:MenuBuild = ''
            function script:Select-JobsPackagerChoice {
                param($Title, $Choices)
                $script:MenuCalls += ($Choices -join '|')
                if ($Title -ceq '选择打包平台') { return 'OpenHarmony' }
                return 'HAP + APP'
            }
            function script:Invoke-JobsPackagerHarmonyBuild { param($Project, $Type) $script:MenuBuild = $Type }
        }
        & $harmony { param($Path) Invoke-JobsFlutterPackageAction -Target $Path } $project
        $menuCalls = @(& $harmony { $script:MenuCalls })
        Assert-Packager ($menuCalls[0] -ceq 'Android|iOS|OpenHarmony') '单一菜单的 fzf 平台列表追加 OpenHarmony'
        Assert-Packager ($menuCalls[1] -ceq 'HAP|APP|HAP + APP') 'OpenHarmony HAP 默认、APP 与两者'
        Assert-Packager ((& $harmony { $script:MenuBuild }) -ceq 'all') 'OpenHarmony 平台分支映射 all'
        & $harmony { $script:MenuBuild = ''; function script:Select-JobsPackagerChoice { param($Title, $Choices) if ($Title -ceq '选择打包平台') { return 'OpenHarmony' }; return $null } }
        & $harmony { param($Path) Invoke-JobsFlutterPackageAction -Target $Path } $project
        Assert-Packager ((& $harmony { $script:MenuBuild }) -ceq '') '取消 OpenHarmony 产物不开始构建'
    } finally {
        foreach ($name in $savedEnvironment.Keys) {
            if ($null -eq $savedEnvironment[$name]) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
        }
    }

    if ($Native -and [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        & (Join-Path $package 'Scripts/Build.ps1') -OutputRoot (Join-Path $release 'bin')
        $probe = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'FlutterRunnerMenuProbe.cs') -Raw -Encoding UTF8
        $probe = $probe.Replace('JobsFlutterRunnerTests', 'JobsFlutterPackagerTests').Replace('239D7884-83C5-4D66-AB0C-14A2667DCD61', '64A7C5BE-E031-4E89-A2D7-75C3F62B1AC9')
        if (-not ('JobsFlutterPackagerTests.MenuProbe' -as [type])) { Add-Type -TypeDefinition $probe }
        $library = Join-Path $release 'bin/JobsFlutterPackagerContextMenu.dll'
        Assert-Packager ([JobsFlutterPackagerTests.MenuProbe]::Count($library, $project, 0) -eq 1) '原生菜单在项目背景插入一项'
        Assert-Packager ([JobsFlutterPackagerTests.MenuProbe]::Count($library, $project, 1) -eq 1) '原生菜单在所选项目插入一项'
        Assert-Packager ([JobsFlutterPackagerTests.MenuProbe]::Count($library, $temporary, 0) -eq 0) '原生菜单在普通背景不插入'
        Assert-Packager ([JobsFlutterPackagerTests.MenuProbe]::Count($library, $temporary, 1) -eq 0) '原生菜单在普通文件夹不插入'
        Assert-Packager ([JobsFlutterPackagerTests.MenuProbe]::Count($library, (Join-Path $project 'android'), 1) -eq 0) '原生菜单不沿用父工程'
        Assert-Packager ([JobsFlutterPackagerTests.MenuProbe]::Count($library, $project, 2) -eq 0) '原生菜单多选不插入'
    }
    Write-Host ('PASS: FlutterPackager.Tests.ps1 (' + $script:assertions + ' assertions)')
    Write-Host 'SKIP: Windows PowerShell 5.1、MSVC DLL、真实 Explorer / CMD / fzf 与 Android / HarmonyOS 构建需 Windows 实机。'
} finally {
    $env:LOCALAPPDATA = $savedLocal
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}
