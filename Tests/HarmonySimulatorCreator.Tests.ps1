# HarmonySimulatorCreator.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月23日，星期五.
# 临时假 Emulator；不联网、不安装注册、不下载镜像或创建真实设备。
[CmdletBinding()]
param()
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$package = Join-Path $root 'JobsHarmonySimulatorCreator'
$action = Import-Module (Join-Path $package 'Scripts/Action.psm1') -PassThru -DisableNameChecking
$installer = Import-Module (Join-Path $package 'Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
$script:assertions = 0
function Assert-Harmony { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw ('FAIL: ' + $Message) }; $script:assertions++ }
function Assert-HarmonyThrows { param([scriptblock]$Body, [string]$Message, [string]$Pattern = '.'); $caught = ''; try { & $Body | Out-Null } catch { $caught = $_.Exception.Message }; Assert-Harmony ($caught -match $Pattern) ($Message + ' | ' + $caught) }
$temporaryBase = [IO.Path]::GetTempPath()
if ([IO.Directory]::Exists('/private/tmp')) { $temporaryBase = '/private/tmp' }
$temporary = Join-Path $temporaryBase ('JobsHarmonySimulator-' + [guid]::NewGuid().ToString('N'))
$environmentNames = @('LOCALAPPDATA', 'HARMONY_EMULATOR_BIN', 'DEVECO_STUDIO_HOME', 'TOOL_HOME', 'PROCESSOR_ARCHITECTURE', 'PROCESSOR_ARCHITEW6432', 'JOBS_HARMONY_TRACE', 'JOBS_HARMONY_IMAGES', 'JOBS_HARMONY_STATE', 'JOBS_HARMONY_CREATED', 'JOBS_HARMONY_COUNT', 'JOBS_HARMONY_MODE', 'JOBS_HARMONY_FAIL', 'FZF_DEFAULT_OPTS', 'FZF_DEFAULT_OPTS_FILE')
$savedEnvironment = @{}
foreach ($name in $environmentNames) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $env:LOCALAPPDATA = Join-Path $temporary 'Local'
    $env:PROCESSOR_ARCHITECTURE = 'AMD64'
    $env:PROCESSOR_ARCHITEW6432 = $null
    $env:DEVECO_STUDIO_HOME = $null
    $env:TOOL_HOME = $null
    foreach ($name in @('TRACE', 'IMAGES', 'STATE', 'CREATED', 'COUNT')) { [Environment]::SetEnvironmentVariable(('JOBS_HARMONY_' + $name), (Join-Path $temporary ($name.ToLowerInvariant() + '.json')), 'Process') }
    $emulator = Join-Path $temporary 'DevEco 中文 & 100%/tools/emulator/Emulator.exe'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $emulator))
    $body = @'
#!/bin/sh
printf '%s|%s\n' "$#" "$*" >> "$JOBS_HARMONY_TRACE"
if [ "$JOBS_HARMONY_FAIL" = "$1" ]; then echo fixture-error >&2; exit 37; fi
case "$1" in
-help)
    if [ "$JOBS_HARMONY_MODE" = old ]; then echo '-list -start'; else printf '\033[32m-create -imageList -list -start\033[0m\n'; fi ;;
-imageList) cat "$JOBS_HARMONY_IMAGES" ;;
-list)
    count=$(cat "$JOBS_HARMONY_COUNT"); count=$((count + 1)); printf '%s' "$count" > "$JOBS_HARMONY_COUNT"
    if [ "$JOBS_HARMONY_MODE" = race ] && [ "$count" -ge 2 ]; then echo '[{"name":"TestNew"}]'; else cat "$JOBS_HARMONY_STATE"; fi ;;
-create) cp "$JOBS_HARMONY_CREATED" "$JOBS_HARMONY_STATE" ;;
-start) echo fixture-start ;;
*) exit 91 ;;
esac
'@
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $source = Join-Path $temporary 'EmulatorFixture.cs'
        $code = @'
