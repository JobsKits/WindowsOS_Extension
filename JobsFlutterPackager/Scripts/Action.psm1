# Action.psm1 | JobsFlutterPackager
# Created by Jobs on 2026年10月20日，星期二.
# CMD 内用 fzf 选择 Android / iOS / HarmonyOS；按平台检查现有 SDK 和构建工具。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

function Assert-JobsPackagerDirectory {
    param([string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path) -or -not [IO.Directory]::Exists($Path)) {
        throw "目标必须是存在的绝对目录：$Path"
    }
    $item = New-Object IO.DirectoryInfo ([IO.Path]::GetFullPath($Path))
    $current = $item
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "不处理符号链接或目录联接：$($current.FullName)"
        }
        $current = $current.Parent
    }
    return $item.FullName
}

function Assert-JobsPackagerPlainFile {
    param([string]$Path)
    $attributes = [IO.File]::GetAttributes($Path)
    if (($attributes -band [IO.FileAttributes]::Directory) -ne 0 -or ($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "配置必须是普通文件：$Path"
    }
}

function Test-JobsPackagerPathEntry {
    param([string]$Path)
    # File.Exists/Test-Path 会将悬空链接当作不存在，GetAttributes 仍能识别链接本身。
    try { [void][IO.File]::GetAttributes($Path); return $true }
    catch [IO.FileNotFoundException] { return $false }
    catch [IO.DirectoryNotFoundException] { return $false }
}

function Remove-JobsYamlComment {
    param([string]$Line)
    $quote = [char]0
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $character = $Line[$i]
        if ($quote -eq [char]34 -and $character -eq [char]92) { $i++; continue }
        if ($quote -eq [char]39 -and $character -eq [char]39 -and $i + 1 -lt $Line.Length -and $Line[$i + 1] -eq [char]39) { $i++; continue }
        if ($quote -ne [char]0) {
            if ($character -eq $quote) { $quote = [char]0 }
            continue
        }
        if ($character -eq [char]39 -or $character -eq [char]34) { $quote = $character; continue }
        if ($character -eq '#' -and ($i -eq 0 -or [char]::IsWhiteSpace($Line[$i - 1]))) {
            return $Line.Substring(0, $i).TrimEnd()
        }
    }
    return $Line.TrimEnd()
}

function ConvertFrom-JobsYamlAtom {
    param([string]$Value)
    $valueText = $Value.Trim()
    if ($valueText -match '^''([^'']*)''$' -or $valueText -match '^"([^"\\]*)"$') { return $Matches[1] }
    return $valueText
}

function ConvertFrom-JobsYamlFlowMap {
    param([string]$Text)
    $value = $Text.Trim()
    if (-not $value.StartsWith('{') -or -not $value.EndsWith('}')) { throw '只支持明确的 YAML 映射，不支持别名、标签或多行 flow 结构。' }
    $body = $value.Substring(1, $value.Length - 2)
    $parts = New-Object 'System.Collections.Generic.List[string]'
    $depth = 0
    $quote = [char]0
    $start = 0
    for ($i = 0; $i -lt $body.Length; $i++) {
        $character = $body[$i]
        if ($quote -eq [char]34 -and $character -eq [char]92) { $i++; continue }
        if ($quote -ne [char]0) {
            if ($character -eq $quote) { $quote = [char]0 }
            continue
        }
        if ($character -eq [char]39 -or $character -eq [char]34) { $quote = $character; continue }
        if ($character -eq '{' -or $character -eq '[') { $depth++ }
        if ($character -eq '}' -or $character -eq ']') { $depth-- }
        if ($depth -lt 0) { throw 'YAML flow 映射括号不匹配。' }
        if ($character -eq ',' -and $depth -eq 0) { $parts.Add($body.Substring($start, $i - $start)); $start = $i + 1 }
    }
    if ($quote -ne [char]0 -or $depth -ne 0) { throw 'YAML flow 映射未闭合。' }
    $parts.Add($body.Substring($start))
    $map = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal)
    for ($partIndex = 0; $partIndex -lt $parts.Count; $partIndex++) {
        $part = $parts[$partIndex]
        if ([string]::IsNullOrWhiteSpace($part)) {
            if ($partIndex -eq $parts.Count - 1 -and ($map.Count -gt 0 -or [string]::IsNullOrWhiteSpace($body))) { continue }
            throw 'YAML flow 映射存在空项。'
        }
        if ($part -notmatch '^\s*(?<key>[A-Za-z_][A-Za-z0-9_-]*|''[^'']+''|"[^"\\]+")\s*:\s*(?<value>.*?)\s*$' -or
            $part -match '^\s*[A-Za-z_][A-Za-z0-9_-]*\s*:\S') { throw '无法可靠读取 YAML flow 映射；未引用键的冒号后须留空格。' }
        $key = ConvertFrom-JobsYamlAtom $Matches['key']
        $entry = $Matches['value']
        if ($map.ContainsKey($key)) { throw "YAML 存在重复键：$key" }
        $map[$key] = $entry
    }
    return $map
}

