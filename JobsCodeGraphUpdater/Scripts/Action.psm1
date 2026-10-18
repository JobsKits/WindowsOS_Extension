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
        CODEGRAPH_NO_DOWNLOAD = '1'; CODEGRAPH_NO_WATCH = '0'; CODEGRAPH_NO_DAEMON = '1'; NO_COLOR = '1'; FORCE_COLOR = '0' }
    foreach ($name in $variables.Keys) { [Environment]::SetEnvironmentVariable($name, $variables[$name], 'Process') }
    $node = Find-JobsExecutable -Name 'node.exe' -Candidates @()
    $npm = Find-JobsExecutable -Name 'npm.cmd' -Candidates @()
    if (-not $node -or -not $npm) {
        Start-Process -FilePath 'https://nodejs.org/en/download'
        throw '缺少 Node.js/npm，已打开官方下载页；安装后重新运行，扩展不会修改系统运行环境。'
    }
    [void](Invoke-JobsCheckedProcess $node @('--version') $Directory)
    $script:CodeGraphPlatform = (Invoke-JobsCheckedProcess $node @('-p', 'process.platform + "-" + process.arch') $Directory -Quiet).StdOut.Trim()
    if ($script:CodeGraphPlatform -notin @('win32-x64', 'win32-arm64')) { throw 'CodeGraph 1.6.2 只提供 Windows x64/ARM64 运行包。' }
    $npmEntry = Get-JobsPackageEntry (Join-Path ([IO.Path]::GetDirectoryName($npm)) 'node_modules\npm') 'npm' 'npm'
    if (-not $npmEntry) { throw '无法确认 npm 的原生 JavaScript 入口；请修复官方 Node.js/npm 安装。' }
    [void](Invoke-JobsCheckedProcess $node @($npmEntry, '--version') $Directory)
    $prefix = Join-Path (Get-JobsInstallRoot) 'tools\codegraph'
    $command = Get-JobsCodeGraphCommand $node $prefix
    if ($command) {
        try { Assert-JobsCodeGraphVersion $command $Directory }
        catch { Write-JobsWorkerMessage $_.Exception.Message; $command = $null }
    }
    if (-not $command) {
        Write-JobsWorkerMessage '安装来源：https://www.npmjs.com/package/@colbymchenry/codegraph/v/1.6.2'
        Write-JobsWorkerMessage 'npm registry：https://registry.npmjs.org/'
        Write-JobsWorkerMessage "仅安装到用户目录：$prefix"
        if ((Read-Host '按回车安装/修复 CodeGraph；输入任意字符取消') -ne '') { throw '已取消。' }
        [void](Invoke-JobsCheckedProcess $node @($npmEntry, 'install', '--prefix', $prefix, '--registry=https://registry.npmjs.org/', '--@colbymchenry:registry=https://registry.npmjs.org/', '--include=optional', '--ignore-scripts', '--no-audit', '--no-fund', '@colbymchenry/codegraph@1.6.2') $Directory 600)
        $command = Get-JobsCodeGraphCommand $node $prefix
        if (-not $command) { throw '安装后仍找不到 CodeGraph 命令入口。' }
        Assert-JobsCodeGraphVersion $command $Directory
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
