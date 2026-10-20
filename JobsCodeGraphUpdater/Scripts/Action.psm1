# Action.psm1
# JobsCodeGraphUpdater
# Created by Jobs on 2026年10月18日，星期日.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Common.psm1') -DisableNameChecking

function Write-JobsWorkerMessage {
    param([string]$Message)
    $safe = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    $safe = $safe -replace '(?im)(authorization\s*[:=]\s*)[^\r\n]+', '$1[已省略]'
    $safe = $safe -replace '(?im)((?:access[_-]?token|authorization|password|secret)\s*[:=]\s*)\S+', '$1[已省略]'
    Write-Host $safe
    Write-JobsLog $safe
}

function Assert-JobsOrdinaryDirectory {
    param([string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path) -or -not [IO.Directory]::Exists($Path)) {
        throw "目标必须是已存在的绝对目录：$Path"
    }
    $directory = New-Object IO.DirectoryInfo ([IO.Path]::GetFullPath($Path))
    $current = $directory
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "不处理符号链接、目录联接或其它重解析目录：$($current.FullName)"
        }
        $current = $current.Parent
    }
    return $directory.FullName
}

function Assert-JobsOrdinaryFile {
    param([string]$Path)
    if (-not [IO.File]::Exists($Path)) { throw "缺少文件：$Path" }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "不处理重解析文件：$Path"
    }
}

