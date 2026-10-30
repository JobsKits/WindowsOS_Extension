# ProjectDependencyArchive.ps1 | 原生依赖分层归档与校验导入。
# Created by Jobs on 2026年10月29日，星期四.
# 随 ProjectSetup 加载；只复制所选缓存层，不执行归档中脚本，不覆盖不同内容。

function Read-JobsArchiveDirectory {
    param([string]$Prompt,[string]$Default='',[switch]$MayBeMissing)
    $value = Read-Host $Prompt
    if ([string]::IsNullOrWhiteSpace($value)) { $value = $Default }
    if (-not [IO.Directory]::Exists($value)) { $value = $value.Trim().Trim('"') }
    if (-not $value -or -not [IO.Path]::IsPathRooted($value)) { throw '需要明确的绝对目录；已取消。' }
    $value = [IO.Path]::GetFullPath($value)
    Assert-JobsSetupDirectory $value
    if (-not $MayBeMissing -and -not [IO.Directory]::Exists($value)) { throw ('目录不存在：'+$value) }
    return $value
}

# FVM SDK 链接为正常绑定，只读取其明确目标；其它缓存链接仍由引擎拒绝。
function Get-JobsArchiveFlutter {
    param([string]$Project)
    $root = Join-Path $Project '.fvm/flutter_sdk'
    if (Test-Path -LiteralPath $root) {
        $item = Get-Item -LiteralPath $root -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            $targets = @($item.Target)
            if ($targets.Count -ne 1 -or -not $targets[0]) { throw '项目 SDK 链接目标不明确。' }
            $root = [string]$targets[0]
            if (-not [IO.Path]::IsPathRooted($root)) { $root = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $item.FullName) $root)) }
        }
    } else {
        $profile = Get-JobsSetupProfile $Project
        if ($profile -and $profile.FlutterMode -ceq 'system') { $root = Split-Path -Parent (Split-Path -Parent $profile.FlutterPath) }
        else { $root = Read-JobsArchiveDirectory '输入已有 Flutter SDK 根目录（空输入取消；本动作不安装 SDK）' }
    }
    Assert-JobsSetupDirectory $root
    $flutter = Get-JobsSetupFlutter (Join-Path $root 'bin/flutter.bat') $Project 'system'
    if ($flutter.Architecture -ceq 'unknown') { throw 'SDK 未返回可确认的本机 Dart 架构，不能生成跨架构误用的缓存快照。' }
    return $flutter
}

function Get-JobsArchiveDart {
    param([string]$Project)
    $candidates = @((Join-Path $Project '.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart.exe'))
    if ($env:DART_SDK) { $candidates += Join-Path $env:DART_SDK 'bin/dart.exe' }
    $found = Find-JobsExecutable 'dart.exe' @('dart')
    if ($found) { $candidates += $found }
    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if ([IO.File]::Exists($candidate)) {
            try {
                $probe = Invoke-JobsSetupProcess $candidate @('--version') $Project 30
                if (($probe.StdOut+$probe.StdErr) -match 'Dart SDK version:') { return $candidate }
            } catch { Write-JobsSetupMessage ('Dart 候选不可用：'+$candidate) }
        }
    }
    $sdk = Read-JobsArchiveDirectory '没有可用 Dart，输入已有 Dart SDK 根目录（空输入取消；不会安装运行时）'
    $candidate = Join-Path $sdk 'bin/dart.exe'
    if (-not [IO.File]::Exists($candidate)) { throw '所选目录没有 bin/dart.exe。' }
    $probe = Invoke-JobsSetupProcess $candidate @('--version') $Project 30
    if (($probe.StdOut+$probe.StdErr) -notmatch 'Dart SDK version:') { throw '所选 Dart 无法确认可运行。' }
    return $candidate
}

function Get-JobsArchiveArchitecture {
    if ($env:PROCESSOR_ARCHITEW6432) { return $env:PROCESSOR_ARCHITEW6432.ToLowerInvariant() }
    if ($env:PROCESSOR_ARCHITECTURE) { return $env:PROCESSOR_ARCHITECTURE.ToLowerInvariant() }
    return ('process-'+([IntPtr]::Size*8))
}

