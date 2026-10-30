# SelectionRequest.ps1 | JobsFileVolumes
# Created by Jobs on 2026年10月28日，星期三.
# 仅解析本包临时目录中的独占清单；路径始终作为数据。
function Read-JobsVolumeRequest {
    param([Parameter(Mandatory = $true)][string]$Path)
    $requestPath = [IO.Path]::GetFullPath($Path)
    $expectedDirectory = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) 'JobsFileVolumes'))
    if ([IO.Path]::GetDirectoryName($requestPath) -ine $expectedDirectory -or
        [IO.Path]::GetFileName($requestPath) -notmatch '^selection-[0-9a-fA-F-]{36}\.json$') { throw '选择清单路径无效。' }
    $directory = Get-Item -LiteralPath $expectedDirectory -Force -ErrorAction Stop
    $item = Get-Item -LiteralPath $requestPath -Force -ErrorAction Stop
    if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.PSIsContainer -or
        ($item.Attributes -band ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::Device)) -ne 0 -or $item.Length -gt 16777216) { throw '选择清单无效。' }
    $stream = [IO.File]::Open($requestPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    try {
        if ($stream.Length -gt 16777216) { throw '选择清单过大。' }
        $reader = New-Object IO.StreamReader($stream, (New-Object Text.UTF8Encoding($false, $true)), $true)
        try { $raw = $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $stream.Dispose() }
    if (-not $raw.TrimStart().StartsWith('[')) { throw '选择清单必须为JSON路径数组。' }
    # 外层对象阻止 PS7 的管道展开把嵌套数组伪装成字符串数组；兼容PS5.1。
    $parsed = ('{"Paths":' + $raw + '}') | ConvertFrom-Json -ErrorAction Stop
    $paths = @($parsed.Paths)
    if ($paths.Count -lt 1 -or $paths.Count -gt 10000 -or
        @($paths | Where-Object { $_ -isnot [string] -or [string]::IsNullOrEmpty($_) -or $_.IndexOf([char]0) -ge 0 }).Count -gt 0) { throw '选择清单不是有效文件路径数组。' }
    [IO.File]::Delete($requestPath)
    return $paths
}