function Test-JobsFlutterPubspec {
    param([string]$Text)
    $Text = $Text.TrimStart([char]0xfeff)
    if ($Text.IndexOf([char]0) -ge 0) { return $false }
    # 只解释 dependencies.flutter.sdk，不能把 description、注释或 flutter_test 当作 Flutter 项目。
    $lines = @($Text -split '\r?\n' | ForEach-Object { Remove-JobsYamlComment $_ })
    if (@($lines | Where-Object { $_.Trim() -in @('---', '...') }).Count -gt 0) { return $false }
    if (@($lines | Where-Object { $_ -match '^\s*\t' }).Count -gt 0) { return $false }
    $roots = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -cmatch '^(?:dependencies|''dependencies''|"dependencies")\s*:\s*(.*)$') {
            $roots += [pscustomobject]@{ Index = $i; Value = $Matches[1] }
        }
    }
    if ($roots.Count -ne 1) { return $false }
    try {
        if (-not [string]::IsNullOrWhiteSpace($roots[0].Value)) {
            $dependencies = ConvertFrom-JobsYamlFlowMap $roots[0].Value
            if (-not $dependencies.ContainsKey('flutter')) { return $false }
            $flutter = ConvertFrom-JobsYamlFlowMap $dependencies['flutter']
            return $flutter.ContainsKey('sdk') -and (ConvertFrom-JobsYamlAtom $flutter['sdk']) -ceq 'flutter'
        }
        $entries = @()
        for ($i = $roots[0].Index + 1; $i -lt $lines.Count; $i++) {
            if ([string]::IsNullOrWhiteSpace($lines[$i])) { continue }
            if ($lines[$i] -notmatch '^\s') { break }
            if ($lines[$i] -notmatch '^(?<indent> +)(?<key>[A-Za-z_][A-Za-z0-9_-]*|''[^'']+''|"[^"\\]+")\s*:\s*(?<value>.*)$') { return $false }
            $entries += [pscustomobject]@{ Indent = $Matches['indent'].Length; Key = (ConvertFrom-JobsYamlAtom $Matches['key']); Value = $Matches['value']; Index = $i }
        }
        if ($entries.Count -eq 0) { return $false }
        $minimum = ($entries | Measure-Object -Property Indent -Minimum).Minimum
        $declarations = @($entries | Where-Object { $_.Indent -eq $minimum -and $_.Key -ceq 'flutter' })
        if ($declarations.Count -ne 1) { return $false }
        $declaration = $declarations[0]
        if (-not [string]::IsNullOrWhiteSpace($declaration.Value)) {
            $flutter = ConvertFrom-JobsYamlFlowMap $declaration.Value
            return $flutter.ContainsKey('sdk') -and (ConvertFrom-JobsYamlAtom $flutter['sdk']) -ceq 'flutter'
        }
        $children = @()
        foreach ($entry in $entries) {
            if ($entry.Index -le $declaration.Index) { continue }
            if ($entry.Indent -le $declaration.Indent) { break }
            $children += $entry
        }
        if ($children.Count -eq 0) { return $false }
        $childIndent = ($children | Measure-Object -Property Indent -Minimum).Minimum
        $sdk = @($children | Where-Object { $_.Indent -eq $childIndent -and $_.Key -ceq 'sdk' })
        return $sdk.Count -eq 1 -and (ConvertFrom-JobsYamlAtom $sdk[0].Value) -ceq 'flutter'
    }
    catch { return $false }
}

function Assert-JobsFlutterProject {
    param([string]$Directory)
    [void](Assert-JobsPackagerDirectory $Directory)
    $pubspec = Join-Path $Directory 'pubspec.yaml'
    Assert-JobsPackagerPlainFile $pubspec
    if ((Get-Item -LiteralPath $pubspec).Length -gt 1MB) { throw 'pubspec.yaml 超过 1 MiB，停止读取。' }
    if (-not (Test-JobsFlutterPubspec (Get-Content -LiteralPath $pubspec -Raw -Encoding UTF8))) {
        throw '目标同层 pubspec.yaml 必须明确声明 dependencies.flutter.sdk: flutter；不会扫描子目录或沿用父工程。YAML 别名、标签及多行 flow 映射请先改成常见 block 写法。'
    }
}

function ConvertTo-JobsPackagerPlainText {
    param([string]$Text)
    $escape = [regex]::Escape([string][char]27)
    $plain = $Text -replace ($escape + '\][^\x07]*(?:\x07|' + $escape + '\\)'), ''
    $plain = $plain -replace ($escape + '\[[0-?]*[ -/]*[@-~]'), ''
    return $plain -replace '\\(?:033|e|x1[bB])\[[0-9;]*m', ''
}

function Write-JobsPackagerMessage {
    param([string]$Message)
    $ErrorActionPreference = 'Stop'
    $safe = (ConvertTo-JobsPackagerPlainText $Message) -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    Write-Host $safe
    if (Get-Variable -Name PackagerLog -Scope Script -ErrorAction SilentlyContinue) {
        [IO.File]::AppendAllText($script:PackagerLog, ($safe + [Environment]::NewLine), (New-Object Text.UTF8Encoding($true)))
    }
}

