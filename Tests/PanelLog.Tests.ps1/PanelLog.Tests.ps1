# PanelLog.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年11月16日，星期一.
# 仅运行生产解析/配色/追加控制流与合成控件边界，不安装、不部署、不改真实用户配置。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$path = Join-Path $root 'Scripts/Installer.psm1'
$module = Import-Module $path -PassThru -Force -DisableNameChecking
& $module { Initialize-JobsManagementLogFormat }
$script:checks = 0
# 计数断言并保留准确失败位置。
function Assert-Log {
    param([bool]$Value, [string]$Message)
    if (-not $Value) { throw ('FAIL: ' + $Message) }
    $script:checks++
}
$escape = [string][char]27
$parser = New-Object JobsManagementLog.AnsiParser
$r = $parser.Push(('原文 C:\安装\a.txt ' + $escape + '[31m错误' + $escape + '[0m 正文'), 'normal')
Assert-Log ($r.Plain -ceq '原文 C:\安装\a.txt 错误 正文') 'SGR只影响颜色，不改路径与正文'
Assert-Log ($r.Spans[1].Style -ceq 'error' -and $r.Spans[2].Style -ceq 'normal') 'SGR复位返回默认级别'
$p = New-Object JobsManagementLog.AnsiParser
Assert-Log ($p.Push(('前' + $escape + '[3'), 'normal').Plain -ceq '前') '分块SGR前半不泄露'
$r = $p.Push('2m绿色', 'normal')
Assert-Log ($r.Plain -ceq '绿色' -and $r.Spans[0].Style -ceq 'success') '跨块颜色状态承接'
Assert-Log ($p.Push('继续', 'normal').Spans[0].Style -ceq 'success') '前景色跨块延续'
$r = $p.Push(($escape + '[39m默认'), 'warning')
Assert-Log ($r.Spans[0].Style -ceq 'warning') '39复位保留当前信息级别'
foreach ($kind in @(']52;c;clipboard', ']8;;https://example.invalid/', 'Pprivate', '_private', '^private')) {
    $p = New-Object JobsManagementLog.AnsiParser
    $start = $p.Push(('前' + $escape + $kind), 'normal')
    $tail = $p.Push(($escape + '\后'), 'normal')
    Assert-Log (($start.Plain + $tail.Plain) -ceq '前后') 'OSC/DCS/APC/PM只删除控制载荷，不执行或展示'
}
foreach ($code in @(0x90,0x98,0x9e,0x9f)) {
    $p = New-Object JobsManagementLog.AnsiParser
    Assert-Log ($p.Push(('前' + [char]$code + 'private' + [char]0x9c + '后'),'normal').Plain -ceq '前后') 'C1字符串控制载荷不泄露'
}
$p = New-Object JobsManagementLog.AnsiParser
Assert-Log ($p.Push(('a' + $escape + ']8;;url' + [char]7 + 'link' + $escape + ']8;;' + [char]7 + 'b'), 'normal').Plain -ceq 'alinkb') 'OSC超链接仅保留可见标签'
$p = New-Object JobsManagementLog.AnsiParser
Assert-Log ($p.Push(("路径`t保留`r`n" + [char]0 + [char]8 + [char]7 + '🧪藏文བོད་'), 'normal').Plain -ceq "路径`t保留`r`n🧪藏文བོད་") '过滤危险控制符，保留Unicode与有效换行'
$p = New-Object JobsManagementLog.AnsiParser
Assert-Log ($p.Push(($escape + '[48;2;31;32;33m背景参数'), 'normal').Spans[0].Style -ceq 'normal') '忽略ANSI背景参数，不误解为前景31/32/33'
$p = New-Object JobsManagementLog.AnsiParser
Assert-Log ($p.Push(($escape + '[38;2;12;200;250mRGB'), 'normal').Spans[0].Style -ceq 'rgb:0cc8fa') '识别24位前景色'
$p = New-Object JobsManagementLog.AnsiParser
Assert-Log ($p.Push(($escape + '[38;5;196m索引'), 'normal').Spans[0].Style -ceq 'rgb:ff0000') '识别256色前景'
$p = New-Object JobsManagementLog.AnsiParser
Assert-Log ($p.Push(($escape + '[' + ('9' * 10000) + 'm完整正文'), 'normal').Plain -ceq '完整正文') '超长控制参数有界丢弃，正文继续'
foreach ($value in @('[ERROR] failed', '❌ 测试', '错误：测试')) { Assert-Log ([JobsManagementLog.Palette]::Level($value) -ceq 'error') '错误前缀识别' }
foreach ($value in @('[WARNING] caution','⚠ 测试')) { Assert-Log ([JobsManagementLog.Palette]::Level($value) -ceq 'warning') '警告前缀识别' }
Assert-Log ([JobsManagementLog.Palette]::Level('C:\warning\error.txt') -ceq 'normal') '不把路径正文当级别'
foreach ($diagnostic in @('C:\src\Feature.cs(12,3): warning CS0001: fixture','C:\src\file.cpp(12): Warning C4996: fixture','file.cpp:12:3: warning: fixture','/源码/含 空格/file.cpp:12: warning: fixture')) { Assert-Log ([JobsManagementLog.Palette]::Level($diagnostic) -ceq 'warning') '标准编译文件行列warning准确识别' }
foreach ($ordinary in @('The file.cpp has warning in its text','C:\warning\file.cpp','file.cpp:12:3: warningless body','正文 warning: 信息')) { Assert-Log ([JobsManagementLog.Palette]::Level($ordinary) -ceq 'normal') '只认标准诊断结构，不扫描任意warning词' }
foreach ($case in @(
    @('Failed', '任意诊断', @{a='Failed'}, 'error'),
    @('Succeeded', '任意诊断', @{a='Succeeded'}, 'success'),
    @('NotInstalled', '未安装，无需卸载', @{a='NotInstalled'}, 'info'),
    @('Skipped', '未执行', @{a='Skipped'}, 'warning'),
    @('Finished', '处理结束；失败1包', @{a='Failed'}, 'error'),
    @('Finished', '处理结束', @{a='Skipped'}, 'warning'),
    @('Finished', '全部处理完成', @{a='Succeeded'}, 'success')
)) {
    $actual = & $module { param($c) Get-JobsManagementLogLevel $c[0] $c[1] $c[2] } $case
    Assert-Log ($actual -ceq $case[3]) '状态配色不把无需卸载/失败/跳过冒充成功'
}
Assert-Log ([JobsManagementLog.Palette]::Background($true) -ne [JobsManagementLog.Palette]::Background($false)) '日志有独立明暗背景'
foreach ($dark in @($false,$true)) {
    foreach ($style in @('normal','error','warning','success','info','accent','cyan','rgb:ffffff','rgb:000000','rgb:f4f7fa','rgb:101821','rgb:ff0000','rgb:00ff00','rgb:0000ff')) {
        $color = [JobsManagementLog.Palette]::Color($style, $dark)
        Assert-Log ([JobsManagementLog.Palette]::Contrast($color,[JobsManagementLog.Palette]::Background($dark)) -ge 4.5) '正文/级别/ANSI色对当前底色满足4.5对比度'
    }
}
foreach ($message in @(0x20a,0x20e,0x24e,0x24f,0x119,0x115,0x114,0x201)) { Assert-Log ([JobsManagementLog.Navigation]::IsInput($message,0)) '原生轮/指针/手势/滚动条/选点暂停追尾' }
foreach ($key in @(33,34,35,36,37,38,39,40)) { Assert-Log ([JobsManagementLog.Navigation]::IsInput(0x100,$key)) '键盘导航暂停追尾' }
foreach ($message in @(0xf,0xb,0x4dd,0x4de,0xb6)) { Assert-Log (-not [JobsManagementLog.Navigation]::IsInput($message,0)) '绘制/内部视口恢复不是用户滚动' }
Assert-Log (-not [JobsManagementLog.Navigation]::IsInput(0x100,67)) '复制键不被当作滚动'
$buffer = New-Object JobsManagementLog.Buffer
$p = New-Object JobsManagementLog.AnsiParser
[void]$buffer.Append($p.Push("a`r",'normal').Spans)
[void]$buffer.Append($p.Push("`nb",'normal').Spans)
Assert-Log (($buffer.Runs.Text -join '') -ceq "a`nb") '跨块CRLF在可见模型中只算一个换行'
$buffer.Reset('')
$removed = $buffer.Append($p.Push(('x' * 1100000),'normal').Spans)
Assert-Log ($removed -eq 400000 -and $buffer.Length -eq 700000) '可见模型限长，完整文件另存'
Assert-Log ((($buffer.Runs | ForEach-Object { $_.Text.Length } | Measure-Object -Sum).Sum) -eq $buffer.Length) '截断后分段索引仍一致'

