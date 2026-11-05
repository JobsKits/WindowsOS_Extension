# FlutterDependencyMigration.psm1 | 一键迁移与原始缓存融合。
# 只复用本包引擎和项目 FVM Dart；默认私库，写入前预检，ZIP 校验后才可删除本次产物。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$script:MigrationScripts = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $script:MigrationScripts 'Common.psm1') -DisableNameChecking

function Read-JobsMigrationLine {
    param([string]$Prompt)
    Write-Host ($Prompt + '：') -NoNewline
    return [Console]::ReadLine()
}

function Write-JobsMigrationMessage {
    param([string]$Message)
    $safe = $Message -replace '(?i)([a-z][a-z0-9+.-]*://)[^\s/@]+@', '$1***@'
    $safe = $safe -replace '(?i)(https?://[^\s?#]+)[?#][^\s]*', '$1?[已省略]'
    Write-Host $safe
    if ($script:MigrationLog) {
        [IO.File]::AppendAllText($script:MigrationLog, $safe + [Environment]::NewLine, (New-Object Text.UTF8Encoding($true)))
    }
}

function ConvertFrom-JobsMigrationPath {
    param([string]$Text)
    if ([IO.Directory]::Exists($Text)) { return [IO.Path]::GetFullPath($Text) }
    $value = $Text.Trim()
    if ($value.StartsWith('& ')) { $value = $value.Substring(2).TrimStart() }
    if ($value.Length -ge 2 -and $value[0] -eq [char]34 -and $value[-1] -eq [char]34) {
        $value = $value.Substring(1, $value.Length - 2)
    } elseif ($value.Length -ge 2 -and $value[0] -eq [char]39 -and $value[-1] -eq [char]39) {
        $value = $value.Substring(1, $value.Length - 2).Replace("''", "'")
    }
    if ([string]::IsNullOrWhiteSpace($value) -or -not [IO.Path]::IsPathRooted($value) -or $value.IndexOfAny([char[]]@(0,10,13,34)) -ge 0) { throw '请输入或拖入一个完整文件夹路径。' }
    return [IO.Path]::GetFullPath($value)
}

function Assert-JobsMigrationDirectory {
    param([string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path) -or -not [IO.Directory]::Exists($Path)) { throw ('目录不存在：' + $Path) }
    $item = New-Object IO.DirectoryInfo ([IO.Path]::GetFullPath($Path))
    while ($null -ne $item) {
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw ('不处理链接或目录联接：' + $item.FullName) }
        $item = $item.Parent
    }
}