function Test-JobsSamePath {
    param([string]$First, [string]$Second)
    foreach ($path in @($First, $Second)) {
        if ([string]::IsNullOrWhiteSpace($path) -or -not [IO.Path]::IsPathRooted($path)) { return $false }
        if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT -and $path -notmatch '^(?:[A-Za-z]:[\\/]|[\\/]{2}[^\\/]+[\\/][^\\/]+(?:[\\/]|$))') { return $false }
    }
    $left = [IO.Path]::GetFullPath($First).TrimEnd('\', '/')
    $right = [IO.Path]::GetFullPath($Second).TrimEnd('\', '/')
    return [string]::Equals($left, $right, [StringComparison]::OrdinalIgnoreCase)
}

function Invoke-JobsCheckedProcess {
    param([string]$Executable, [string[]]$Arguments, [string]$Directory,
        [int]$TimeoutSeconds = 30, [switch]$Quiet)
    Write-JobsLog ("执行：{0} {1}" -f $Executable, (($Arguments | ForEach-Object { Quote-JobsArgument $_ }) -join ' '))
    $result = Invoke-JobsProcess -FilePath $Executable -Arguments $Arguments -WorkingDirectory $Directory -TimeoutSeconds $TimeoutSeconds
    if (-not $Quiet) {
        if ($result.StdOut) { Write-JobsWorkerMessage $result.StdOut.TrimEnd() }
        if ($result.StdErr) { Write-JobsWorkerMessage $result.StdErr.TrimEnd() }
    }
    if ($result.ExitCode -ne 0) {
        if ($Quiet -and $result.StdErr) { Write-JobsWorkerMessage $result.StdErr.TrimEnd() }
        throw "命令失败（退出码 $($result.ExitCode)）：$Executable"
    }
    return $result
}

function Get-JobsPackageEntry {
    param([string]$PackageDirectory, [string]$PackageName, [string]$CommandName)
    if (-not (Test-Path -LiteralPath $PackageDirectory -PathType Container)) { return $null }
    [void](Assert-JobsOrdinaryDirectory $PackageDirectory)
    $packagePath = Join-Path $PackageDirectory 'package.json'
    if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { return $null }
    Assert-JobsOrdinaryFile $packagePath
    $package = Get-Content -LiteralPath $packagePath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($package.name -ne $PackageName) { return $null }
    if ($PackageName -eq '@colbymchenry/codegraph' -and $package.version -ne '1.6.2') { return $null }
    $bin = if ($package.bin -is [string]) { $package.bin } else { $package.bin.$CommandName }
    if ([string]::IsNullOrWhiteSpace($bin) -or [IO.Path]::IsPathRooted($bin)) { throw 'npm 包命令入口不合法。' }
    $root = [IO.Path]::GetFullPath($PackageDirectory).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $entry = [IO.Path]::GetFullPath((Join-Path $PackageDirectory $bin))
    if (-not $entry.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) { throw 'npm 包命令入口越过包目录。' }
    Assert-JobsOrdinaryFile $entry
    return $entry
}

function Get-JobsCodeGraphCommand {
    param([string]$Node, [string]$Prefix)
    $packages = @((Join-Path $Prefix 'node_modules\@colbymchenry\codegraph'))
    $shim = Find-JobsExecutable -Name 'codegraph.cmd' -Candidates @((Join-Path $Prefix 'node_modules\.bin\codegraph.cmd'))
    if ($shim) {
        $shimDirectory = [IO.Path]::GetDirectoryName($shim)
        $packages += Join-Path $shimDirectory 'node_modules\@colbymchenry\codegraph'
        $packages += Join-Path ([IO.Path]::GetDirectoryName($shimDirectory)) '@colbymchenry\codegraph'
    }
    foreach ($package in $packages | Select-Object -Unique) {
        $entry = Get-JobsPackageEntry $package '@colbymchenry/codegraph' 'codegraph'
        if ($entry) {
            $platformName = 'codegraph-' + $script:CodeGraphPlatform
            $bundles = @(
                (Join-Path ([IO.Path]::GetDirectoryName($package)) $platformName),
                (Join-Path $package ('node_modules\@colbymchenry\' + $platformName))
            )
            foreach ($bundle in $bundles) {
                $metadata = Join-Path $bundle 'package.json'
                if (-not (Test-Path -LiteralPath $metadata -PathType Leaf)) { continue }
                [void](Assert-JobsOrdinaryDirectory $bundle)
                Assert-JobsOrdinaryFile $metadata
                $platform = Get-Content -LiteralPath $metadata -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($platform.name -ne ('@colbymchenry/' + $platformName) -or $platform.version -ne '1.6.2') { continue }
                $runtime = Join-Path $bundle 'node.exe'
                $cli = Join-Path $bundle 'lib\dist\bin\codegraph.js'
                Assert-JobsOrdinaryFile $runtime
                Assert-JobsOrdinaryFile $cli
                return @{ Executable = $runtime; Prefix = @('--liftoff-only', $cli); SchemaNode = $runtime }
            }
        }
    }
    if ($shim) {
        $directory = [IO.Path]::GetDirectoryName($shim)
        foreach ($bundle in @($directory, [IO.Path]::GetDirectoryName($directory))) {
            $metadata = Join-Path $bundle 'lib\package.json'
            if (-not (Test-Path -LiteralPath $metadata -PathType Leaf)) { continue }
            [void](Assert-JobsOrdinaryDirectory $bundle)
            Assert-JobsOrdinaryFile $metadata
            $package = Get-Content -LiteralPath $metadata -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($package.name -ne '@colbymchenry/codegraph' -or $package.version -ne '1.6.2') { continue }
            $runtime = Join-Path $bundle 'node.exe'
            $cli = Join-Path $bundle 'lib\dist\bin\codegraph.js'
            Assert-JobsOrdinaryFile $runtime
            Assert-JobsOrdinaryFile $cli
            return @{ Executable = $runtime; Prefix = @('--liftoff-only', $cli); SchemaNode = $runtime }
        }
    }
    return $null
}

function Assert-JobsCodeGraphVersion {
    param([hashtable]$Command, [string]$Directory)
    $result = Invoke-JobsCheckedProcess $Command.Executable ($Command.Prefix + @('--version')) $Directory
    if ($result.StdOut.Trim() -notmatch '^(?:CodeGraph\s+)?v?1\.6\.2$') {
        throw '此入口只支持已核实无隐式 hooks/agent 安装的 CodeGraph 1.6.2；未知版本不执行建图。'
    }
}

function Assert-JobsCodeGraphRuntime {
    param([hashtable]$Command, [string]$Directory)
    Assert-JobsCodeGraphVersion $Command $Directory
    $probe = 'const {DatabaseSync}=require("node:sqlite");const db=new DatabaseSync(":memory:");try{db.exec("CREATE TABLE health(value TEXT); INSERT INTO health VALUES(''ok'')");if(db.prepare("SELECT value FROM health").get().value!=="ok")throw Error("SQLite probe failed");}finally{db.close();}process.stdout.write("SQLite ok");'
    [void](Invoke-JobsCheckedProcess $Command.SchemaNode @('-e', $probe) $Directory -Quiet)
    $help = (Invoke-JobsCheckedProcess $Command.Executable ($Command.Prefix + @('--help')) $Directory -Quiet).StdOut
    foreach ($name in @('init', 'sync', 'status')) {
        if ($help -notmatch ('\b' + $name + '\b')) { throw "CodeGraph 缺少必需命令：$name" }
    }
    Write-JobsWorkerMessage "健康：CodeGraph 1.6.2、随包 Node 与 SQLite → $($Command.Executable)"
}

function Assert-JobsCodeGraphHost {
    if ($PSVersionTable.PSVersion -lt [version]'5.1' -or $PSVersionTable.PSEdition -ne 'Desktop') {
        throw '工具链阻塞在 Windows PowerShell 5.1 Desktop；请使用本包 .cmd 安装及菜单入口。'
    }
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $digest = [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes('Jobs'))).Replace('-', '').ToLowerInvariant()
        if ($digest -cne '2f17a0f8d518e491c5a0c490b2c1991828dd87d173994ba40996e1da59d4e368') { throw '.NET SHA-256 不可用。' }
    } finally { $hash.Dispose() }
    $architecture = [string]$env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $architecture = $env:PROCESSOR_ARCHITEW6432 }
    $script:CodeGraphPlatform = switch ($architecture.ToUpperInvariant()) {
        'AMD64' { 'win32-x64' }
        'ARM64' { 'win32-arm64' }
        default { throw 'CodeGraph 1.6.2 只提供 Windows x64/ARM64 运行包。' }
    }
    Write-JobsWorkerMessage "健康：PowerShell $($PSVersionTable.PSVersion)、.NET $([Environment]::Version)、$script:CodeGraphPlatform"
}