function Get-JobsPackagerFlutter {
    param([string]$Project, [string]$SdkRoot)
    if ($SdkRoot) {
        if (-not [IO.Path]::IsPathRooted($SdkRoot) -or -not [IO.Directory]::Exists($SdkRoot)) { throw 'FLUTTER_OHOS_SDK / FlutterSdk 必须是现有 SDK 绝对目录。' }
        foreach ($name in @('flutter.bat', 'flutter.exe')) {
            $candidate = Join-Path $SdkRoot ('bin/' + $name)
            if ([IO.File]::Exists($candidate)) { return [IO.Path]::GetFullPath($candidate) }
        }
        throw '指定 OpenHarmony SDK 中没有 bin/flutter.bat 或 bin/flutter.exe。'
    }
    foreach ($candidate in @((Join-Path $Project '.fvm/flutter_sdk/bin/flutter.bat'), (Join-Path $Project '.fvm/flutter_sdk/bin/flutter.exe'))) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return [IO.Path]::GetFullPath($candidate) }
    }
    foreach ($binding in @('.fvmrc', '.fvm/fvm_config.json', '.fvm/flutter_sdk')) {
        if (Test-JobsPackagerPathEntry (Join-Path $Project $binding)) {
            throw '项目已绑定 FVM，但项目 Flutter SDK 缺失或不完整。请先恢复对应 SDK；不会改用 PATH 的其它版本。'
        }
    }
    $flutter = Find-JobsExecutable -Name 'flutter.bat' -Candidates @('flutter.exe', 'flutter')
    if (-not $flutter) { throw '未找到 Flutter SDK。请配置 PATH，或先使用 FVM 安装 / 修复项目绑定版本。' }
    return $flutter
}

function Select-JobsPackagerChoice {
    param([string]$Title, [string[]]$Choices)
    $fzf = Find-JobsExecutable -Name 'fzf.exe' -Candidates @('fzf')
    if (-not $fzf) { throw '缺少 fzf。请先在终端执行 winget install --id junegunn.fzf --exact，重新打开终端后重试；本功能不会自动安装或改用编号菜单。' }
    $health = Invoke-JobsProcess -FilePath $fzf -Arguments @('--version') -TimeoutSeconds 10
    if ($health.ExitCode -ne 0) { throw 'fzf --version 检查失败，请修复 fzf 后重试。' }
    $savedOptions = $env:FZF_DEFAULT_OPTS
    $savedOptionsFile = $env:FZF_DEFAULT_OPTS_FILE
    $savedOutputEncoding = $OutputEncoding
    $savedConsoleEncoding = [Console]::OutputEncoding
    try {
        # Windows PowerShell 5.1 默认 ASCII 管道会损坏中文平台名。
        $OutputEncoding = New-Object Text.UTF8Encoding($false)
        [Console]::OutputEncoding = $OutputEncoding
        # 隔离用户 bind / execute 配置，选择器只允许返回提供的单项。
        $env:FZF_DEFAULT_OPTS = ''
        $env:FZF_DEFAULT_OPTS_FILE = ''
        $result = @($Choices | & $fzf --height=40% --reverse --no-multi --prompt ($Title + ' > ') --header '回车确认；Esc / Ctrl+C 取消')
        $code = $LASTEXITCODE
    } finally {
        $env:FZF_DEFAULT_OPTS = $savedOptions
        $env:FZF_DEFAULT_OPTS_FILE = $savedOptionsFile
        $OutputEncoding = $savedOutputEncoding
        [Console]::OutputEncoding = $savedConsoleEncoding
    }
    if ($code -eq 1 -or $code -eq 130) { return $null }
    if ($code -ne 0) { throw ('fzf 选择失败，退出码：' + $code) }
    if ($result.Count -ne 1 -or $result[0] -cnotin $Choices) { throw 'fzf 返回无效选项；没有开始打包。' }
    return $result[0]
}

function Assert-JobsPackagerWindowsPlatform {
    param([string]$Platform)
    if ($Platform -ceq 'iOS') { throw 'Windows 无法构建 iOS 安装包。请在 macOS + Xcode 上使用同名 Flutter打包 菜单；本次没有运行 pub get 或 build。' }
    if ($Platform -cnotin @('Android', 'OpenHarmony')) { throw '无效打包平台。' }
}

function Get-JobsPackagerOptions {
    param([string]$Mode = $env:BUILD_MODE, [string]$Flavor = $env:FLAVOR)
    if ([string]::IsNullOrEmpty($Mode)) { $Mode = 'release' }
    if ($Mode -cnotin @('release', 'debug', 'profile')) { throw 'BUILD_MODE / Mode 只支持 release、debug、profile。' }
    if ($Flavor -and $Flavor -cnotmatch '^[A-Za-z][A-Za-z0-9_-]*$') { throw 'FLAVOR / Flavor 只能包含英文字母、数字、下划线和连字符，并以字母开头。' }
    return [pscustomobject]@{ Mode = $Mode; Flavor = $Flavor }
}