function Get-JobsMigrationFiles {
    param([string]$Directory)
    Assert-JobsMigrationDirectory $Directory
    $root = [IO.Path]::GetFullPath($Directory).TrimEnd('\','/')
    $pending = New-Object 'Collections.Generic.Stack[string]'
    $pending.Push($root)
    while ($pending.Count -gt 0) {
        foreach ($entry in (New-Object IO.DirectoryInfo ($pending.Pop())).EnumerateFileSystemInfos()) {
            if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw ('产物含链接，停止打包/删除：' + $entry.FullName) }
            if ($entry.Attributes -band [IO.FileAttributes]::Directory) { $pending.Push($entry.FullName); continue }
            [pscustomobject]@{ Path=$entry.FullName; Relative=$entry.FullName.Substring($root.Length+1).Replace('\','/'); Length=$entry.Length }
        }
    }
}

function Get-JobsMigrationStreamHash {
    param([IO.Stream]$Stream)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash($Stream)).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Assert-JobsMigrationZip {
    param([string]$Bundle,[string]$Zip)
    Add-Type -AssemblyName System.IO.Compression
    $files = @(Get-JobsMigrationFiles $Bundle)
    $prefix = [IO.Path]::GetFileName($Bundle.TrimEnd('\','/')) + '/'
    $stream = [IO.File]::OpenRead($Zip)
    $archive = $null
    try {
        $archive = New-Object IO.Compression.ZipArchive ($stream, [IO.Compression.ZipArchiveMode]::Read)
        if ($archive.Entries.Count -ne $files.Count) { throw 'ZIP 文件清单不匹配。' }
        $seen = @{}
        foreach ($file in $files) {
            $name = $prefix + $file.Relative
            $entry = $archive.GetEntry($name)
            if ($null -eq $entry -or $entry.Length -ne $file.Length -or $seen.ContainsKey($name)) { throw ('ZIP 条目缺失或重复：' + $file.Relative) }
            $seen[$name] = $true
            $source = [IO.File]::OpenRead($file.Path)
            $compressed = $entry.Open()
            try {
                if ((Get-JobsMigrationStreamHash $source) -cne (Get-JobsMigrationStreamHash $compressed)) { throw ('ZIP 校验失败或原产物已改变：' + $file.Relative) }
            } finally { $source.Dispose(); $compressed.Dispose() }
        }
        foreach ($entry in $archive.Entries) { if (-not $seen.ContainsKey($entry.FullName)) { throw 'ZIP 包含多余或重复条目。' } }
    } finally { if ($archive) { $archive.Dispose() }; $stream.Dispose() }
}

function Compress-JobsMigrationBundle {
    param([string]$Bundle)
    Add-Type -AssemblyName System.IO.Compression
    $files = @(Get-JobsMigrationFiles $Bundle)
    $prefix = [IO.Path]::GetFileName($Bundle.TrimEnd('\','/')) + '/'
    $zip = $Bundle + '.zip'
    if ([IO.File]::Exists($zip) -or [IO.Directory]::Exists($zip)) { throw '同名 ZIP 已存在；保留原产物，不覆盖。' }
    $temporary = $zip + '.partial-' + [guid]::NewGuid().ToString('N')
    $stream = $null
    $archive = $null
    try {
        $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $archive = New-Object IO.Compression.ZipArchive ($stream, [IO.Compression.ZipArchiveMode]::Create, $true)
        foreach ($file in $files) {
            $entry = $archive.CreateEntry($prefix + $file.Relative, [IO.Compression.CompressionLevel]::Optimal)
            $source = [IO.File]::OpenRead($file.Path)
            $compressed = $entry.Open()
            try { $source.CopyTo($compressed) } finally { $source.Dispose(); $compressed.Dispose() }
        }
        $archive.Dispose(); $archive = $null
        $stream.Dispose(); $stream = $null
        Assert-JobsMigrationZip $Bundle $temporary
        [IO.File]::Move($temporary, $zip)
        return $zip
    } finally {
        if ($archive) { $archive.Dispose() }
        if ($stream) { $stream.Dispose() }
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Get-JobsMigrationSystemDartCandidates {
    $seen = @{}
    foreach ($command in @(Get-Command -Name dart.exe,dart,dart.bat -CommandType Application -All -ErrorAction SilentlyContinue)) {
        $file = $command.Source
        if ([string]::IsNullOrWhiteSpace($file)) { continue }
        $candidate = $null
        if ([IO.Path]::GetExtension($file) -ieq '.exe') { $candidate = $file }
        elseif ([IO.Path]::GetExtension($file) -ieq '.bat') {
            # Flutter 启动 shim 会下载或改写 SDK；只探测其旁边已经存在的原生 Dart。
            $candidate = Join-Path ([IO.Path]::GetDirectoryName($file)) 'cache/dart-sdk/bin/dart.exe'
        }
        if ($candidate -and -not $seen.ContainsKey($candidate)) { $seen[$candidate]=$true; $candidate }
    }
}

function Get-JobsMigrationDart {
    param([string]$Project)
    $worker = Import-Module (Join-Path $script:MigrationScripts 'Actions/import-dependencies/Scripts/Action.psm1') -PassThru -DisableNameChecking
    & $worker { param($p) Assert-JobsFlutterProject $p } $Project
    $preferred = & $worker { param($p) try { Find-JobsImporterDart $p } catch { return $null } } $Project
    if ($preferred) { return $preferred }
    Write-Host '项目 FVM Dart 未就绪；迁移仅处理文件，尝试复用已有原生系统 Dart，不安装或切换工程 SDK。'
    foreach ($candidate in @(Get-JobsMigrationSystemDartCandidates)) {
        if (-not (& $worker {param($p)Test-JobsImporterNativeExecutable $p} $candidate)) { continue }
        try {
            $probe = Invoke-JobsProcess -FilePath $candidate -Arguments @('--version') -WorkingDirectory $Project -TimeoutSeconds 15
            if ($probe.ExitCode -eq 0 -and ($probe.StdOut+$probe.StdErr) -match 'Dart SDK version:') {
                Write-Host ('文件迁移运行时：'+$candidate)
                return $candidate
            }
        } catch { }
    }
    throw '缺少健康的原生 Dart。请先准备已有 Dart 或 Flutter/FVM SDK，再重新运行迁移；不会调用下载 shim 或自动安装 SDK。'
}

function Invoke-JobsMigrationEngine {
    param([string]$Dart,[string[]]$Arguments,[string]$Project)
    $engine = Join-Path $script:MigrationScripts 'FlutterDependencyMigration.dart'
    if (-not [IO.File]::Exists($engine)) { throw '缺少迁移引擎，请保留完整工具包。' }
    $result = Invoke-JobsProcess -FilePath $Dart -Arguments (@($engine)+$Arguments) -WorkingDirectory $Project -TimeoutSeconds 21600
    foreach ($output in @($result.StdOut,$result.StdErr)) { if ($output) { Write-JobsMigrationMessage $output.TrimEnd() } }
    if ($result.ExitCode -ne 0) { throw ('迁移引擎失败（退出码 ' + $result.ExitCode + '）；未授权覆盖冲突文件。') }
    return $result.StdOut
}

function Invoke-JobsFlutterMigration {
    param([string]$Project,[ValidateSet('export-all-dependencies','import-all-dependencies')][string]$Action,[switch]$PrivateOnly)
    $script:MigrationLog = $null
    $exporting = $Action -ceq 'export-all-dependencies'
    Write-Host 'Jobs · 一键提取 / 一键导入 Flutter 依赖' -ForegroundColor Red
    Write-Host '🔐 私库是迁移重点：默认只提取可识别的私库候选；未知来源会列为缺口，Git/path/非公共源不等同于已确认私有。' -ForegroundColor Yellow
    Write-Host '只读本机已有依赖，不下载、不运行依赖源码、排除已知缓存认证配置、不安装 SDK；项目及两份缓存不代表完整离线环境。'
    Write-Host '导入先校验再精确 YES，向当前环境融合；同名不同内容拒绝，原有文件保留。ZIP 请先解压，再选择产物目录。'
    Write-Host '日志：系统临时目录中的 JobsFlutterMigration-*.log；按 Ctrl+C 或输入结束取消。'
    $answer = Read-JobsMigrationLine '已了解用途与影响，直接回车继续；任意非空输入取消'
    if ($null -eq $answer -or $answer.Length -ne 0) { return }
    Assert-JobsMigrationDirectory $Project
    $dart = Get-JobsMigrationDart $Project
    $script:MigrationLog = Join-Path ([IO.Path]::GetTempPath()) ('JobsFlutterMigration-'+[guid]::NewGuid().ToString('N')+'.log')
    Write-JobsMigrationMessage ('日志：'+$script:MigrationLog)
    Write-JobsMigrationMessage ('目标工程：'+$Project)
    try {
        if ($exporting) {
            $all = $false
            if (-not $PrivateOnly) {
                $scope = Read-JobsMigrationLine '直接回车 = 只提取私库；输入任意字符（含空格）再回车 = 全提取'
                if ($null -eq $scope) { return }
                $all = $scope.Length -ne 0
            }
            $desktop = [Environment]::GetFolderPath('DesktopDirectory')
            $inputPath = Read-JobsMigrationLine ('输入或拖入输出父目录（直接回车：'+$desktop+'）')
            if ($null -eq $inputPath) { return }
            $destination = if ($inputPath.Length -eq 0) { $desktop } else { ConvertFrom-JobsMigrationPath $inputPath }
            Assert-JobsMigrationDirectory $destination
            $before = @((New-Object IO.DirectoryInfo $destination).EnumerateFileSystemInfos() | ForEach-Object { $_.FullName })
            Write-JobsMigrationMessage ('来源：项目已解析依赖与当前机器缓存；项目：'+$Project+'；输出父目录：'+$destination)
            Write-JobsMigrationMessage ('范围：'+$(if($all){'已确认全提取'}else{'只提取私库候选'}))
            $arguments = @('export','--project',$Project,'--destination',$destination)
            if ($all) { $arguments += '--all' }
            $output = Invoke-JobsMigrationEngine $dart $arguments $Project
            $markers = @([regex]::Matches($output,'(?m)^JOBS_MIGRATION_OUTPUT=(.+)\r?$'))
            if ($markers.Count -ne 1) { throw '引擎未返回唯一完整产物；不打包、不删除。' }
            $bundle = [IO.Path]::GetFullPath($markers[0].Groups[1].Value.TrimEnd("`r"))
            Assert-JobsMigrationDirectory $bundle
            $parent = [IO.Path]::GetDirectoryName($bundle.TrimEnd('\','/'))
            if (-not [string]::Equals($parent.TrimEnd('\','/'),[IO.Path]::GetFullPath($destination).TrimEnd('\','/'),[StringComparison]::OrdinalIgnoreCase) -or $bundle -in $before) { throw '产物不是本次新建的直属目录；不打包、不删除。' }
            $zipAnswer = Read-JobsMigrationLine '直接回车 = 打包成 ZIP；输入任意字符再回车 = 不打包'
            if ($null -eq $zipAnswer -or $zipAnswer.Length -ne 0) { Write-JobsMigrationMessage ('保留提取目录：'+$bundle); return }
            $zip = Compress-JobsMigrationBundle $bundle
            Write-JobsMigrationMessage ('ZIP 已逐文件 SHA-256 校验：'+$zip)
            $deleteAnswer = Read-JobsMigrationLine '直接回车 = 不删除原始提取产物；输入任意字符再回车 = 删除'
            if ($null -ne $deleteAnswer -and $deleteAnswer.Length -ne 0) {
                Assert-JobsMigrationZip $bundle $zip
                [IO.Directory]::Delete($bundle,$true)
                Write-JobsMigrationMessage ('已删除本次提取目录；ZIP 保留：'+$zip)
            } else { Write-JobsMigrationMessage ('保留提取目录：'+$bundle) }
        } else {
            while ($true) {
                $inputPath = Read-JobsMigrationLine '输入或拖入迁移产物、原始 Pub/Gradle 缓存目录或同时包含它们的父目录（名称可改，留空继续询问）'
                if ($null -eq $inputPath) { return }
                if (-not [string]::IsNullOrWhiteSpace($inputPath)) { break }
                Write-JobsMigrationMessage '尚未输入目录，请继续输入；Ctrl+C 或输入结束取消。'
            }
            $source = ConvertFrom-JobsMigrationPath $inputPath
            Assert-JobsMigrationDirectory $source
            Write-JobsMigrationMessage ('来源：'+$source+'；目标：当前项目/本机 PUB_CACHE、GRADLE_USER_HOME 或系统默认目录')
            $arguments = @('import','--project',$Project,'--source',$source)
            $preview = Invoke-JobsMigrationEngine $dart $arguments $Project
            $plans = @([regex]::Matches($preview,'(?m)^JOBS_MIGRATION_PLAN=([0-9a-f]{64})\r?$'))
            if ($plans.Count -ne 1) { throw '预检未返回唯一完整计划指纹，停止导入。' }
            $plan = $plans[0].Groups[1].Value
            $confirm = Read-JobsMigrationLine '核对上方识别结果与写入计划，精确输入大写 YES 导入；其它输入取消'
            if ($null -eq $confirm -or $confirm -cne 'YES') { Write-JobsMigrationMessage '已取消，未导入。'; return }
            [void](Invoke-JobsMigrationEngine $dart ($arguments+@('--apply','--expected-plan',$plan)) $Project)
            Write-JobsMigrationMessage '导入完成；请核对缺口，再用项目原有工具准备 SDK 和解析依赖。'
        }
    } finally { $script:MigrationLog = $null }
}
Export-ModuleMember -Function Invoke-JobsFlutterMigration