function Get-JobsCodeGraphNodeTools {
    param([string]$Directory)
    $candidates = @('node.exe')
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if ($base) { $candidates += Join-Path $base 'nodejs\node.exe'; $candidates += Join-Path $base 'Programs\nodejs\node.exe' }
    }
    $visited = @()
    foreach ($candidate in $candidates) {
        $node = Find-JobsExecutable -Name $candidate -Candidates @()
        if (-not $node -or $node -in $visited) { continue }
        $visited += $node
        try {
            $version = (Invoke-JobsCheckedProcess $node @('--version') $Directory -Quiet).StdOut.Trim()
            if ($version -notmatch '^v(\d+)\.' -or [int]$Matches[1] -lt 20 -or [int]$Matches[1] -ge 25) { throw 'CodeGraph 1.6.2 安装工具链需要 Node.js >=20 且 <25。' }
            $probe = 'if(!require("node:fs").statSync(process.execPath).isFile())throw Error("runtime missing");process.stdout.write(require("node:crypto").createHash("sha256").update("Jobs").digest("hex"));'
            $digest = (Invoke-JobsCheckedProcess $node @('-e', $probe) $Directory -Quiet).StdOut.Trim()
            if ($digest -cne '2f17a0f8d518e491c5a0c490b2c1991828dd87d173994ba40996e1da59d4e368') { throw 'Node.js 标准库体检结果不正确。' }
            $npm = Get-JobsPackageEntry (Join-Path ([IO.Path]::GetDirectoryName($node)) 'node_modules\npm') 'npm' 'npm'
            if (-not $npm) { throw '此 Node.js 安装缺少匹配的 npm JavaScript 入口。' }
            $npmVersion = (Invoke-JobsCheckedProcess $node @($npm, '--version', '--offline') $Directory -Quiet).StdOut.Trim()
            if ($npmVersion -notmatch '^\d+\.\d+\.\d+') { throw 'npm 没有返回有效版本。' }
            $npmPrefix = (Invoke-JobsCheckedProcess $node @($npm, 'config', 'get', 'prefix', '--offline') $Directory -Quiet).StdOut.Trim()
            $npmRoot = (Invoke-JobsCheckedProcess $node @($npm, 'root', '--global', '--offline') $Directory -Quiet).StdOut.Trim()
            if ([string]::IsNullOrWhiteSpace($npmPrefix) -or [string]::IsNullOrWhiteSpace($npmRoot) -or
                -not [IO.Path]::IsPathRooted($npmPrefix) -or -not [IO.Path]::IsPathRooted($npmRoot)) { throw 'npm 配置或全局包路径不可用。' }
            Write-JobsWorkerMessage "健康：Node.js $version → $node；npm $npmVersion → $npm"
            return @{ Node = $node; NpmEntry = $npm }
        } catch { Write-JobsWorkerMessage ("上游体检：{0} → {1}" -f $node, $_.Exception.Message) }
    }
    Write-JobsWorkerMessage '上游体检：Node.js/npm 缺失或损坏；已有健康的 CodeGraph 随包运行时不依赖这层。'
    return $null
}