using System;
using System.IO;
using System.Text;
class EmulatorFixture {
    static int Main(string[] args) {
        Console.OutputEncoding = new UTF8Encoding(false);
        File.AppendAllText(Environment.GetEnvironmentVariable("JOBS_HARMONY_TRACE"), args.Length + "|" + String.Join(" ", args) + Environment.NewLine);
        if (args.Length == 0) return 91;
        if (Environment.GetEnvironmentVariable("JOBS_HARMONY_FAIL") == args[0]) { Console.Error.WriteLine("fixture-error"); return 37; }
        string mode = Environment.GetEnvironmentVariable("JOBS_HARMONY_MODE");
        switch(args[0]) {
            case "-help": Console.WriteLine(mode == "old" ? "-list -start" : "\x1b[32m-create -imageList -list -start\x1b[0m"); break;
            case "-imageList": Console.Write(File.ReadAllText(Environment.GetEnvironmentVariable("JOBS_HARMONY_IMAGES"))); break;
            case "-list":
                string countFile = Environment.GetEnvironmentVariable("JOBS_HARMONY_COUNT");
                int count = Int32.Parse(File.ReadAllText(countFile)) + 1; File.WriteAllText(countFile, count.ToString());
                Console.Write(mode == "race" && count >= 2 ? "[{\"name\":\"TestNew\"}]" : File.ReadAllText(Environment.GetEnvironmentVariable("JOBS_HARMONY_STATE"))); break;
            case "-create": File.Copy(Environment.GetEnvironmentVariable("JOBS_HARMONY_CREATED"), Environment.GetEnvironmentVariable("JOBS_HARMONY_STATE"), true); break;
            case "-start": Console.WriteLine("fixture-start"); break;
            default: return 91;
        }
        return 0;
    }
}
'@
        [IO.File]::WriteAllText($source, $code, (New-Object Text.UTF8Encoding($false)))
        $csc = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
        & $csc /nologo /target:exe ('/out:' + $emulator) $source
        if ($LASTEXITCODE -ne 0) { throw '临时 Emulator 夹具编译失败。' }
    } else {
        [IO.File]::WriteAllText($emulator, $body.Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
        & /bin/chmod 700 $emulator
        if ($LASTEXITCODE -ne 0) { throw '临时 Emulator 权限设置失败。' }
    }
    $env:HARMONY_EMULATOR_BIN = $emulator
    $imageJson = '[{"SoftWareVersion":"6.0.0.112","deviceType":"phone","downloaded":"true","osVersion":"HarmonyOS 6.0.1(21)","releaseType":"Release","upgradable":"false"}]'
    function Reset-HarmonyFixture {
        [IO.File]::WriteAllText($env:JOBS_HARMONY_IMAGES, $imageJson)
        [IO.File]::WriteAllText($env:JOBS_HARMONY_TRACE, '')
        [IO.File]::WriteAllText($env:JOBS_HARMONY_STATE, '[]')
        [IO.File]::WriteAllText($env:JOBS_HARMONY_COUNT, '0')
        [IO.File]::WriteAllText($env:JOBS_HARMONY_CREATED, '[{"name":"TestNew","deviceType":"phone","os":{"osVersion":"HarmonyOS 6.0.1(21)"}}]')
        $env:JOBS_HARMONY_MODE = $null
        $env:JOBS_HARMONY_FAIL = $null
        & $action {
            $script:Answers = New-Object 'System.Collections.Generic.Queue[string]'
            foreach ($answer in @('', '', 'skip')) { $script:Answers.Enqueue($answer) }
        }
    }
    & $action {
        function script:Test-JobsHarmonyDesktop { param($Target) return $Target -ceq 'fixture-desktop' }
        function script:Read-JobsHarmonyInput { param($Prompt); if ($script:Answers.Count -eq 0) { throw 'fixture EOF' }; return $script:Answers.Dequeue() }
        function script:Select-JobsHarmonyChoice { param($Title, $Choices) return $Choices[0] }
    }
    Reset-HarmonyFixture
    Assert-Harmony ((& $action { Get-JobsHarmonyArchitecture }) -ceq 'x86_64') 'x64 宿主支持'
    $env:PROCESSOR_ARCHITEW6432 = 'ARM64'
    Assert-HarmonyThrows { & $action { Get-JobsHarmonyArchitecture } } '原生 ARM64 即使模拟 AMD64 也拒绝'
    $env:PROCESSOR_ARCHITEW6432 = $null
    Assert-Harmony ((& $action { Get-JobsHarmonyEmulator }) -ceq $emulator) '显式工具路径支持中文空格与 CMD 元字符'
    Assert-HarmonyThrows { & $action { param($Path) Get-JobsHarmonyEmulator (Join-Path $Path 'missing.exe') } $temporary } '坏显式路径不回退'
    $env:HARMONY_EMULATOR_BIN = $null
    $env:DEVECO_STUDIO_HOME = Join-Path $temporary 'DevEco 中文 & 100%'
    Assert-Harmony ((& $action { Get-JobsHarmonyEmulator }) -ceq $emulator) 'DevEco 根目录工具发现'
    $env:DEVECO_STUDIO_HOME = Join-Path $temporary 'bad-root'
    Assert-HarmonyThrows { & $action { Get-JobsHarmonyEmulator } } '坏显式 DevEco 根目录不回退'
    $env:DEVECO_STUDIO_HOME = $null
    $env:HARMONY_EMULATOR_BIN = $emulator
    $check = & $action { Get-JobsHarmonyCheck }
    Assert-Harmony ($check.Images.Count -eq 1 -and $check.Instances.Count -eq 0) '只读 Check 识别镜像和空实例数组'
    Assert-Harmony ((Get-Content -LiteralPath $env:JOBS_HARMONY_TRACE) -join '~' -ceq '1|-help~3|-imageList -downloaded true~2|-list -details') 'Check 仅官方只读命令，无下载 / 创建 / 启动'
    Assert-Harmony (-not [IO.Directory]::Exists($env:LOCALAPPDATA)) 'Check 不创建日志或安装状态'
    Reset-HarmonyFixture
    $env:JOBS_HARMONY_MODE = 'old'
    Assert-HarmonyThrows { & $action { Get-JobsHarmonyCheck } } '旧 Emulator / Android 工具能力不足拒绝' '未确认支持 -create'
    Assert-Harmony (@(Get-Content -LiteralPath $env:JOBS_HARMONY_TRACE).Count -eq 1) '能力失败不继续查询或创建'
    Reset-HarmonyFixture
    [IO.File]::WriteAllText($env:JOBS_HARMONY_IMAGES, '[]')
    Assert-HarmonyThrows { & $action { Invoke-JobsHarmonySimulatorAction -Target 'fixture-desktop' -Name 'TestNew' } } '缺镜像提示 Device Manager 并停止' 'Device Manager'
    Assert-Harmony (-not ((Get-Content -LiteralPath $env:JOBS_HARMONY_TRACE) -join ' ').Contains('-create ')) '缺镜像不创建'
    foreach ($bad in @('{}', '[{"deviceType":"phone"}]', '[{"SoftWareVersion":"1","deviceType":"phone","downloaded":"yes","osVersion":"HarmonyOS 6","releaseType":"Release","upgradable":"false"}]')) {
        [IO.File]::WriteAllText($env:JOBS_HARMONY_IMAGES, $bad)
        Assert-HarmonyThrows { & $action { param($File) Get-JobsHarmonyImages $File } $emulator } '拒绝不明确或不完整的镜像 JSON'
    }
    [IO.File]::WriteAllText($env:JOBS_HARMONY_IMAGES, $imageJson.Replace('"Release"', '"Beta"'))
    Assert-Harmony (@(& $action { param($File) Get-JobsHarmonyImages $File } $emulator).Count -eq 0) '未将 Beta 镜像作为 Release 使用'
    [IO.File]::WriteAllText($env:JOBS_HARMONY_IMAGES, $imageJson.Replace('"downloaded":"true"', '"downloaded":false'))
    Assert-Harmony (@(& $action { param($File) Get-JobsHarmonyImages $File } $emulator).Count -eq 0) '不选择未下载镜像'
    foreach ($bad in @('[{"name":123}]', '[{"name":"bad\nname"}]', '[{"name":"One"},{"name":"one"}]', '{"data":[]}')) {
        [IO.File]::WriteAllText($env:JOBS_HARMONY_STATE, $bad)
        Assert-HarmonyThrows { & $action { param($File) Get-JobsHarmonyInstances $File } $emulator } '拒绝数字/控制字符/大小写冲突/未知容器实例'
    }
    [IO.File]::WriteAllText($env:JOBS_HARMONY_STATE, '{"name":"Single"}')
    Assert-Harmony (@(& $action { param($File) Get-JobsHarmonyInstances $File } $emulator).Count -eq 1) '兼容单个具 name 的 JSON 对象'
    Assert-HarmonyThrows { & $action { New-JobsHarmonyName -Existing @([pscustomobject]@{name='testnew'}) -Name 'TestNew' } } '大小写同名拒绝覆盖'
    Assert-HarmonyThrows { & $action { New-JobsHarmonyName -Name 'bad & name' } } '拒绝不合法新名称'
    $first = & $action { New-JobsHarmonyName -Existing @() }
    $second = & $action { New-JobsHarmonyName -Existing @([pscustomobject]@{name=$args[0]}) } $first
    Assert-Harmony ($first -cne $second -and $first -cmatch '^JobsHarmony_[A-Za-z0-9_]+$') '自动名称唯一且适合 CLI'
    Assert-HarmonyThrows { & $action { Get-JobsHarmonyInstanceVersion ([pscustomobject]@{'os.osVersion'='A';os=[pscustomobject]@{osVersion='B'}}) } } '平铺与嵌套系统版本冲突拒绝'
    Reset-HarmonyFixture
    & $action { Invoke-JobsHarmonySimulatorAction -Target 'fixture-desktop' -Name 'TestNew' }
    $records = @(Get-Content -LiteralPath $env:JOBS_HARMONY_TRACE)
    Assert-Harmony ($records -join '~' -ceq '1|-help~3|-imageList -downloaded true~2|-list -details~2|-list -details~6|-create TestNew -deviceType phone -osVersion HarmonyOS 6.0.1(21)~2|-list -details') '创建前重读并使用准确 -create NAME 契约，版本完整保持单 argv'
    Assert-Harmony (@($records | Where-Object { $_ -match '-start|-install|-force|-license|-name' }).Count -eq 0) '跳过启动，始终不下载/强制/接受许可/虚构-name参数'
    Reset-HarmonyFixture
    & $action { $script:Answers.Clear(); foreach($answer in @('', '', '')) { $script:Answers.Enqueue($answer) } }
    & $action { Invoke-JobsHarmonySimulatorAction -Target 'fixture-desktop' -Name 'TestNew' }
    Assert-Harmony ((Get-Content -LiteralPath $env:JOBS_HARMONY_TRACE)[-1] -ceq '2|-start TestNew') '本人选择后才启动新实例'
    Reset-HarmonyFixture
    $env:JOBS_HARMONY_MODE = 'race'
    Assert-HarmonyThrows { & $action { Invoke-JobsHarmonySimulatorAction -Target 'fixture-desktop' -Name 'TestNew' } } '确认期间新增同名实例时停止' '拒绝覆盖'
    Assert-Harmony (@(Get-Content -LiteralPath $env:JOBS_HARMONY_TRACE | Where-Object { $_ -match '\|-create ' }).Count -eq 0) '并发同名不调用创建'
    Reset-HarmonyFixture
    $env:JOBS_HARMONY_FAIL = '-create'
    Assert-HarmonyThrows { & $action { Invoke-JobsHarmonySimulatorAction -Target 'fixture-desktop' -Name 'TestNew' } } '真实假创建失败传播退出码' '退出码 37'
    Assert-Harmony (-not ((Get-Content -LiteralPath $env:JOBS_HARMONY_TRACE) -join ' ').Contains('-start ')) '创建失败不启动'
    Reset-HarmonyFixture
    [IO.File]::WriteAllText($env:JOBS_HARMONY_CREATED, '[]')
    Assert-HarmonyThrows { & $action { Invoke-JobsHarmonySimulatorAction -Target 'fixture-desktop' -Name 'TestNew' } } '退出0但回读缺实例不能成功' '保留现场'
    Reset-HarmonyFixture
    [IO.File]::WriteAllText($env:JOBS_HARMONY_CREATED, '[{"name":"TestNew","deviceType":"tablet","os":{"osVersion":"HarmonyOS 6.0.1(21)"}}]')
    Assert-HarmonyThrows { & $action { Invoke-JobsHarmonySimulatorAction -Target 'fixture-desktop' -Name 'TestNew' } } '回读产品类型不匹配拒绝' '保留现场'
    Reset-HarmonyFixture
    [IO.File]::WriteAllText($env:JOBS_HARMONY_CREATED, 'non-json output')
    Assert-HarmonyThrows { & $action { Invoke-JobsHarmonySimulatorAction -Target 'fixture-desktop' -Name 'TestNew' } } '创建后未知顶层输出保留现场' '详情回读失败'
    Reset-HarmonyFixture
    & $action { $script:Answers.Clear(); $script:Answers.Enqueue('cancel') }
    Assert-HarmonyThrows { & $action { Invoke-JobsHarmonySimulatorAction -Target 'fixture-desktop' -Name 'TestNew' } } '初始取消不调用工具' '已取消'
    Assert-Harmony ((Get-Item -LiteralPath $env:JOBS_HARMONY_TRACE).Length -eq 0) '初始取消零工具调用'
    Reset-HarmonyFixture
    & $action { $script:Answers.Clear(); $script:Answers.Enqueue(''); $script:Answers.Enqueue('cancel') }
    Assert-HarmonyThrows { & $action { Invoke-JobsHarmonySimulatorAction -Target 'fixture-desktop' -Name 'TestNew' } } '创建确认取消不创建' '已取消'
    Assert-Harmony (@(Get-Content -LiteralPath $env:JOBS_HARMONY_TRACE | Where-Object { $_ -match '\|-create ' }).Count -eq 0) '确认取消不调用创建'
    Assert-HarmonyThrows { & $action { Invoke-JobsHarmonySimulatorAction -Target 'ordinary-folder' } } '业务入口复检桌面边界' '仅适用于系统桌面'
    $manifest = Get-Content -LiteralPath (Join-Path $package 'Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $release = Join-Path $temporary 'release'
    & $installer { param($Path,$Dest) New-JobsPackageRelease -PackagePath $Path -Destination $Dest } $package $release | Out-Null
    $plan = @(& $installer { param($Manifest,$Release) Get-JobsPackageRegistryPlan -Manifest $Manifest -ReleasePath $Release -PowerShellPath 'powershell.exe' } $manifest $release)
    Assert-Harmony ($plan.Count -eq 2 -and $plan[0].Key.Contains('DesktopBackground') -and $plan[0].Key.Contains('shellex') -and $plan[1].Key -match '95E5B535-2EB8-48CA-98B5-A14D17A0A859') '独立桌面handler与CLSID，不扩展文件夹'
    foreach ($file in @('Run.cmd','Scripts/Action.psm1','Scripts/CreateHarmonySimulator.ps1','Scripts/DesktopScope.h','Scripts/ContextMenu.cpp')) { Assert-Harmony ([IO.File]::Exists((Join-Path $release $file))) ('独立发布完整：'+$file) }
    $selector = Import-Module (Join-Path $package 'Scripts/Action.psm1') -PassThru -DisableNameChecking -Force
    & $selector { function script:Find-JobsExecutable { param($Name,$Candidates) return $null }; function script:Read-JobsHarmonyInput { param($Prompt) return '' } }
    Assert-Harmony ((& $selector { Select-JobsHarmonyChoice '镜像' @('手机中文','平板') }) -ceq '手机中文') '无 fzf 编号回车选择第一项'
    & $selector { function script:Read-JobsHarmonyInput { param($Prompt) throw 'fixture EOF' } }
    Assert-HarmonyThrows { & $selector { Select-JobsHarmonyChoice '镜像' @('手机') } } 'EOF 不执行默认选项' 'EOF'
    Write-Host ('PASS: HarmonySimulatorCreator.Tests.ps1 (' + $script:assertions + ' assertions)')
    Write-Host 'SKIP: Windows PowerShell 5.1、真实 Emulator.exe/详情格式、MSVC/Explorer、许可与真实创建启动需 Windows 实机。'
} finally {
    foreach ($name in $savedEnvironment.Keys) {
        if ($null -eq $savedEnvironment[$name]) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }
        else { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
    }
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}