function Assert-JobsPackagerJava17 {
    param([string]$Project)
    $java = $null
    if ($env:JAVA_HOME) {
        $java = Join-Path $env:JAVA_HOME 'bin/java.exe'
        if (-not (Test-Path -LiteralPath $java -PathType Leaf)) { throw 'JAVA_HOME 未指向完整 JDK 17；请修复后重试。' }
    } else {
        $java = Find-JobsExecutable -Name 'java.exe' -Candidates @('java')
    }
    if (-not $java) { throw '未找到 JDK 17，请安装并配置 JAVA_HOME 后重试。' }
    $result = Invoke-JobsProcess -FilePath $java -Arguments @('-version') -WorkingDirectory $Project -TimeoutSeconds 15
    $version = $result.StdOut + $result.StdErr
    if ($result.ExitCode -ne 0 -or $version -notmatch '(?:java|openjdk) version "17(?:\.|"|-)') { throw 'Android 打包沿用 JDK 17 基线；当前 Java 不是 17 或无法运行。请配置 JAVA_HOME。' }
    $javaHome = Split-Path -Parent (Split-Path -Parent $java)
    if (-not (Test-Path -LiteralPath (Join-Path $javaHome 'bin/javac.exe') -PathType Leaf)) { throw '当前 Java 缺少 javac.exe，请使用完整 JDK 17。' }
    # 仅影响本次 PowerShell 和构建子进程，结束后恢复。
    $env:JAVA_HOME = $javaHome
    $env:PATH = (Join-Path $javaHome 'bin') + [IO.Path]::PathSeparator + $env:PATH
    Write-JobsPackagerMessage ('Java 17：' + $java)
}

function Invoke-JobsPackagerTool {
    param([string]$File, [string[]]$Arguments, [string]$Project)
    if (@($Arguments | Where-Object { $_ -cnotmatch '^[A-Za-z0-9._-]+$' }).Count -gt 0) { throw '构建参数不合法。' }
    Write-JobsPackagerMessage ('执行：' + $File + ' ' + ($Arguments -join ' '))
    Push-Location -LiteralPath $Project
    try {
        # PowerShell 5.1 将原生 stderr 包装为 ErrorRecord；用进程退出码判断成功。
        $ErrorActionPreference = 'Continue'
        & $File @Arguments 2>&1 | ForEach-Object { Write-JobsPackagerMessage ([string]$_) }
        $code = $LASTEXITCODE
    } finally { Pop-Location }
    if ($code -ne 0) { throw ('构建命令失败，退出码 ' + $code + '：' + ($Arguments -join ' ')) }
}

function Get-JobsPackagerArtifacts {
    param([string]$Project, [string]$Type, [string]$Mode, [string]$Flavor, [datetime]$StartedUtc)
    $directory = Join-Path $Project 'build/app/outputs/flutter-apk'
    $flavorPart = ''
    if ($Flavor) { $flavorPart = $Flavor.ToLowerInvariant() + '-' }
    $expectedName = 'app-' + $flavorPart + $Mode + '.apk'
    $expectedParent = ''
    if ($Type -eq 'appbundle') {
        $directory = Join-Path $Project 'build/app/outputs/bundle'
        $expectedName = 'app-' + $flavorPart + $Mode + '.aab'
        $expectedParent = $Flavor.ToLowerInvariant() + $Mode
    }
    $found = @()
    if (Test-Path -LiteralPath $directory -PathType Container) {
        foreach ($file in Get-ChildItem -LiteralPath $directory -Recurse -File) {
            if ($file.Length -le 0) { continue }
            $nameMatches = $file.Name -ieq $expectedName
            if ($Type -eq 'appbundle') {
                if ($file.Directory.Name -ine $expectedParent) { continue }
                $nameMatches = $nameMatches -or $file.Name -ieq 'app.aab' -or $file.Name -ieq ('app-' + $Mode + '.aab')
            }
            if (-not $nameMatches) { continue }
            $found += $file.FullName
        }
    }
    if ($found.Count -eq 0) { throw ('命令结束但没有发现对应 ' + $Type + ' 非空产物（mode=' + $Mode + '，flavor=' + $Flavor + '）：' + $directory) }
    return $found
}

function Invoke-JobsPackagerBuild {
    param([string]$Project, [string]$Type, [string]$Mode = $env:BUILD_MODE, [string]$Flavor = $env:FLAVOR)
    $options = Get-JobsPackagerOptions -Mode $Mode -Flavor $Flavor
    if ($Type -cnotin @('apk', 'appbundle', 'all')) { throw '无效 Android 产物类型。' }
    $gradle = Join-Path $Project 'android/gradlew.bat'
    if (-not (Test-Path -LiteralPath $gradle -PathType Leaf)) { throw '缺少 android/gradlew.bat，目标尚未配置 Android 平台。' }
    $flutter = Get-JobsPackagerFlutter $Project
    $savedJava = $env:JAVA_HOME
    $savedPath = $env:PATH
    try {
        Assert-JobsPackagerJava17 $Project
        Write-JobsPackagerMessage ('工程：' + $Project)
        Write-JobsPackagerMessage ('Flutter SDK：' + $flutter)
        Write-JobsPackagerMessage ('产物：' + $Type + '；模式：' + $options.Mode + '；Flavor：' + $options.Flavor)
        Invoke-JobsPackagerTool -File $flutter -Arguments @('pub', 'get') -Project $Project
        $targets = @($Type)
        if ($Type -eq 'all') { $targets = @('apk', 'appbundle') }
        foreach ($target in $targets) {
            $arguments = @('build', $target, ('--' + $options.Mode))
            if ($options.Flavor) { $arguments += @('--flavor', $options.Flavor) }
            $started = [DateTime]::UtcNow
            Invoke-JobsPackagerTool -File $flutter -Arguments $arguments -Project $Project
            $artifacts = @(Get-JobsPackagerArtifacts -Project $Project -Type $target -Mode $options.Mode -Flavor $options.Flavor -StartedUtc $started)
            foreach ($artifact in $artifacts) {
                $file = Get-Item -LiteralPath $artifact
                if ($file.LastWriteTimeUtc -lt $started) { Write-JobsPackagerMessage ('现存产物（构建命令成功，可能复用 Gradle 缓存，请核对）：' + $artifact) }
                else { Write-JobsPackagerMessage ('产物已验证：' + $artifact) }
            }
        }
    } finally {
        $env:JAVA_HOME = $savedJava
        $env:PATH = $savedPath
    }
}

