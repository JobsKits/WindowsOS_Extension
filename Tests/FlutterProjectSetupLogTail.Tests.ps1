# FlutterProjectSetupLogTail.Tests.ps1 | 增量 UTF8、显示上限与真实控制台门禁。
# Created by Jobs on 2026年10月29日，星期四.
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetupLogTail.psm1') -DisableNameChecking
$count=0
function Assert($Value,[string]$Message){$script:count++;if(-not$Value){throw $Message}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('jobs-setup-log-tail-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
try{
 $file=Join-Path $temp 'raw.log'
 $state=New-JobsSetupLogTailState -Path $file -MaxBytesPerPoll 1
 $chunk=Read-JobsSetupLogTail $state
 Assert (-not$chunk.Changed-and-not[IO.File]::Exists($file)) '缺少日志时不创建或改写原始文件'
 $sample="A中😀结束Z`r`n"
 $bytes=[Text.Encoding]::UTF8.GetBytes($sample)
 [IO.File]::WriteAllBytes($file,$bytes)
 $hash=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
 $collected=''
 for($i=0;$i-lt$bytes.Length;$i++){
  $chunk=Read-JobsSetupLogTail $state
  Assert ($chunk.BytesRead-le1) '每轮读取不超过预算'
  $collected+=$chunk.Text
 }
 Assert ($collected-ceq$sample-and$state.Tail-ceq$sample) '逐字节跨块读取仍完整保留中文与emoji'
 Assert (-not$collected.Contains([char]0xFFFD)) '持久 Decoder 不产生边界替换字符'
 $chunk=Read-JobsSetupLogTail $state
 Assert (-not$chunk.Changed-and$chunk.BytesRead-eq0) '未增长时不重读旧文件或刷新UI'
 Assert ((Get-FileHash -LiteralPath $file).Hash-ceq$hash) '读显示日志不改写原始文件'
 # 一个中文字符跨两次文件追加，EOF不能刷新/丢弃decoder中的残留字节。
 $extra=[Text.Encoding]::UTF8.GetBytes('跨')
 $append=[IO.File]::Open($file,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
 try{$append.WriteByte($extra[0])}finally{$append.Dispose()}
 $chunk=Read-JobsSetupLogTail $state
 Assert ($chunk.Text-ceq'') '未完整的UTF8字符在EOF处等待下一块'
 $append=[IO.File]::Open($file,[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)
 try{$append.Write($extra,1,2)}finally{$append.Dispose()}
 $received='';for($i=0;$i-lt2;$i++){$received+=(Read-JobsSetupLogTail $state).Text}
 Assert ($received-ceq'跨') '下一次追加补全字符，不产生半字'
 # 源文件被重新写小时重置offset和decoder，不混入旧尾部。
 $replacement='新😀'
 [IO.File]::WriteAllText($file,$replacement,(New-Object Text.UTF8Encoding($false)))
 $collected='';$reset=$false
 for($i=0;$i-lt[Text.Encoding]::UTF8.GetByteCount($replacement);$i++){$chunk=Read-JobsSetupLogTail $state;$reset=$reset-or$chunk.Reset;$collected+=$chunk.Text}
 Assert ($reset-and$collected-ceq$replacement-and$state.Tail-ceq$replacement) '截短后重新读取完整新内容'
 # 大日志积压直接定位有界尾部，限制单轮工作量；原始文件仍完整。
 $large=("中😀 line ABC`r`n"*120000)+'最终尾部😀'
 [IO.File]::WriteAllText($file,$large,(New-Object Text.UTF8Encoding($false)))
 $hash=(Get-FileHash -LiteralPath $file).Hash;$length=(Get-Item -LiteralPath $file).Length
 $state=New-JobsSetupLogTailState -Path $file -MaxDisplayChars 2000 -MaxBytesPerPoll 16384 -MaxBacklogBytes 65536
 $polls=0
 while($state.Offset-lt$length-and$polls-lt10){$chunk=Read-JobsSetupLogTail $state;$polls++;Assert ($chunk.BytesRead-le16384) '大日志每轮只处理固定字节预算'}
 Assert ($state.Offset-eq$length-and$polls-lt5) '积压日志不从头全量刷新，少量poll即可追到当前尾部'
 Assert ($state.SkippedBytes-gt0-and$state.Tail.Length-le2000) '仅跳过显示历史并限制显示字符上限'
 Assert ($state.Tail.EndsWith('最终尾部😀')-and-not$state.Tail.Contains([char]0xFFFD)) '大日志跳转对齐UTF8码点，尾部内容完整'
 Assert (-not[char]::IsLowSurrogate($state.Tail[0])) '显示裁剪不从emoji低代理项开始'
 Assert ((Get-FileHash -LiteralPath $file).Hash-ceq$hash-and(Get-Item -LiteralPath $file).Length-eq$length) '界面裁剪不会截断原始完整日志'
 $source=[IO.File]::ReadAllText((Join-Path $root 'JobsFlutterTools/Scripts/ProjectSetupDashboard.ps1'))
 Assert ($source.Contains('IsWindowVisible')-and$source.Contains('GetClientRect')-and$source.Contains('IsIconic')) '原生控制台检查可见性、客户区和最小化状态'
 $guard=$source.IndexOf('if([JobsEmbeddedConsole]::HasDrawableClient($handle))')
 $reparent=$source.IndexOf('::SetParent($handle,$console.Handle)')
 Assert ($guard-ge0-and$guard-lt$reparent) '真实可见检查发生在reparent之前'
 Assert ($source.Contains('HWND 不可见或无客户区')-and$source.Contains('$fallback.Visible=$true')) '消息专用HWND保持回退界面可见'
 Assert (-not$source.Contains('[IO.File]::ReadAllText($raw)')-and-not$source.Contains('$fallback.Text=$text')) '200ms轮询不再全量读原始文件/替换完整RichTextBox'
 Assert ($source.Contains('Read-JobsSetupLogTail')-and$source.Contains('AppendText($chunk.Text)')) '回退显示使用增量数据追加'
 Write-Host ('PASS: FlutterProjectSetupLogTail.Tests.ps1 ('+$count+' assertions; no native window operations)')
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