function Get-JobsCodeGraphWinget {
    param([string]$Directory)
    $winget = Find-JobsExecutable -Name 'winget.exe' -Candidates @()
    if ($winget) {
        try {
            $version = (Invoke-JobsCheckedProcess $winget @('--version') $Directory -Quiet).StdOut.Trim()
            if ($version -notmatch '^v?\d+\.\d+') { throw 'WinGet 没有返回有效版本。' }
            [void](Invoke-JobsCheckedProcess $winget @('--info') $Directory -Quiet)
            Write-JobsWorkerMessage "健康：WinGet $version → $winget"
            return $winget
        } catch { Write-JobsWorkerMessage ("上游体检：WinGet → " + $_.Exception.Message) }
    }
    Write-JobsWorkerMessage '上游体检：WinGet 不可用；仅在缺少健康 Node.js/npm、需要安装工具链时阻塞。'
    return $null
}

function Update-JobsCodeGraphSessionPath {
    # 只合并安装器新登记的路径到本进程，不覆盖用户或系统的持久 PATH。
    $paths = @($env:PATH -split [IO.Path]::PathSeparator)
    foreach ($scope in @('User', 'Machine')) {
        $paths += @([Environment]::GetEnvironmentVariable('PATH', $scope) -split [IO.Path]::PathSeparator)
    }
    $env:PATH = (@($paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique) -join [IO.Path]::PathSeparator)
}

function Repair-JobsCodeGraphNodeTools {
    param([string]$Winget, [string]$Directory)
    if (-not $Winget) {
        Write-JobsWorkerMessage '官方修复来源：https://learn.microsoft.com/windows/package-manager/winget/'
        Write-JobsWorkerMessage 'Node.js 官方安装包：https://nodejs.org/en/download'
        throw '工具链阻塞在 WinGet/App Installer；请修复该层或安装官方 Node.js/npm 后重试。'
    }
    Write-JobsWorkerMessage '安装来源：WinGet 官方 winget 源；OpenJS.NodeJS.LTS，仅选 24.x。Windows 原生不使用 WSL Homebrew。'
    $available = (Invoke-JobsCheckedProcess $Winget @('show', '--id', 'OpenJS.NodeJS.LTS', '--exact', '--versions', '--source', 'winget', '--accept-source-agreements', '--disable-interactivity') $Directory 120 -Quiet).StdOut
    $versions = @([regex]::Matches($available, '(?m)^\s*(24\.\d+\.\d+)\s*$') | ForEach-Object { [version]$_.Groups[1].Value } | Sort-Object -Descending)
    if ($versions.Count -eq 0) { throw 'WinGet 官方源没有可核实的 Node.js 24.x；停止，不安装不兼容的新 major。' }
    $version = $versions[0].ToString()
    [void](Invoke-JobsCheckedProcess $Winget @('show', '--id', 'OpenJS.NodeJS.LTS', '--exact', '--version', $version, '--source', 'winget', '--accept-source-agreements', '--disable-interactivity') $Directory 120)
    Write-JobsWorkerMessage "将强制重跑 Node.js $version 官方安装器，可能替换现有损坏或不兼容的 Node.js、登记其 PATH 并请求系统授权；本包不主动提权。"
    if ((Read-Host '按回车安装/修复 Node.js/npm；输入任意字符取消') -ne '') { throw '已取消。' }
    [void](Invoke-JobsCheckedProcess $Winget @('install', '--id', 'OpenJS.NodeJS.LTS', '--exact', '--version', $version, '--source', 'winget', '--force', '--accept-source-agreements', '--accept-package-agreements', '--disable-interactivity') $Directory 900)
    Update-JobsCodeGraphSessionPath
    $tools = Get-JobsCodeGraphNodeTools $Directory
    if (-not $tools) { throw 'Node.js/npm 一次安装/修复后仍不健康；停止，不继续安装 CodeGraph。' }
    return $tools
}