function Get-JobsPackagerHarmonyOptions {
    param([string]$Type = $env:OHOS_BUILD_TARGET, [string]$Mode = $env:BUILD_MODE, [string]$Flavor = $env:FLAVOR)
    if ([string]::IsNullOrEmpty($Type)) { $Type = 'hap' }
    if ($Type -cnotin @('hap', 'app', 'all')) { throw 'OHOS_BUILD_TARGET / Type 只支持 hap、app、all。' }
    if ($Flavor) { throw 'OpenHarmony 暂不接受 FLAVOR / Flavor；部分适配 SDK 会将未知 flavor 静默退回 default，请先移除该参数并核对工程产品配置。' }
    $options = Get-JobsPackagerOptions -Mode $Mode -Flavor ''
    return [pscustomobject]@{ Type = $Type; Mode = $options.Mode }
}

function Initialize-JobsPackagerHarmonyEnvironment {
    $toolHome = $env:DEVECO_STUDIO_HOME
    if (-not $toolHome) { $toolHome = $env:TOOL_HOME }
    if (-not $env:DEVECO_SDK_HOME -and $env:HOS_SDK_HOME) { $env:DEVECO_SDK_HOME = $env:HOS_SDK_HOME }
    if ($toolHome) {
        if (-not [IO.Path]::IsPathRooted($toolHome) -or -not [IO.Directory]::Exists($toolHome)) { throw 'DEVECO_STUDIO_HOME / TOOL_HOME 必须指向现有 DevEco Studio 或 command-line-tools 绝对目录。' }
    } elseif (-not $env:DEVECO_SDK_HOME) {
        $candidates = @()
        foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)})) {
            if (-not $base) { continue }
            foreach ($relative in @('Huawei/DevEco Studio', 'Huawei/DevEcoStudio')) {
                $candidate = Join-Path $base $relative
                if ([IO.Directory]::Exists((Join-Path $candidate 'sdk'))) { $candidates += [IO.Path]::GetFullPath($candidate) }
            }
        }
        $candidates = @($candidates | Select-Object -Unique)
        if ($candidates.Count -gt 1) { throw '发现多个 DevEco Studio，请用 DEVECO_STUDIO_HOME 明确选择。' }
        if ($candidates.Count -eq 1) { $toolHome = $candidates[0] }
    }
    $paths = @()
    if ($toolHome) {
        $env:TOOL_HOME = $toolHome
        if (-not $env:DEVECO_SDK_HOME) { $env:DEVECO_SDK_HOME = Join-Path $toolHome 'sdk' }
        foreach ($relative in @('tools/node/bin', 'tools/node', 'tool/node/bin', 'tool/node', 'tools/ohpm/bin', 'ohpm/bin', 'tools/hvigor/bin', 'hvigor/bin')) {
            $candidate = Join-Path $toolHome $relative
            if ([IO.Directory]::Exists($candidate)) { $paths += $candidate }
        }
        if (-not $env:JAVA_HOME -and [IO.File]::Exists((Join-Path $toolHome 'jbr/bin/java.exe'))) { $env:JAVA_HOME = Join-Path $toolHome 'jbr' }
    }
    if ($env:JAVA_HOME) {
        if (-not [IO.File]::Exists((Join-Path $env:JAVA_HOME 'bin/java.exe'))) { throw 'JAVA_HOME 中没有 bin/java.exe，请修复现有 Java 配置。' }
        $paths = @((Join-Path $env:JAVA_HOME 'bin')) + $paths
    }
    if ($env:NODE_HOME) {
        $nodePath = $null
        foreach ($relative in @('bin/node.exe', 'node.exe')) {
            if ([IO.File]::Exists((Join-Path $env:NODE_HOME $relative))) { $nodePath = Split-Path -Parent (Join-Path $env:NODE_HOME $relative); break }
        }
        if (-not $nodePath) { throw 'NODE_HOME 中没有 node.exe 或 bin/node.exe，请修复现有 Node 配置。' }
        $paths = @($nodePath) + $paths
    }
    if ($paths.Count -gt 0) { $env:PATH = ($paths -join [IO.Path]::PathSeparator) + [IO.Path]::PathSeparator + $env:PATH }
    if (-not $env:DEVECO_SDK_HOME -or -not [IO.Path]::IsPathRooted($env:DEVECO_SDK_HOME) -or -not [IO.Directory]::Exists($env:DEVECO_SDK_HOME)) {
        throw '没有有效 DEVECO_SDK_HOME（兼容 HOS_SDK_HOME）。请准备 HarmonyOS SDK；不会将 OHOS_SDK_HOME 自动视为同义路径。'
    }
    $env:NO_COLOR = '1'
    $env:FORCE_COLOR = '0'
    $env:CLICOLOR = '0'
    $env:ANSI_COLORS_DISABLED = '1'
    $env:npm_config_color = 'false'
    Write-JobsPackagerMessage ('HarmonyOS SDK：' + $env:DEVECO_SDK_HOME)
}

