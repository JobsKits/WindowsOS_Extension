# ProjectSetupLogTail.psm1 | 有界增量读取回退终端日志。
# Created by Jobs on 2026年10月29日，星期四.
Set-StrictMode -Version 2.0
# 每个会话持有自己的 UTF8 Decoder，跨块中文/emoji 不会被截坏。
function New-JobsSetupLogTailState {
    param([string]$Path,[int]$MaxDisplayChars=200000,[int]$MaxBytesPerPoll=131072,[long]$MaxBacklogBytes=1048576)
    if ($MaxDisplayChars -lt 2 -or $MaxBytesPerPoll -lt 1 -or $MaxBacklogBytes -lt 1) { throw '日志窗口与读取上限必须为正数。' }
    return [pscustomobject]@{ Path=$Path; Offset=[long]0; Decoder=[Text.Encoding]::UTF8.GetDecoder(); Tail=''; Rendered=$false; MaxDisplayChars=$MaxDisplayChars; MaxBytesPerPoll=$MaxBytesPerPoll; MaxBacklogBytes=$MaxBacklogBytes; SkippedBytes=[long]0 }
}
# 有界显示末尾；文件过快增长时跳过旧显示数据，完整文件从不截断。
function Read-JobsSetupLogTail {
    param($State)
    if (-not [IO.File]::Exists($State.Path)) { return [pscustomobject]@{ Changed=$false; Reset=$false; Text=''; BytesRead=0; SkippedBytes=0 } }
    $stream=New-Object IO.FileStream($State.Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $reset=$false; $skipped=[long]0; $read=0
    $text=New-Object Text.StringBuilder
    try {
        $length=$stream.Length
        if ($length -lt $State.Offset) { $State.Offset=[long]0; $State.Decoder.Reset(); $State.Tail=''; $reset=$true }
        if ($length - $State.Offset -gt [Math]::Max($State.MaxBacklogBytes,[long]($State.MaxDisplayChars * 3 + 4))) {
            $before=$State.Offset
            $stream.Position=[Math]::Max([long]0,$length - [long]($State.MaxDisplayChars * 3 + 4))
            # 新位置若落在 UTF8 continuation byte 中，前移到完整码点起始。
            while ($stream.Position -lt $length) {
                $value=$stream.ReadByte()
                if (($value -band 192) -ne 128) { $stream.Position--; break }
            }
            $State.Offset=$stream.Position; $skipped=$State.Offset - $before
            $State.SkippedBytes += $skipped
            $State.Decoder.Reset(); $State.Tail=''; $reset=$true
        }
        $stream.Position=$State.Offset
        $budget=[int][Math]::Min([long]$State.MaxBytesPerPoll,$length - $State.Offset)
        $bytes=New-Object byte[] ([Math]::Min(32768,$State.MaxBytesPerPoll))
        $characters=New-Object char[] ([Text.Encoding]::UTF8.GetMaxCharCount($bytes.Length))
        while ($budget -gt 0) {
            $count=$stream.Read($bytes,0,[Math]::Min($bytes.Length,$budget))
            if ($count -le 0) { break }
            $State.Offset += $count; $read += $count; $budget -= $count
            $decoded=$State.Decoder.GetChars($bytes,0,$count,$characters,0,$false)
            if ($decoded) { [void]$text.Append($characters,0,$decoded) }
        }
    } finally { $stream.Dispose() }
    $delta=$text.ToString()
    if ($delta.Length -gt 0) {
        if (-not $State.Rendered) { $reset=$true }
        $State.Tail += $delta
        if ($State.Tail.Length -gt $State.MaxDisplayChars) {
            $trim=$State.Tail.Length - $State.MaxDisplayChars
            if ($trim -gt 0 -and [char]::IsLowSurrogate($State.Tail[$trim]) -and [char]::IsHighSurrogate($State.Tail[$trim-1])) { $trim++ }
            $State.Tail=$State.Tail.Substring($trim)
        }
    }
    $changed=($delta.Length -gt 0 -or $reset)
    if ($changed) { $State.Rendered=$true }
    return [pscustomobject]@{ Changed=$changed; Reset=$reset; Text=$delta; BytesRead=$read; SkippedBytes=$skipped }
}
Export-ModuleMember -Function New-JobsSetupLogTailState,Read-JobsSetupLogTail