function Assert-JobsGraphFiles {
    param([string]$Directory)
    $graph = Join-Path $Directory '.codegraph'
    [void](Assert-JobsOrdinaryDirectory $graph)
    foreach ($entry in Get-ChildItem -LiteralPath $graph -Force) {
        if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "地图中存在重解析条目：$($entry.FullName)" }
    }
    $database = Join-Path $graph 'codegraph.db'
    Assert-JobsOrdinaryFile $database
    $stream = [IO.File]::Open($database, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $header = New-Object byte[] 16
        if ($stream.Read($header, 0, 16) -ne 16 -or [Text.Encoding]::ASCII.GetString($header) -cne "SQLite format 3`0") {
            throw '当前精确地图数据库不是有效的 SQLite 文件；保留原图并停止。'
        }
    } finally { $stream.Dispose() }
    return $database
}

function Get-JobsGraphStatus {
    param([hashtable]$Command, [string]$Directory, [switch]$Complete)
    $database = Assert-JobsGraphFiles $Directory
    # 在 status 的父级回退逻辑之前，只读检查精确数据库，禁止修复或创建空 schema。
    $checkSchema = 'const {DatabaseSync}=require("node:sqlite");const db=new DatabaseSync(process.argv[1],{readOnly:true});try{if(!db.prepare("SELECT 1 FROM sqlite_master WHERE type=''table'' AND name=''nodes'' LIMIT 1").get())throw Error("missing nodes table");const r=db.prepare("PRAGMA quick_check(1)").get();if(Object.values(r)[0]!=="ok")throw Error("database integrity check failed");}finally{db.close();}'
    [void](Invoke-JobsCheckedProcess $Command.SchemaNode @('-e', $checkSchema, $database) $Directory 120 -Quiet)
    $result = Invoke-JobsCheckedProcess $Command.Executable ($Command.Prefix + @('status', '--json', $Directory)) $Directory -Quiet
    try { $status = $result.StdOut | ConvertFrom-Json }
    catch { throw 'CodeGraph 返回了无效 JSON；未继续改动地图。' }
    if ($null -eq $status -or $status.initialized -ne $true -or $status.version -ne '1.6.2' -or
        -not (Test-JobsSamePath $status.projectPath $Directory) -or
        -not (Test-JobsSamePath $status.indexPath (Join-Path $Directory '.codegraph'))) {
        throw 'CodeGraph 项目身份与精确目标不一致；拒绝回退到父目录地图。'
    }
    if ($Complete) {
        if (-not $status.lastIndexed -or $status.index.state -ne 'complete') { throw '地图未报告索引完成。' }
        foreach ($name in @('added', 'modified', 'removed')) {
            if ($null -eq $status.pendingChanges.$name -or $status.pendingChanges.$name -ne 0) { throw "地图仍有待处理变更：$name" }
        }
        if ($null -eq $status.index.pendingRefs -or $status.index.pendingRefs -ne 0) { throw '地图仍有待解析引用。' }
        foreach ($name in @('filesNeedingReindex', 'filesWithParseErrors')) {
            if ($name -in @($status.index.PSObject.Properties.Name) -and $status.index.$name -ne 0) { throw "地图仍有待处理项：$name" }
        }
    }
}

