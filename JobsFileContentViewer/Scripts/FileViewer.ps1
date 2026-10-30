# FileViewer.ps1 | JobsFileContentViewer
# Created by Jobs on 2026年10月27日，星期二.
# 只读、固定块流式输出；大小确认先于任何内容读取，内容和控制字符不作为命令执行。

function Get-JobsFileViewerLimit {
    $value = [Environment]::GetEnvironmentVariable('JOBS_FILE_VIEWER_MAX_BYTES')
    if ($null -eq $value) { return [long]1048576 }
    $limit = [long]0
    if ($value -cnotmatch '^[0-9]+$' -or -not [long]::TryParse($value, [ref]$limit) -or $limit -lt 1) {
        throw 'JOBS_FILE_VIEWER_MAX_BYTES 必须是 1 到 9223372036854775807 的十进制字节数。'
    }
    return $limit
}

function Get-JobsFileViewerTarget {
    param([Parameter(Mandatory = $true)][string]$Target)
    $item = Get-Item -LiteralPath $Target -Force -ErrorAction Stop
    if ($item.PSProvider.Name -ne 'FileSystem' -or $item.PSIsContainer -or
        ($item.Attributes -band ([IO.FileAttributes]::ReparsePoint -bor [IO.FileAttributes]::Device)) -ne 0) {
        throw '用终端查看文件内容只接受一个普通文件；不接受目录、链接或设备。'
    }
    return $item
}

function Confirm-JobsFileViewer {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
    $answer = Read-Host '输入 YES 后回车继续；直接回车、其他输入或输入结束均取消，Ctrl+C 中止'
    return $answer -ceq 'YES'
}

function ConvertTo-JobsFileViewerSafeText {
    param([AllowEmptyString()][string]$Text)
    # ESC / BEL / C1 等只显示转义文字，避免终端重设、改标题或触发超链接。
    return [regex]::Replace($Text, '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]', {
        param($match)
        return ('\u{0:X4}' -f [int][char]$match.Value[0])
    })
}

function Get-JobsFileViewerEncoding {
    param([byte[]]$Sample, [int]$Count, [bool]$Complete)
    $offset = 0
    $label = 'UTF-8'
    $encoding = New-Object Text.UTF8Encoding($false, $true)
    if ($Count -ge 4 -and $Sample[0] -eq 255 -and $Sample[1] -eq 254 -and $Sample[2] -eq 0 -and $Sample[3] -eq 0) {
        $encoding = New-Object Text.UTF32Encoding($false, $false, $true)
        $offset = 4; $label = 'UTF-32 LE'
    } elseif ($Count -ge 4 -and $Sample[0] -eq 0 -and $Sample[1] -eq 0 -and $Sample[2] -eq 254 -and $Sample[3] -eq 255) {
        $encoding = New-Object Text.UTF32Encoding($true, $false, $true)
        $offset = 4; $label = 'UTF-32 BE'
    } elseif ($Count -ge 2 -and $Sample[0] -eq 255 -and $Sample[1] -eq 254) {
        $encoding = New-Object Text.UnicodeEncoding($false, $false, $true)
        $offset = 2; $label = 'UTF-16 LE'
    } elseif ($Count -ge 2 -and $Sample[0] -eq 254 -and $Sample[1] -eq 255) {
        $encoding = New-Object Text.UnicodeEncoding($true, $false, $true)
        $offset = 2; $label = 'UTF-16 BE'
    } elseif ($Count -ge 3 -and $Sample[0] -eq 239 -and $Sample[1] -eq 187 -and $Sample[2] -eq 191) {
        $offset = 3
    }
    $uncertain = $false
    $text = ''
    try {
        $decoder = $encoding.GetDecoder()
        $characters = New-Object char[] ($encoding.GetMaxCharCount($Count))
        $length = $decoder.GetChars($Sample, $offset, ($Count - $offset), $characters, 0, $Complete)
        $text = New-Object string($characters, 0, $length)
    } catch [Text.DecoderFallbackException] {
        $uncertain = $true
        # 未知编码只能在确认后按替换字符查看，避免猜测 ANSI 代码页导致不可重现的结果。
        $label += '（无效字节显示为替换字符）'
    }
    $binary = $text -match '[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f]'
    return [pscustomobject]@{ Encoding = $encoding; Offset = $offset; Label = $label; NeedsConfirmation = ($uncertain -or $binary) }
}

function Invoke-JobsFileContentViewer {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Target)

    Write-Host 'Jobs · 用终端查看文件内容' -ForegroundColor Red
    Write-Host '只读查看一个文件；不运行文件。大文件和疑似二进制需输入 YES，Ctrl+C 随时中止。'
    Write-Host '文件正文仅显示在本窗口，不写入日志。'
    $limit = Get-JobsFileViewerLimit
    $item = Get-JobsFileViewerTarget -Target $Target
    Write-Host ('文件：' + (ConvertTo-JobsFileViewerSafeText $item.FullName))
    Write-Host ('大小：{0} 字节；确认阈值：{1} 字节。' -f $item.Length, $limit)
    if ($item.Length -gt $limit -and -not (Confirm-JobsFileViewer '文件超过阈值，完整输出可能耗时或令终端卡顿。是否继续？')) {
        Write-Host '已取消，未读取文件内容。'
        return
    }

    # 确认完成再打开；不允许写入/删除共享，避免输出过程中扩容或替换绕过阈值。
    $stream = $null
    $reader = $null
    try {
        [void](Get-JobsFileViewerTarget -Target $item.FullName)
        $stream = [IO.File]::Open($item.FullName, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        if ($stream.Length -gt $limit -and $stream.Length -ne $item.Length -and
            -not (Confirm-JobsFileViewer ('文件大小已变为 {0} 字节，超过阈值 {1} 字节。是否继续？' -f $stream.Length, $limit))) {
            Write-Host '已取消，未读取文件内容。'
            return
        }
        $sample = New-Object byte[] 8192
        $count = $stream.Read($sample, 0, $sample.Length)
        $format = Get-JobsFileViewerEncoding -Sample $sample -Count $count -Complete ($stream.Position -eq $stream.Length)
        if ($format.NeedsConfirmation -and -not (Confirm-JobsFileViewer '检测到疑似二进制、控制字符或未知编码。继续可能出现乱码；控制字符将显示为转义文字。是否继续？')) {
            Write-Host '已取消，未输出文件正文。'
            return
        }
        $stream.Position = $format.Offset
        $encoding = $format.Encoding.Clone()
        $encoding.DecoderFallback = New-Object Text.DecoderReplacementFallback([string][char]0xfffd)
        $reader = New-Object IO.StreamReader($stream, $encoding, $false, 4096)
        Write-Host ('编码：' + $format.Label)
        Write-Host '──────── 文件内容开始 ────────'
        $buffer = New-Object char[] 4096
        $pendingCarriageReturn = $false
        while (($readCount = $reader.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $chunk = New-Object string($buffer, 0, $readCount)
            if ($pendingCarriageReturn) { $chunk = "`r" + $chunk }
            $pendingCarriageReturn = $chunk.EndsWith("`r", [StringComparison]::Ordinal)
            if ($pendingCarriageReturn) { $chunk = $chunk.Substring(0, $chunk.Length - 1) }
            $chunk = $chunk.Replace("`r`n", "`n").Replace("`r", '\r')
            [Console]::Write((ConvertTo-JobsFileViewerSafeText $chunk))
        }
        if ($pendingCarriageReturn) { [Console]::Write('\r') }
        Write-Host ''
        Write-Host '──────── 文件内容结束 ────────'
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}