# 文件夹名称与工程位置构成类型边界；不允许把任意用户目录作为缓存根。
function Assert-JobsArchiveRoot {
    param([string]$Project,[string]$Kind,[string]$Platform,[string]$Root,[string]$Layer)
    Assert-JobsSetupDirectory $Root
    $leaf = [IO.Path]::GetFileName($Root.TrimEnd('\','/'))
    switch ($Kind) {
        gradle {
            if ($leaf -cne $Layer) { throw ('Gradle 缓存根必须为所选组件 '+$Layer+'，不能选择整个 Gradle 用户目录。') }
            if ($Layer -ceq 'modules-2' -and [IO.Path]::GetFileName((Split-Path -Parent $Root)) -cne 'caches') { throw 'Maven 缓存必须位于 caches/modules-2。' }
        }
        ohos { if ($leaf -cne $Layer) { throw ('鸿蒙缓存层必须为 '+$Layer+'，不能混入其它层。') } }
        native {
            $name = if ($Platform -ceq 'android') { 'app' } else { $Platform }
            $expected = [IO.Path]::GetFullPath((Join-Path $Project ('build/'+$name)))
            if (-not [string]::Equals($expected,[IO.Path]::GetFullPath($Root),[StringComparison]::OrdinalIgnoreCase)) { throw 'native 只处理当前工程 build 下所选目标目录，不能选择整个 build 或其它平台。' }
        }
        precache {
            $normalized = $Root.Replace('\','/').TrimEnd('/')
            if (-not $normalized.EndsWith('/bin/cache/artifacts',[StringComparison]::OrdinalIgnoreCase)) { throw 'SDK 产物根必须为 bin/cache/artifacts，不能选择整个 SDK 或 Dart runtime。' }
        }
        web {
            if ($leaf -cne 'node_modules' -or -not [IO.File]::Exists((Join-Path (Split-Path -Parent $Root) 'package.json'))) { throw 'Web 缓存根必须是存在 package.json 的工程 node_modules。' }
            $parent = [IO.Path]::GetFullPath((Split-Path -Parent $Root))
            if ($parent -cnotin @([IO.Path]::GetFullPath($Project),[IO.Path]::GetFullPath((Join-Path $Project 'web')))) { throw '只处理当前工程根或 web/ 的 node_modules。' }
        }
    }
}

function Get-JobsArchiveCachePlan {
    param([string]$Project,[string]$Kind,[string]$Fzf,$Manifest,[switch]$Import)
    $platform = ''; $version = ''; $cache = ''; $layer = ''; $flutter = $null
    if ($Import) { $platform = [string]$Manifest.platform }
    switch ($Kind) {
        gradle {
            $platform = 'android'; $spec = Get-JobsSetupGradleSpec $Project
            $user = if ($env:GRADLE_USER_HOME) { $env:GRADLE_USER_HOME } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) '.gradle' }
            $components = @('Maven 原生库与插件缓存（modules-2）','工程固定 Wrapper 分发')
            if ($Import -and [string]$Manifest.toolVersion -like '* wrapper') { [array]::Reverse($components) }
            $component = Select-JobsSetupChoice $Fzf '选择 Gradle 归档组件（两类快照不可互换）' $components
            if ($component.StartsWith('Maven')) {
                $layer = 'modules-2'; $cache = Join-Path $user 'caches/modules-2'
                $version = 'Gradle '+$spec.Version.ToString()+' modules'
            } else {
                $layer = $spec.Name.Substring(0,$spec.Name.Length-4)
                $archive = Get-JobsSetupWrapperZip $Project $spec
                $cache = Split-Path -Parent (Split-Path -Parent $archive)
                $version = 'Gradle '+$spec.Version.ToString()+' wrapper'
            }
        }
        ohos {
            $platform = 'ohos'
            $layers = @('oh_modules','.hvigor')
            if ($Import -and [string]$Manifest.toolVersion -like 'Hvigor *') { [array]::Reverse($layers) }
            $layer = Select-JobsSetupChoice $Fzf '选择鸿蒙归档层（单独归档，不能互换）' $layers
            $cache = Join-Path $Project ('ohos/'+$layer)
            $directory = Join-Path $Project 'ohos'
            if ($layer -ceq '.hvigor') {
                $tool = $null
                foreach ($name in @('hvigorw.bat','hvigorw.cmd','hvigorw')) { $candidate = Join-Path $directory $name; if ([IO.File]::Exists($candidate)) { $tool = $candidate; break } }
                if (-not $tool) { throw '缺少工程 Hvigor wrapper，无法确认归档工具版本。' }
                $probe = Invoke-JobsSetupProcess $tool @('--version') $directory 60
                $label = 'Hvigor'
            } else {
                $candidates = @('ohpm.cmd','ohpm')
                foreach ($homePath in @($env:TOOL_HOME,$env:DEVECO_STUDIO_HOME)) {
                    if ($homePath) { foreach ($relative in @('tools/ohpm/bin/ohpm.bat','ohpm/bin/ohpm.bat')) { $candidates += Join-Path $homePath $relative } }
                }
                $tool = Find-JobsExecutable 'ohpm.bat' $candidates
                if (-not $tool) { throw '缺少现有 ohpm，请使用匹配工程的 DevEco 工具环境。' }
                $probe = Invoke-JobsSetupProcess $tool @('--version') $directory 30
                $label = 'OHPM'
            }
            if (($probe.StdOut+$probe.StdErr) -notmatch '(?i)(?:^|\s)v?(\d+\.\d+(?:\.[0-9A-Za-z+._-]+)?)') { throw '无法读取鸿蒙缓存层的真实工具版本。' }
            $version = $label+' '+$Matches[1]
        }
        native {
            if (-not $Import) { $platform = (Select-JobsSetupChoice $Fzf '选择当前工程的构建目标（仅打包该目标目录）' (Get-JobsDependencyPlatforms $Project)).ToLowerInvariant() }
            if ($platform -cnotin @('android','windows','web','ohos')) { throw '当前宿主不能处理此 native 平台。' }
            $name = if ($platform -ceq 'android') { 'app' } else { $platform }
            $cache = Join-Path $Project ('build/'+$name)
            $flutter = Get-JobsArchiveFlutter $Project
            $version = 'Flutter '+$flutter.FrameworkVersion+' arch '+$flutter.Architecture
        }
        precache {
            $flutter = Get-JobsArchiveFlutter $Project
            if (-not $Import) { $platform = (Select-JobsSetupChoice $Fzf '选择本次 SDK 产物使用的平台' (Get-JobsDependencyPlatforms $Project)).ToLowerInvariant() }
            if ($platform -cnotin @('android','windows','web','ohos')) { throw '当前宿主不导入此平台 SDK 产物。' }
            $cache = Join-Path $flutter.Root 'bin/cache/artifacts'
            $version = 'Flutter '+$flutter.FrameworkVersion+' artifacts arch '+$flutter.Architecture
        }
        web {
            $platform = 'web'
            $scopes = @(@($Project,(Join-Path $Project 'web')) | Where-Object { [IO.File]::Exists((Join-Path $_ 'package.json')) })
            if (-not $scopes.Count) { throw 'JS 归档不适用：工程没有 package.json。' }
            if ($Import) {
                $scope = if ([string]$Manifest.toolVersion -like '* scope web') { Join-Path $Project 'web' } else { $Project }
                if ($scope -cnotin $scopes) { throw '目标缺少快照所需的 JS 工程清单。' }
            } elseif ($scopes.Count -eq 1) { $scope = $scopes[0] }
            else { $scope = Select-JobsSetupChoice $Fzf '选择 JS 清单所在目录' $scopes }
            $cache = Join-Path $scope 'node_modules'
            $node = Find-JobsExecutable 'node.exe' @('node')
            if (-not $node) { throw '缺少现有 Node，无法确认 node_modules 的运行时兼容性。' }
            $probe = Invoke-JobsSetupProcess $node @('--version') $scope 30
            if (($probe.StdOut+$probe.StdErr).Trim() -notmatch '^v?(\d+\.\d+\.\d+)$') { throw 'Node 版本输出无效。' }
            $nodeVersion = $Matches[1]
            $architecture = Invoke-JobsSetupProcess $node @('-p','process.arch') $scope 30
            $nodeArchitecture = ($architecture.StdOut+$architecture.StdErr).Trim()
            if ($nodeArchitecture -cnotmatch '^[a-zA-Z0-9_-]+$') { throw 'Node 未返回有效运行时架构。' }
            $scopeName = if ($scope -ceq $Project) { 'root' } else { 'web' }
            $version = 'Node '+$nodeVersion+' arch '+$nodeArchitecture+' scope '+$scopeName
        }
    }
    if ($Import) {
        # 目标由本次环境计算并明确显示，不能沿用快照内的开发机绝对路径。
        $cache = Read-JobsArchiveDirectory ('导入目标根目录（空回车使用 '+$cache+'）') $cache -MayBeMissing
    } else {
        $cache = Read-JobsArchiveDirectory ('导出源根目录（空回车使用 '+$cache+'；可输入同类型缓存根）') $cache
    }
    Assert-JobsArchiveRoot $Project $Kind $platform $cache $layer
    return [pscustomobject]@{Root=$cache;Platform=$platform;ToolVersion=$version}
}

function Invoke-JobsProjectDependencyArchiveAction {
    param([string]$Target,[string]$Action,[switch]$Check)
    if ($Action -cnotmatch '^(export|import)-(gradle|ohos|native|precache|web)-dependencies$') { throw '未知原生依赖归档动作。' }
    $operation = $Matches[1]; $kind = $Matches[2]
    $project = Resolve-JobsTarget $Target
    Assert-JobsSetupDirectory $project
    $identity = Import-Module (Join-Path $PSScriptRoot 'Actions/sdk-manage/Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $identity { param($p) Assert-JobsFlutterProject $p } $project
    if ($Check) {
        Write-Host ('只读归档计划：'+$operation+' / '+$kind+'；工程：'+$project)
        Write-Host '实际运行会选择缓存根和快照目录，核对宿主/目标/工具版本/锁指纹及全部校验；当前未运行工具、联网、复制或写文件。'
        return
    }
    Write-Host ('原生依赖归档：'+$operation+' / '+$kind) -ForegroundColor Red
    Write-Host '只复制所选层；Gradle modules-2 可能含其它工程的共享包，OHPM/Hvigor分开，native是本机目标构建缓存，precache不含SDK源码/Dart，JS不执行归档脚本。'
    Write-Host '仅相同宿主、目标、工具版本与工程锁指纹允许导入；同名不同内容拒绝，导入前精确YES。不保证跨系统或完全离线；分享前检查缓存中的私有内容。'
    if (-not (Test-JobsSetupInteractive)) { throw '需要真实交互终端。' }
    if ((Read-Host '回车继续；任意非空输入取消') -ne '') { throw '已取消，未复制归档。' }
    $saved = Get-JobsSetupEnvironmentSnapshot @('PATH','JAVA_HOME','TOOL_HOME','DEVECO_SDK_HOME','NO_COLOR','FORCE_COLOR','CLICOLOR','ANSI_COLORS_DISABLED','npm_config_color')
    try {
        $logs = Join-Path (Get-JobsInstallRoot) 'logs'
        [void][IO.Directory]::CreateDirectory($logs)
        $script:SetupLog = Join-Path $logs ('native-archive-'+[guid]::NewGuid().ToString('N')+'.log')
        Write-JobsSetupMessage ('归档审计日志：'+$script:SetupLog)
        $fzf = Get-JobsSetupFzf $project
        $manifest = $null
        if ($operation -ceq 'import') {
            $directory = Read-JobsArchiveDirectory '输入或拖入完整原生依赖快照目录（含 manifest.json 与 payload）'
            $file = Join-Path $directory 'manifest.json'; Assert-JobsSetupFile $file
            $manifest = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($manifest.format -cne 'JobsNativeDependencyArchive' -or $manifest.formatVersion -ne 1 -or $manifest.kind -cne $kind) { throw '快照格式/类型不匹配。' }
        } else {
            $desktop = [Environment]::GetFolderPath('DesktopDirectory')
            $directory = Read-JobsArchiveDirectory '导出父目录（空回车使用系统桌面）' $desktop
        }
        $plan = Get-JobsArchiveCachePlan $project $kind $fzf $manifest -Import:($operation -ceq 'import')
        $dart = Get-JobsArchiveDart $project
        $engine = Join-Path $PSScriptRoot 'NativeDependencyArchive.dart'
        Assert-JobsSetupFile $engine
        if (-not [IO.File]::Exists($engine)) { throw '归档引擎缺失，请取得完整发布包。' }
        $arguments = @($engine,$operation,'--project',$project,'--kind',$kind,'--directory',$directory,'--platform',$plan.Platform,'--tool-version',$plan.ToolVersion)
        $arguments += if ($operation -ceq 'import') { @('--target-root',$plan.Root) } else { @('--source-root',$plan.Root) }
        Write-JobsSetupMessage ('缓存层：'+$kind+'；根：'+$plan.Root+'；快照目录：'+$directory+'；版本：'+$plan.ToolVersion)
        # 引擎预检校验全部证据后才确认写入；实际执行仍会重新校验以防等待期间变化。
        $preflight = Invoke-JobsSetupProcess $dart ($arguments+@('--check')) $project 1800
        $proof = $preflight.StdOut | ConvertFrom-Json
        if ($proof.kind -cne $kind) { throw '归档预检未确认本类型。' }
        if ($operation -ceq 'import') {
            if ((Read-Host '输入精确大写 YES 导入；其它输入取消') -cne 'YES') { throw '已取消，未导入缓存。' }
            $arguments += @('--confirm','YES')
        } elseif ((Read-Host '预检已通过，回车导出；任意非空输入取消') -ne '') { throw '已取消，未导出缓存。' }
        [void](Invoke-JobsSetupProcess $dart $arguments $project 3600)
        Write-JobsSetupMessage '所选缓存层归档操作已完成；没有安装依赖或启动应用。'
    } finally {
        Restore-JobsSetupEnvironment $saved
        Remove-Variable SetupLog -Scope Script -ErrorAction SilentlyContinue
    }
}