$windows = [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
if ($windows) {
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw '请以 Windows PowerShell -STA 运行原生控件回归。' }
    $view = New-Object JobsManagementLog.View
} else {
    # 编译生产View方法，仅把WinForms/HWND边界换为内存控件；不模拟真实滚动设备。
    $ast = [Management.Automation.Language.Parser]::ParseFile($path,[ref]$null,[ref]$null)
    $fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Initialize-JobsManagementLogFormat' },$true)
    $literals = @($fn.FindAll({ param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst] -and $n.Value.Contains('namespace JobsManagementLog') },$true))
    $pure = @($literals | Where-Object { $_.Value.Contains('public sealed class AnsiParser') })[0].Value
    $native = @($literals | Where-Object { $_.Value.Contains('public sealed class View :') })[0].Value
    $boundary = @'
namespace System.Windows.Forms {
    public struct Message { public int Msg; public System.IntPtr WParam; }
    public class RichTextBox {
        public string Text = "";
        public int TextLength { get { return Text.Length; } }
        public int SelectionStart, SelectionLength, ScrollCalls, BaseMessages;
        public readonly System.Collections.Generic.List<int> AddedColors = new System.Collections.Generic.List<int>();
        public System.Drawing.Color BackColor, ForeColor, SelectionColor;
        public bool IsHandleCreated { get { return false; } }
        public System.IntPtr Handle { get { return System.IntPtr.Zero; } }
        public string SelectedText { get { return Text.Substring(SelectionStart,SelectionLength); } set { Text = Text.Substring(0,SelectionStart) + value + Text.Substring(SelectionStart+SelectionLength); SelectionLength = value.Length; } }
        public void Select(int start, int length) { if (start < 0 || length < 0 || start + length > Text.Length) throw new System.ArgumentException("selection"); SelectionStart=start; SelectionLength=length; }
        public void AppendText(string value) { AddedColors.Add(SelectionColor.ToArgb()); Text += value; SelectionStart = Text.Length; SelectionLength = 0; Dispatch(0x115,0); }
        public int GetLineFromCharIndex(int index) { int lines = 0; for (int i=0;i<System.Math.Min(index,Text.Length);i++) if (Text[i]=='\n') lines++; return lines; }
        public System.Drawing.Point GetPositionFromCharIndex(int index) { return new System.Drawing.Point(0,GetLineFromCharIndex(index)*18); }
        public void ScrollToCaret() { ScrollCalls++; Dispatch(0x115,0); }
        public void Invalidate() { }
        protected virtual void WndProc(ref Message message) { BaseMessages++; }
        public void Dispatch(int message, int key) { var value = new Message { Msg=message, WParam=new System.IntPtr(key) }; WndProc(ref value); }
    }
}
'@
    $probe = ($pure + $boundary + $native).Replace('namespace JobsManagementLog {','namespace JobsManagementLogProbe {')
    Add-Type -TypeDefinition $probe
    $view = New-Object JobsManagementLogProbe.View
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('JobsPanelLog-' + [guid]::NewGuid().ToString('N') + '.log')
$state = [pscustomobject]@{ LogView=$view; FollowLog=[pscustomobject]@{ Checked=$true }; LogPath=$temp; Theme='light' }
try {
    $view.add_UserNavigation({ $state.FollowLog.Checked = $false }.GetNewClosure())
    & $module { param($s,$e) Add-JobsManagementLog $s ('原文 ' + $e + '[31m错误' + $e + '[0m 正文') -NoNewline } $state $escape
    Assert-Log ([IO.File]::ReadAllText($temp) -ceq '原文 错误 正文') '会话文件保持完整纯文本原文'
    Assert-Log ($view.Text -ceq '原文 错误 正文') '可见正文与完整纯文本一致'
    Assert-Log ($state.FollowLog.Checked) '生产追加中的内部滚动消息不误判为用户导航'
    $view.Select(3,2)
    $selected = $view.SelectedText
    & $module { param($s) Add-JobsManagementLog $s '后台追加' -NoNewline } $state
    Assert-Log ($view.SelectedText -ceq $selected -and $view.SelectionStart -eq 3) '生产追加方法保留原选区'
    $view.Select(1,0)
    if (-not $windows) {
        $view.Dispatch(0x20a,0)
        Assert-Log (-not $state.FollowLog.Checked) '生产WndProc手动轮输入触发暂停追尾'
        $scrollCalls = $view.ScrollCalls
        & $module { param($s) Add-JobsManagementLog $s '暂停期间继续' -NoNewline } $state
        Assert-Log ($view.ScrollCalls -eq $scrollCalls -and $view.SelectionStart -eq 1) '暂停时生产追加不调用追尾'
        Assert-Log ($view.BaseMessages -gt 0) '所有输入仍交给原生控件基类，不重写wheel delta'
    }
    $savedText = $view.Text; $start=$view.SelectionStart; $length=$view.SelectionLength
    foreach ($theme in @('dark','light','dark','light')) {
        $state.Theme=$theme
        & $module { param($s) Set-JobsManagementLogTheme $s } $state
        Assert-Log ($view.Text -ceq $savedText -and $view.SelectionStart -eq $start -and $view.SelectionLength -eq $length) '反复主题切换不改正文与选区'
        Assert-Log (($view.BackColor.ToArgb() -band 0xffffff) -eq [JobsManagementLog.Palette]::Background(($theme -eq 'dark'))) '主题切换采用独立日志背景'
    }
    if (-not $windows) {
        $scrollCalls=$view.ScrollCalls
        $view.FollowTail()
        Assert-Log ($view.ScrollCalls -eq $scrollCalls + 1 -and $view.SelectionStart -eq $view.TextLength) '显式恢复使用生产追尾方法定位末尾'
    }
    & $module { param($s,$e) Add-JobsManagementLog $s ($e + '[3') -Channel output -NoNewline; Add-JobsManagementLog $s 'stderr' -Channel error -NoNewline; Add-JobsManagementLog $s '2mstdout' -Channel output -NoNewline } $state $escape
    Assert-Log ([IO.File]::ReadAllText($temp).EndsWith('stderrstdout')) '标准输出/错误控制状态隔离，不吞掉另一通道原文'
    if (-not $windows) { Assert-Log ($view.AddedColors -contains [JobsManagementLog.Palette]::Color('error',$false)) '生产追加实际收到错误级别前景色' }
    Assert-Log (-not [IO.File]::ReadAllText($temp).Contains([string][char]27)) '复制全部的同一会话文件没有终端控制码'
# 以系统色快照替代只读系统查询，运行生产重配色及追加，避免改真实主题。
    $view.Select(1,2)
    foreach ($sample in @(
        @('high|-16777216|-1|-16777216|-1',-16777216,-1,-1),
        @('high|-1|-16777216|-1|-16777216',-1,-16777216,-16777216),
        @('normal',([JobsManagementLog.Palette]::Background($false) -bor [int]::MinValue -bor 0x7f000000),[JobsManagementLog.Palette]::Color('normal',$false),[JobsManagementLog.Palette]::Color('error',$false))
    )) {
        $oldText=$view.Text; $oldStart=$view.SelectionStart; $oldLength=$view.SelectionLength
        & $module {
            param($s,$key)
            function Get-JobsPanelContrastKey { return $key }
            Add-JobsManagementLog $s '高对比度切换后追加' -NoNewline -Level error
        } $state $sample[0]
        Assert-Log ($view.BackColor.ToArgb() -eq $sample[1] -and $view.ForeColor.ToArgb() -eq $sample[2]) '动态高对比度/系统色变更同轮刷新背景与正文'
        Assert-Log ($view.Text.StartsWith($oldText) -and $view.SelectionStart -eq $oldStart -and $view.SelectionLength -eq $oldLength) '动态高对比度保留已有正文与选区'
        Assert-Log ($state.LogContrastKey -ceq $sample[0]) '仅完成整区重配色后更新颜色快照'
        if (-not $windows) { Assert-Log ($view.AddedColors[$view.AddedColors.Count-1] -eq $sample[3]) '新追加与整区背景使用同一份颜色快照' }
    }
    foreach ($diagnostic in @('C:\src\Feature.cs(12,3): warning CS0001: fixture','file.cpp:12:3: warning: fixture')) {
        & $module { param($s,$text) Add-JobsManagementLog $s $text -Channel error -NoNewline } $state $diagnostic
        Assert-Log ($state.LogBuffer.Runs[$state.LogBuffer.Runs.Count-1].Style -ceq 'warning') '标准编译warning走stderr仍保持警告级别'
        Assert-Log ([IO.File]::ReadAllText($temp).EndsWith($diagnostic)) '编译诊断路径/行列/原文未被颜色分类改写'
        if (-not $windows) { Assert-Log ($view.AddedColors[$view.AddedColors.Count-1] -eq [JobsManagementLog.Palette]::Color('warning',$false)) 'stderr编译warning实际以当前警告前景色追加' }
    }
} finally {
    if ($windows) { $view.Dispose() }
    if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) }
}
# 实际外观更新只运行到控件布局边界，验证timer失效条件，不加载原生窗口。
$invalidation = & $module {
    $results=@()
    foreach ($case in @(
        @('normal','normal',$false,0),
        @('normal','high|-16777216|-1|-16777216|-1',$false,1),
        @('high|-16777216|-1|-16777216|-1','high|-1|-16777216|-1|-16777216',$false,1),
        @('high|-1|-16777216|-1|-16777216','normal',$false,1),
        @('normal','normal',$true,1)
    )) {
        $currentKey=$case[1]
        function Get-JobsPanelContrastKey { return $currentKey }
        $form=[pscustomobject]@{Calls=0}
        $form | Add-Member ScriptMethod SuspendLayout { $this.Calls++; throw 'appearance-probe-stop' }
        $s=[pscustomobject]@{Preferences=[pscustomobject]@{Language='zh-Hans';Theme='light'};Language='zh-Hans';Theme='light';ContrastKey=$case[0];PreferenceUpdating=$false;Form=$form}
        $errorText=''
        try { Update-JobsPanelPresentation $s -Force:$case[2] } catch { $errorText=$_.Exception.Message }
        $results += [pscustomobject]@{Calls=$form.Calls;Expected=$case[3];KeyKept=($s.ContrastKey -ceq $currentKey);OnlyBoundary=($errorText -eq '' -or $errorText.Contains('appearance-probe-stop'))}
    }
    $results
}
foreach ($item in $invalidation) {
    Assert-Log ($item.Calls -eq $item.Expected -and $item.OnlyBoundary) '现有timer仅外观未变时跳过，高对比度/系统色变更会触发更新'
    Assert-Log ($item.KeyKept) '外观失效键包含本轮高对比度和系统色'
}

