# HarmonyTools.ps1 | SDL 镜像工具依赖；由 Action.psm1 私有载入。
# 固定摘要来自 SDL 镜像快照，不冒称华为官方摘要。
function Get-JobsHarmonyToolPackage {
    return [pscustomobject]@{
        Version = '6.1.1.280'
        Url = 'https://libsdl.org/harmonyos-devtools/commandline-tools-windows-x64-6.1.1.280.zip'
        Size = [long]2601671927
        Sha256 = '829554008df4f0b48a080f920175d562a4ebc4823e914b92ef45387dc7e7d628'
    }
}
function Get-JobsHarmonyToolsHome {
    if (-not $env:LOCALAPPDATA -or -not [IO.Path]::IsPathRooted($env:LOCALAPPDATA)) { throw 'LOCALAPPDATA 必须是有效的绝对目录。' }
    return Join-Path $env:LOCALAPPDATA 'Jobs/HarmonySimulator/tools'
}
function Receive-JobsHarmonyToolArchive {
    param($Package, [string]$Destination)
    $previousTls = [Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol = $previousTls -bor [Net.SecurityProtocolType]::Tls12
        [void](Invoke-JobsSdkAcquire -Label ('Harmony CLT：' + $Package.Url) -Operation {
            Receive-JobsSdkWebFile $Package.Url $Destination 120 -SingleAttempt -ExpectedSha256 $Package.Sha256
            if ((Get-Item -LiteralPath $Destination).Length -ne $Package.Size) { throw 'SDL 下载不完整，保留文件并自动重试。' }
        })
    } finally { [Net.ServicePointManager]::SecurityProtocol = $previousTls }
}
function Expand-JobsHarmonyToolArchive {
    param([string]$Archive, [string]$Destination, $Package)
    if ((Get-Item -LiteralPath $Archive).Length -ne $Package.Size) { throw 'SDL 工具包大小不符，未解压。' }
    if ((Get-FileHash -LiteralPath $Archive -Algorithm SHA256).Hash -ine $Package.Sha256) { throw 'SDL 工具包 SHA-256 不符，未解压。' }
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($Archive)
    try {
        $names = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        [long]$unpacked = 0
        foreach ($entry in $zip.Entries) {
            $name = $entry.FullName
            if ($name -cnotmatch '^command-line-tools/' -or $name -match '[\\:\x00-\x1f]|(^|/)\.\.?(/|$)|//' -or -not $names.Add($name)) { throw ('SDL 工具包包含不安全或重复路径：' + $name) }
            foreach ($part in $name.TrimEnd('/').Split('/')) {
                if ($part -match '[. ]$|^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { throw 'SDL 工具包包含 Windows 保留路径，未解压。' }
            }
            if ((($entry.ExternalAttributes -shr 16) -band 0xf000) -eq 0xa000) { throw 'SDL Windows 工具包含符号链接，未解压。' }
            $unpacked += $entry.Length
            if ($unpacked -gt 16GB) { throw 'SDL 工具包解压大小异常，未解压。' }
        }
        # Windows 包内有 218 字符相对路径，使用扩展路径，不要求修改系统长路径设置。
        $extractRoot = ConvertTo-JobsHarmonyFileSystemPath $Destination
        [void][IO.Directory]::CreateDirectory($extractRoot)
        foreach ($entry in $zip.Entries) {
            $target = [IO.Path]::Combine($extractRoot, $entry.FullName.Replace('/', [IO.Path]::DirectorySeparatorChar))
            if ($entry.FullName.EndsWith('/')) { [void][IO.Directory]::CreateDirectory($target); continue }
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
            $inputStream = $entry.Open()
            try {
                $outputStream = [IO.File]::Open($target, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose() }
            } finally { $inputStream.Dispose() }
        }
    } finally { $zip.Dispose() }
}
function ConvertTo-JobsHarmonyFileSystemPath {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or $full.StartsWith('\\?\')) { return $full }
    if ($full.StartsWith('\\')) { return '\\?\UNC\' + $full.Substring(2) }
    return '\\?\' + $full
}
function Install-JobsHarmonyTools {
    [void](Get-JobsHarmonyArchitecture)
    $package = Get-JobsHarmonyToolPackage
    $root = Get-JobsHarmonyToolsHome
    if (Test-Path -LiteralPath $root) {
        $item = Get-Item -LiteralPath $root -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw '工具安装根目录不是普通目录，停止。' }
    }
    [void][IO.Directory]::CreateDirectory($root)
    $token = [guid]::NewGuid().ToString('N')
    $stage = Join-Path $root ('.install-' + $token)
    [void][IO.Directory]::CreateDirectory($stage)
    $complete = $false
    try {
        Write-JobsHarmonyMessage ('SDL 第三方免登录镜像：' + $package.Url)
        Write-JobsHarmonyMessage ('CLT ' + $package.Version + '；' + $package.Size + ' 字节；快照 SHA-256：' + $package.Sha256)
        Write-JobsHarmonyMessage '该摘要固定 SDL 镜像内容，不代表已比对华为官方摘要；当前运行流程仅准备 CLT 工具，不下载系统镜像。'
        $archive = $env:HARMONY_CLT_ARCHIVE
        if ($archive) {
            if (-not [IO.File]::Exists($archive)) { throw 'HARMONY_CLT_ARCHIVE 指定的文件不存在。' }
            Write-JobsHarmonyMessage ('使用本地归档：' + $archive)
        } else {
            $archive = Join-Path $stage 'tools.zip'
            Receive-JobsHarmonyToolArchive $package $archive
        }
        $extract = Join-Path $stage 'extract'
        Expand-JobsHarmonyToolArchive $archive $extract $package
        $content = Join-Path $extract 'command-line-tools'
        $emulator = Join-Path $content 'emulator/Emulator.exe'
        if (-not [IO.File]::Exists($emulator) -or -not [IO.File]::Exists((Join-Path $content 'version.txt'))) { throw 'SDL 工具包缺少完整 Emulator 或版本文件，未安装。' }
        Assert-JobsHarmonyCapabilities $emulator
        $destination = Join-Path $root ('clt-' + $package.Version + '-' + $token)
        # Directory.Move 对已有目标失败，不会嵌套或覆盖既有安装。
        [IO.Directory]::Move($content, $destination)
        $installed = Join-Path $destination 'emulator/Emulator.exe'
        Write-JobsHarmonyMessage ('SDL 工具依赖已安装并通过能力复检：' + $destination)
        $complete = $true
        return $installed
    } finally {
        $cleanup = ConvertTo-JobsHarmonyFileSystemPath $stage
        if ($complete -and [IO.Directory]::Exists($cleanup)) { [IO.Directory]::Delete($cleanup, $true) } elseif ([IO.Directory]::Exists($cleanup)) { Write-JobsHarmonyMessage ('未完成下载保留：' + $cleanup) }
    }
}