function Invoke-JobsCodeGraphAction {
    param([string]$Directory)
    Write-JobsWorkerMessage "代码地图目标：$(Join-Path $Directory '.codegraph')"
    $variables = @{ CODEGRAPH_DIR = '.codegraph'; CODEGRAPH_TELEMETRY = '0'; DO_NOT_TRACK = '1';
        CODEGRAPH_NO_DOWNLOAD = '1'; CODEGRAPH_NO_WATCH = '0'; CODEGRAPH_NO_DAEMON = '1'; NO_COLOR = '1'; FORCE_COLOR = '0';
        NODE_OPTIONS = ''; NODE_PATH = '' }
    foreach ($name in $variables.Keys) { [Environment]::SetEnvironmentVariable($name, $variables[$name], 'Process') }
    Assert-JobsCodeGraphHost
    $inspectionDirectory = Assert-JobsOrdinaryDirectory (Get-JobsInstallRoot)
    $tools = Get-JobsCodeGraphNodeTools $inspectionDirectory
    $winget = Get-JobsCodeGraphWinget $inspectionDirectory
    $prefix = Join-Path (Get-JobsInstallRoot) 'tools\codegraph'
    $command = $null
    try {
        $command = Get-JobsCodeGraphCommand '' $prefix
        if ($command) { Assert-JobsCodeGraphRuntime $command $Directory }
    } catch {
        Write-JobsWorkerMessage ("CodeGraph 体检失败：" + $_.Exception.Message)
        $command = $null
    }
    if (-not $command) {
        if (-not $tools) { $tools = Repair-JobsCodeGraphNodeTools $winget $inspectionDirectory }
        Write-JobsWorkerMessage '安装来源：https://www.npmjs.com/package/@colbymchenry/codegraph/v/1.6.2'
        Write-JobsWorkerMessage 'npm registry：https://registry.npmjs.org/'
        Write-JobsWorkerMessage "仅安装到用户目录：$prefix"
        if ((Read-Host '按回车安装/修复 CodeGraph；输入任意字符取消') -ne '') { throw '已取消。' }
        # 安装范围和平台由本包控制，不继承会改变 optional 包布局的 npm 进程配置。
        $npmVariables = @{ npm_config_global = 'false'; npm_config_omit = ''; npm_config_include = 'optional';
            npm_config_platform = 'win32'; npm_config_arch = $script:CodeGraphPlatform.Substring('win32-'.Length) }
        foreach ($name in $npmVariables.Keys) { [Environment]::SetEnvironmentVariable($name, $npmVariables[$name], 'Process') }
        [void](Assert-JobsOrdinaryDirectory (Get-JobsInstallRoot))
        $toolsDirectory = [IO.Path]::GetDirectoryName($prefix)
        if (Test-Path -LiteralPath $toolsDirectory) { [void](Assert-JobsOrdinaryDirectory $toolsDirectory) }
        [void][IO.Directory]::CreateDirectory($prefix)
        [void](Assert-JobsOrdinaryDirectory $prefix)
        [void](Invoke-JobsCheckedProcess $tools.Node @($tools.NpmEntry, 'ping', '--registry=https://registry.npmjs.org/', '--fetch-retries=0', '--fetch-timeout=20000') $prefix 30)
        [void](Invoke-JobsCheckedProcess $tools.Node @($tools.NpmEntry, 'install', '--global=false', '--prefix', $prefix, '--os=win32', ('--cpu=' + $npmVariables.npm_config_arch), '--registry=https://registry.npmjs.org/', '--@colbymchenry:registry=https://registry.npmjs.org/', '--include=optional', '--ignore-scripts', '--no-audit', '--no-fund', '@colbymchenry/codegraph@1.6.2') $prefix 600)
        $command = Get-JobsCodeGraphCommand $tools.Node $prefix
        if (-not $command) { throw '安装后仍找不到 CodeGraph 命令入口。' }
        Assert-JobsCodeGraphRuntime $command $Directory
    }
    [void](Assert-JobsOrdinaryDirectory $Directory)
    $graph = Join-Path $Directory '.codegraph'
    if (Test-Path -LiteralPath $graph) {
        Get-JobsGraphStatus $command $Directory
        [void](Invoke-JobsCheckedProcess $command.Executable ($command.Prefix + @('sync', $Directory)) $Directory 900)
    } else {
        [void](Invoke-JobsCheckedProcess $command.Executable ($command.Prefix + @('init', '--yes', $Directory)) $Directory 900)
    }
    Get-JobsGraphStatus $command $Directory -Complete
    Write-JobsWorkerMessage "代码地图更新完成：$graph"
}

function Invoke-JobsFeature {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)

    $directory = Assert-JobsOrdinaryDirectory -Path (Resolve-JobsTarget -Target $Target)
    Invoke-JobsCodeGraphAction -Directory $directory
}

Export-ModuleMember -Function Invoke-JobsFeature