function Invoke-JobsPackagerProbe {
    param([string]$File, [string[]]$Arguments, [string]$Project)
    if (@($Arguments | Where-Object { $_ -cnotmatch '^[A-Za-z0-9._-]+$' }).Count -gt 0) { throw '工具检查参数不合法。' }
    Push-Location -LiteralPath $Project
    try {
        # 通过 PowerShell 启动 .bat / .cmd，兼容 Windows 工具链的脚本入口。
        $ErrorActionPreference = 'Continue'
        $global:LASTEXITCODE = -1
        $output = @(& $File @Arguments 2>&1 | ForEach-Object { [string]$_ })
        $code = $LASTEXITCODE
    } finally { Pop-Location }
    return [pscustomobject]@{ ExitCode = $code; Output = (ConvertTo-JobsPackagerPlainText ($output -join [Environment]::NewLine)) }
}

function Assert-JobsPackagerHarmonyToolchain {
    param([string]$Project, [string]$Flutter, [string[]]$Targets)
    $specifications = @(
        @{ Label = 'Node.js'; Name = 'node.exe'; Candidates = @('node'); Arguments = @('--version') },
        @{ Label = 'npm'; Name = 'npm.cmd'; Candidates = @('npm.bat', 'npm'); Arguments = @('--version') },
        @{ Label = 'ohpm'; Name = 'ohpm.bat'; Candidates = @('ohpm.cmd', 'ohpm'); Arguments = @('--version') },
        @{ Label = 'Hvigor'; Name = 'hvigorw.bat'; Candidates = @('hvigorw.cmd', 'hvigorw'); Arguments = @('--version') },
        @{ Label = 'Java'; Name = 'java.exe'; Candidates = @('java'); Arguments = @('-version') }
    )
    foreach ($specification in $specifications) {
        $file = Find-JobsExecutable -Name $specification.Name -Candidates $specification.Candidates
        if (-not $file) { throw ('缺少 ' + $specification.Label + '，请检查现有 DevEco 工具目录和 PATH；不会自动安装。') }
        Write-JobsPackagerMessage ('检查 ' + $specification.Label + '：' + $file)
        $result = Invoke-JobsPackagerProbe -File $file -Arguments $specification.Arguments -Project $Project
        if ($result.Output) { Write-JobsPackagerMessage $result.Output }
        if ($result.ExitCode -ne 0) { throw ($specification.Label + ' 健康检查失败，退出码 ' + $result.ExitCode + '；没有运行 pub get 或 build。') }
    }
    $version = Invoke-JobsPackagerProbe -File $Flutter -Arguments @('--version') -Project $Project
    if ($version.Output) { Write-JobsPackagerMessage $version.Output }
    if ($version.ExitCode -ne 0) { throw ('Flutter 健康检查失败，退出码 ' + $version.ExitCode + '。') }
    foreach ($target in $Targets) {
        $result = Invoke-JobsPackagerProbe -File $Flutter -Arguments @('build', $target, '--help') -Project $Project
        if ($result.ExitCode -ne 0 -or (ConvertTo-JobsPackagerPlainText $result.Output) -cnotmatch ('flutter\s+build\s+' + $target + '\b')) {
            if ($result.Output) { Write-JobsPackagerMessage $result.Output }
            throw ('此 Flutter SDK 未确认支持 flutter build ' + $target + '，请指定匹配工程的 OpenHarmony 适配 SDK；普通 Android / iOS SDK 无法打 OpenHarmony 包。')
        }
        Write-JobsPackagerMessage ('已确认 SDK 能力：flutter build ' + $target)
    }
}