# 真实完成/读取控制流只替换日志输出边界，不调用GUI、安装器或外部进程。
$completion = & $module {
    function Add-JobsManagementLog { param($State, [string]$Text, [string]$Level) [void]$State.Logs.Add([pscustomobject]@{Text=$Text;Level=$Level}) }
    function New-JobsCompletionFixture {
        $timer = [pscustomobject]@{ Stopped=$false }
        $timer | Add-Member ScriptMethod Stop { $this.Stopped=$true }
        $clock = New-Object Diagnostics.Stopwatch
        $clock.Start()
        [pscustomobject]@{
            Operation='Install'; FeatureStates=@{a='Succeeded'}; RunClocks=@{Install=$clock}; Timer=$timer
            Running=$true; Progress=[pscustomobject]@{Style='';Maximum=1;Value=0}
            StatusLabel=[pscustomobject]@{Text=''}; Pump=$null; RequestPath=''
            CancelButton=[pscustomobject]@{Enabled=$false;Text='取消'}; Form=[pscustomobject]@{CancelButton=$null}
            LogPath='fixture-summary.log'; Logs=(New-Object 'Collections.Generic.List[object]')
        }
    }
    $cases = @(
        @($true,$false,'全部处理完成；退出码：0。','success'),
        @($false,$false,'部分功能处理失败；退出码：1。','error'),
        @($false,$false,'任意未分类诊断；退出码：7。','error'),
        @($false,$true,'已停止安装；退出码：130。','warning'),
        @($true,$true,'停止标记优先；退出码：0。','warning')
    )
    $results = @()
    foreach ($case in $cases) {
        $s=New-JobsCompletionFixture
        $s | Add-Member NoteProperty Stopped $case[1]
        Complete-JobsManagementRun $s $case[0] $case[2]
        $results += [pscustomobject]@{
            Expected=$case[3];Actual=$s.Logs[0].Level;Count=$s.Logs.Count
            MessageKept=$s.Logs[0].Text.StartsWith($case[2]);PathKept=$s.Logs[0].Text.EndsWith(' 日志：fixture-summary.log')
            Finished=(-not $s.Running -and $s.Timer.Stopped -and -not $s.RunClocks.Install.IsRunning)
            StateKept=($s.FeatureStates.a -ceq 'Succeeded')
        }
    }
    $old=New-JobsCompletionFixture
    Complete-JobsManagementRun $old $false '兼容无停止字段的失败状态。'
    $s=New-JobsCompletionFixture
    $s.FeatureStates=@{a='Succeeded';b='Skipped'}
    $s | Add-Member NoteProperty Stopped $false
    $queue=New-Object 'Collections.Generic.Queue[object]'
    $queue.Enqueue([pscustomobject]@{Text='@@JOBS-MANAGER@@'+(ConvertTo-Json @{State='Stopped';FeatureIds=@();Message='原停止事件正文。'} -Compress);IsEvent=$true})
    $pump=[pscustomobject]@{Queue=$queue;Process=[pscustomobject]@{HasExited=$true;ExitCode=130};Drained=$true;Lines=[pscustomobject]@{IsEmpty=$true};Disposed=$false}
    $pump | Add-Member ScriptMethod Take { if ($this.Queue.Count -gt 0) { return $this.Queue.Dequeue() }; return $null }
    $pump | Add-Member ScriptMethod Dispose { $this.Disposed=$true }
    $s.Pump=$pump
    Read-JobsManagementOutput $s
    $request=New-JobsCompletionFixture
    $request | Add-Member NoteProperty StopRequested $false
    $request | Add-Member NoteProperty StopRequestPath (Join-Path ([IO.Path]::GetTempPath()) ('JobsStopColor-' + [guid]::NewGuid().ToString('N')))
    $request | Add-Member NoteProperty ConfirmButton ([pscustomobject]@{Enabled=$true;Text=''})
    try {
        Request-JobsManagementStop $request
        $requestKept=($request.StopRequested -and $request.Running -and [IO.File]::ReadAllText($request.StopRequestPath) -ceq 'stop-after-current-package')
    } finally { $request.RunClocks.Install.Stop(); if ([IO.File]::Exists($request.StopRequestPath)) { [IO.File]::Delete($request.StopRequestPath) } }
    [pscustomobject]@{Cases=$results;Legacy=$old.Logs[0].Level;Stop=$s;Pump=$pump;Request=$request;RequestKept=$requestKept}
}
foreach ($case in $completion.Cases) {
    Assert-Log ($case.Actual -ceq $case.Expected) '真实Complete按停止/成功/失败明确传递最终日志级别'
    Assert-Log ($case.Count -eq 1 -and $case.MessageKept -and $case.PathKept) '最终汇总保留原正文/退出码/日志路径及条数'
    Assert-Log ($case.Finished -and $case.StateKept) '展示级别不改变任务收尾与业务状态'
}
Assert-Log ($completion.Legacy -ceq 'error') '兼容无Stopped字段时失败仍明确为错误'
Assert-Log ($completion.Request.Logs.Count -eq 1 -and $completion.Request.Logs[0].Level -ceq 'warning' -and $completion.RequestKept) '停止请求显式警告且不改变原请求内容/仍运行语义'
Assert-Log ($completion.Stop.Stopped -and $completion.Stop.Logs.Count -eq 1 -and $completion.Stop.Logs[0].Level -ceq 'warning') '真实Read的Stopped标记进入唯一最终警告汇总'
Assert-Log ($completion.Stop.Logs[0].Text.Contains('退出码：130。') -and $completion.Stop.FeatureStates.b -ceq 'Skipped') '停止控制流保留原退出码和未执行状态'
Assert-Log ($completion.Pump.Disposed -and $null -eq $completion.Stop.Pump -and -not $completion.Stop.Running) '停止收尾仍正确释放原后台句柄'

$canonical = [IO.File]::ReadAllBytes($path)
$copies = @((Join-Path $root 'Scripts/SelectionPanel.psm1'), (Join-Path $root 'Infrastructure/SelectionPanel.psm1')) + @(Get-ChildItem -LiteralPath $root -Directory -Filter 'Jobs*' | ForEach-Object { Join-Path $_.FullName 'Scripts/SelectionPanel.psm1' } | Where-Object { [IO.File]::Exists($_) })
foreach ($copy in $copies) { Assert-Log ([Convert]::ToBase64String([IO.File]::ReadAllBytes($copy)) -ceq [Convert]::ToBase64String($canonical)) '独立副本与公共面板一致' }
Write-Host ('PASS: PanelLog.Tests.ps1 (' + $script:checks + ' assertions; native Windows GUI: ' + $windows + ')')