function Get-JobsPackagerHarmonyArtifacts {
    param([string]$Project, [string]$Type)
    $roots = @((Join-Path $Project 'build/ohos'), (Join-Path $Project 'ohos/build'))
    foreach ($module in Get-ChildItem -LiteralPath (Join-Path $Project 'ohos') -Directory) {
        if (($module.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { $roots += Join-Path $module.FullName 'build' }
    }
    $found = New-Object 'System.Collections.Generic.List[string]'
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($rootPath in $roots) {
        if (-not [IO.Directory]::Exists($rootPath)) { continue }
        try { [void](Assert-JobsPackagerDirectory $rootPath) } catch { continue }
        $pending = New-Object 'System.Collections.Generic.Stack[string]'
        $pending.Push($rootPath)
        while ($pending.Count -gt 0) {
            $directory = $pending.Pop()
            if (([IO.File]::GetAttributes($directory) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            foreach ($entry in Get-ChildItem -LiteralPath $directory -Force) {
                if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                if ($entry.PSIsContainer) {
                    if ($entry.Name -notin @('intermediates', '.hvigor', 'node_modules', 'oh_modules', '.git')) { $pending.Push($entry.FullName) }
                    continue
                }
                if ($entry.Extension -ine ('.' + $Type) -or $entry.Length -le 0) { continue }
                $relative = $entry.FullName.Substring($rootPath.Length).Replace('\', '/')
                if ($rootPath -ne $roots[0] -and $relative -notmatch '/outputs/') { continue }
                if ($seen.Add($entry.FullName)) { $found.Add($entry.FullName) }
            }
        }
    }
    if ($found.Count -eq 0) { throw ('命令结束但没有发现非空 .' + $Type + ' 产物；已检查 build/ohos 与 ohos 各模块的 outputs 目录。') }
    return $found.ToArray()
}

function Invoke-JobsPackagerHarmonyBuild {
    param([string]$Project, [string]$Type = $env:OHOS_BUILD_TARGET, [string]$Mode = $env:BUILD_MODE, [string]$FlutterSdk = $env:FLUTTER_OHOS_SDK, [string]$Flavor = $env:FLAVOR)
    $options = Get-JobsPackagerHarmonyOptions -Type $Type -Mode $Mode -Flavor $Flavor
    foreach ($relative in @('ohos/build-profile.json5', 'ohos/oh-package.json5')) {
        $file = Join-Path $Project $relative
        if (-not [IO.File]::Exists($file)) { throw ('工程缺少 ' + $relative + '，请先完成 ohos 平台适配；不会自动创建或修改平台。') }
        Assert-JobsPackagerPlainFile $file
    }
    $flutter = Get-JobsPackagerFlutter -Project $Project -SdkRoot $FlutterSdk
    $environment = @{}
    foreach ($name in @('PATH', 'JAVA_HOME', 'NODE_HOME', 'TOOL_HOME', 'DEVECO_SDK_HOME', 'NO_COLOR', 'FORCE_COLOR', 'CLICOLOR', 'ANSI_COLORS_DISABLED', 'npm_config_color')) {
        $environment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
    }
    try {
        Initialize-JobsPackagerHarmonyEnvironment
        $targets = @($options.Type)
        if ($options.Type -eq 'all') { $targets = @('hap', 'app') }
        Assert-JobsPackagerHarmonyToolchain -Project $Project -Flutter $flutter -Targets $targets
        Write-JobsPackagerMessage ('工程：' + $Project)
        Write-JobsPackagerMessage ('Flutter SDK：' + $flutter)
        Write-JobsPackagerMessage ('OpenHarmony 产物：' + $options.Type + '；模式：' + $options.Mode + '；签名沿用工程现有配置。')
        Invoke-JobsPackagerTool -File $flutter -Arguments @('pub', 'get') -Project $Project
        $validatedArtifacts = @{}
        foreach ($target in $targets) {
            $started = [DateTime]::UtcNow
            Invoke-JobsPackagerTool -File $flutter -Arguments @('build', $target, ('--' + $options.Mode)) -Project $Project
            $validatedArtifacts[$target] = @(Get-JobsPackagerHarmonyArtifacts -Project $Project -Type $target)
            foreach ($artifact in $validatedArtifacts[$target]) {
                $file = Get-Item -LiteralPath $artifact
                if ($file.Name -match '-unsigned\.') { Write-JobsPackagerMessage ('未签名 OpenHarmony 产物：' + $artifact + '；安装或上架前必须完成签名。') }
                elseif ($file.LastWriteTimeUtc -lt $started) { Write-JobsPackagerMessage ('现存 OpenHarmony 产物（构建命令成功，可能复用 Hvigor 缓存，请核对）：' + $artifact) }
                else { Write-JobsPackagerMessage ('OpenHarmony 产物已验证：' + $artifact) }
            }
        }
        # APP 构建可能重建输出树，只复核本轮已验证路径，不能换用其它旧包。
        if ($targets.Count -gt 1) {
            foreach ($target in $targets) {
                $remaining = @($validatedArtifacts[$target] | Where-Object {
                    try {
                        Assert-JobsPackagerPlainFile $_
                        [void](Assert-JobsPackagerDirectory (Split-Path -Parent $_))
                        (Get-Item -LiteralPath $_).Length -gt 0
                    } catch { $false }
                })
                if ($remaining.Count -eq 0) { throw ('最终检查失败：已验证的非空 .' + $target + ' 产物已消失或被替换，不能报告双产物完成。') }
            }
        }
    } finally {
        foreach ($name in $environment.Keys) {
            if ($null -eq $environment[$name]) { Remove-Item -LiteralPath ('Env:' + $name) -ErrorAction SilentlyContinue }
            else { [Environment]::SetEnvironmentVariable($name, $environment[$name], 'Process') }
        }
    }
}

function Invoke-JobsFlutterHarmonyAction {
    param([string]$Target)
    Write-Host '打包鸿蒙 HAP + APP：只处理所选 Flutter 根目录，固定 release，使用项目 FVM 适配 SDK。'
    Write-Host '会运行 pub get、build hap --release、build app --release 并写入工程；签名沿用工程配置，不安装或切换 SDK。'
    Write-Host '不读取 BUILD_MODE / OHOS_BUILD_TARGET / FLAVOR；Ctrl+C 或任意非空输入取消。'
    Assert-JobsFlutterProject $Target
    try {
        [void](Assert-JobsPackagerDirectory (Join-Path $Target 'lib'))
        [void](Assert-JobsPackagerDirectory (Join-Path $Target 'ohos'))
        foreach ($relative in @('ohos/build-profile.json5', 'ohos/oh-package.json5')) {
            Assert-JobsPackagerPlainFile (Join-Path $Target $relative)
        }
    } catch {
        throw ('请先完成当前 Flutter 项目的鸿蒙平台适配：需要普通非链接的 lib/、ohos/、ohos/build-profile.json5 和 ohos/oh-package.json5。本次未启动构建。详情：' + $_.Exception.Message)
    }
    if (-not [IO.File]::Exists((Join-Path $Target '.fvm/flutter_sdk/bin/flutter.bat')) -and
        -not [IO.File]::Exists((Join-Path $Target '.fvm/flutter_sdk/bin/flutter.exe'))) {
        throw '项目 FVM SDK 缺失；快捷打包不会使用全局或临时覆盖的 Flutter。'
    }
    $confirmation = Read-Host '回车开始打包鸿蒙 HAP + APP，任意非空输入取消'
    if ($null -eq $confirmation -or $confirmation -ne '') { Write-Host '已取消，没有开始打包。'; return }
    $logDirectory = Join-Path (Get-JobsInstallRoot) 'logs'
    [void][IO.Directory]::CreateDirectory($logDirectory)
    $script:PackagerLog = Join-Path $logDirectory ('harmony-' + (Get-Date -Format 'yyyy-MM-dd-HH-mm-ss') + '-' + [guid]::NewGuid().ToString('N') + '.log')
    Write-JobsPackagerMessage ('日志：' + $script:PackagerLog)
    Invoke-JobsPackagerHarmonyBuild -Project $Target -Type 'all' -Mode 'release' -Flavor '' -FlutterSdk ''
    Write-JobsPackagerMessage '鸿蒙 HAP + APP 打包完成；两种产物均已检查，未签名产物需要先完成签名才能安装。'
}

function Invoke-JobsFlutterPackageAction {
    param([string]$Target)
    Write-Host 'Flutter打包：仅处理所选 Flutter 根目录，用 fzf 选择 Android / iOS / OpenHarmony 及产物。'
    Write-Host 'Android / OpenHarmony 会执行 pub get / build 并写入工程；OpenHarmony 须已有 ohos 平台和适配 SDK，iOS 需要 macOS + Xcode。'
    Write-Host '模式默认 release，BUILD_MODE 可设 debug / profile，FLAVOR 指定 flavor；Esc / Ctrl+C 取消。'
    Assert-JobsFlutterProject $Target
    $logDirectory = Join-Path (Get-JobsInstallRoot) 'logs'
    [void][IO.Directory]::CreateDirectory($logDirectory)
    $script:PackagerLog = Join-Path $logDirectory ('package-' + (Get-Date -Format 'yyyy-MM-dd-HH-mm-ss') + '-' + [guid]::NewGuid().ToString('N') + '.log')
    Write-JobsPackagerMessage ('日志：' + $script:PackagerLog)
    $platform = Select-JobsPackagerChoice '选择打包平台' @('Android', 'iOS', 'OpenHarmony')
    if ($null -eq $platform) { Write-JobsPackagerMessage '已取消，没有开始打包。'; return }
    Assert-JobsPackagerWindowsPlatform $platform
    if ($platform -ceq 'OpenHarmony') {
        $options = Get-JobsPackagerHarmonyOptions
        $labels = @{ hap = 'HAP'; app = 'APP'; all = 'HAP + APP' }
        $defaultLabel = $labels[$options.Type]
        $choices = @($defaultLabel) + @('HAP', 'APP', 'HAP + APP' | Where-Object { $_ -cne $defaultLabel })
        $choice = Select-JobsPackagerChoice '选择 OpenHarmony 产物' $choices
        if ($null -eq $choice) { Write-JobsPackagerMessage '已取消，没有开始打包。'; return }
        $type = switch -CaseSensitive ($choice) { 'HAP' { 'hap' } 'APP' { 'app' } 'HAP + APP' { 'all' } default { throw '无效 OpenHarmony 产物选择。' } }
        Invoke-JobsPackagerHarmonyBuild -Project $Target -Type $type
        Write-JobsPackagerMessage 'Flutter HarmonyOS 打包完成；发布要求请结合工程签名配置核对。'
        return
    }
    $choice = Select-JobsPackagerChoice '选择 Android 产物' @('APK', 'AAB', 'APK + AAB')
    if ($null -eq $choice) { Write-JobsPackagerMessage '已取消，没有开始打包。'; return }
    $type = switch -CaseSensitive ($choice) { 'APK' { 'apk' } 'AAB' { 'appbundle' } 'APK + AAB' { 'all' } }
    Invoke-JobsPackagerBuild -Project $Target -Type $type
    Write-JobsPackagerMessage 'Flutter Android 打包完成。'
}

function Invoke-JobsFeature {
    param([Parameter(Mandatory = $true)][string]$Target)
    $directory = Get-JobsDirectory -Target $Target
    Invoke-JobsFlutterPackageAction -Target $directory
}

Export-ModuleMember -Function Invoke-JobsFeature
