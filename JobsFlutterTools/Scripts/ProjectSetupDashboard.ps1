# ProjectSetupDashboard.ps1 | 里程碑与原生交互控制台。
# Created by Jobs on 2026年10月28日，星期三.
param([string]$Target=$env:JOBS_SETUP_TARGET,[switch]$Preview)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '运行仪表盘需要 Windows 图形桌面。' }
Import-Module (Join-Path $PSScriptRoot 'ProjectSetupLogTail.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot 'ProjectSetupProgress.psm1') -DisableNameChecking
Add-Type -AssemblyName System.Windows.Forms,System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class JobsEmbeddedConsole {
 [DllImport("user32.dll",SetLastError=true)] public static extern IntPtr SetParent(IntPtr child,IntPtr parent);
 [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr child);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr window);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
 [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr window);
 [StructLayout(LayoutKind.Sequential)] public struct ClientRectangle { public int Left,Top,Right,Bottom; }
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr window,out ClientRectangle rectangle);
 // ConPTY may return a message-only HWND: it cannot serve as a visible console.
 public static bool HasDrawableClient(IntPtr window) { ClientRectangle rectangle; return IsWindow(window) && IsWindowVisible(window) && !IsIconic(window) && GetClientRect(window,out rectangle) && rectangle.Right > rectangle.Left && rectangle.Bottom > rectangle.Top; }
 [DllImport("user32.dll",EntryPoint="GetWindowLongW")] public static extern int GetStyle(IntPtr window,int index);
 [DllImport("user32.dll",EntryPoint="SetWindowLongW")] public static extern int SetStyle(IntPtr window,int index,int style);
 [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr window,int x,int y,int width,int height,bool repaint);
 [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window,int action);
 public static int ChildStyle(int style) { return unchecked((int)(((uint)style & ~(0x80000000u | 0x00C00000u | 0x00040000u)) | 0x40000000u)); }
}
'@
$session=Join-Path ([IO.Path]::GetTempPath()) ('JobsFlutterSetup-'+[guid]::NewGuid().ToString('N'))
if (-not $Preview) { [void][IO.Directory]::CreateDirectory($session) }
$form=New-Object Windows.Forms.Form
$toolVersion=Get-JobsSetupVersion
$form.Text='Jobs · 一键配置 Flutter 项目至运行 · '+$toolVersion.Label
$workArea=[Windows.Forms.Screen]::FromPoint([Windows.Forms.Cursor]::Position).WorkingArea
$form.Size=New-Object Drawing.Size([Math]::Min(1240,[Math]::Max(900,$workArea.Width-40)),[Math]::Min(850,[Math]::Max(650,$workArea.Height-40)))
$form.MinimumSize=New-Object Drawing.Size(900,650)
$form.StartPosition='CenterScreen'
$form.Font=New-Object Drawing.Font('Microsoft YaHei UI',9)
$top=New-Object Windows.Forms.TableLayoutPanel
$top.Dock='Top';$top.Height=265;$top.ColumnCount=5;$top.RowCount=1
for($i=0;$i-lt5;$i++){[void]$top.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent,20)))}
$groups=@(
 @('环境','sdk.flutter','Flutter SDK','sdk.java','Java / jEnv'),
 @('平台工具链','platform.select','选择平台','platform.tools','SDK / C++ / 浏览器','platform.licenses','许可 / 私库'),
 @('依赖','deps.gradle','Gradle 分发','deps.pub','Pub 依赖','deps.plugins','构建插件'),
 @('设备与启动参数','run.device','设备 / 模拟器','run.arguments','入口 / Flavor / Defines'),
 @('运行验收','run.doctor','Doctor 检查','run.launch','编译 / 安装 / 启动','run.started','app.started 确认')
)
$componentNodes=@('sdk.flutter','sdk.java','platform.tools','deps.gradle','deps.plugins')
$labels=@{};$versionLabels=@{};$heads=@();$toolTips=New-Object Windows.Forms.ToolTip
for($g=0;$g-lt$groups.Count;$g++){
 $column=New-Object Windows.Forms.FlowLayoutPanel
 $column.Dock='Fill';$column.FlowDirection='TopDown';$column.WrapContents=$false;$column.Padding=New-Object Windows.Forms.Padding(12)
 $head=New-Object Windows.Forms.Label
 $head.Text=('● '+($g+1)+'  '+$groups[$g][0]);$head.AutoSize=$false;$head.Width=169;$head.Height=22;$head.AutoEllipsis=$true;$head.Font=New-Object Drawing.Font($form.Font,[Drawing.FontStyle]::Bold);$head.ForeColor=[Drawing.Color]::Gray
 $header=New-Object Windows.Forms.FlowLayoutPanel;$header.AutoSize=$true;$header.WrapContents=$false;$header.FlowDirection='LeftToRight'
 $toolTips.SetToolTip($head,$head.Text)
 $header.Controls.Add($head)
 if($g-lt4){$arrow=New-Object Windows.Forms.Label;$arrow.Text='>>>>>';$arrow.AutoSize=$false;$arrow.Width=45;$arrow.Height=22;$arrow.Font=New-Object Drawing.Font('Consolas',9,[Drawing.FontStyle]::Bold);$arrow.ForeColor=[Drawing.Color]::Gray;$arrow.Margin=New-Object Windows.Forms.Padding(4,1,0,0);$header.Controls.Add($arrow)}
 $column.Controls.Add($header);$heads+=$head
 for($j=1;$j-lt$groups[$g].Count;$j+=2){
  $label=New-Object Windows.Forms.Label;$label.Text='○ '+$groups[$g][$j+1]+' · 未开始';$label.Width=195;$label.Height=24
  $labels[$groups[$g][$j]]=$label;$column.Controls.Add($label)
  $versionLabel=New-Object Windows.Forms.Label;$versionLabel.Text=if($groups[$g][$j]-in$componentNodes){'版本：尚未检测'}else{'版本：不适用（操作步骤）'};$versionLabel.Width=195;$versionLabel.Height=28;$versionLabel.AutoEllipsis=$true;$versionLabel.Font=New-Object Drawing.Font('Microsoft YaHei UI',8);$versionLabel.ForeColor=[Drawing.Color]::DimGray
  $versionLabels[$groups[$g][$j]]=$versionLabel;$column.Controls.Add($versionLabel)
 }
 $top.Controls.Add($column,$g,0)
}
# 五组保持同一水平线；小屏缩窄文字，完整名称/版本仍可悬停查看。
$resizeTop={
 $width=[Math]::Max(115,[int]($top.ClientSize.Width/5)-32)
 foreach($label in $labels.Values){$label.Width=$width;$label.AutoEllipsis=$true}
 foreach($label in $versionLabels.Values){$label.Width=$width}
 for($index=0;$index-lt$heads.Count;$index++){$heads[$index].Width=if($index-lt4){[Math]::Max(60,$width-49)}else{$width}}
}
$top.Add_Resize($resizeTop)
$bottom=New-Object Windows.Forms.Panel;$bottom.Dock='Bottom';$bottom.Height=48
$status=New-Object Windows.Forms.Label;$status.AutoSize=$false;$status.Dock='Fill';$status.Text='下方为真实 CMD / PowerShell 交互控制台；点击终端后使用键盘。';$status.Padding=New-Object Windows.Forms.Padding(10)
$logButton=New-Object Windows.Forms.Button;$logButton.Text='打开完整日志';$logButton.Dock='Right';$logButton.Width=130
$logButton.Add_Click({if(Test-Path -LiteralPath $session){Start-Process explorer.exe -ArgumentList ('"'+$session+'"')}})
$bottom.Controls.Add($status);$bottom.Controls.Add($logButton);$form.Controls.Add($bottom)
$console=New-Object Windows.Forms.Panel;$console.Dock='Fill';$console.BackColor=[Drawing.Color]::Black
$fallback=New-Object Windows.Forms.RichTextBox;$fallback.Dock='Fill';$fallback.ReadOnly=$true;$fallback.BackColor=[Drawing.Color]::Black;$fallback.ForeColor=[Drawing.Color]::Gainsboro;$fallback.Font=New-Object Drawing.Font('Consolas',10)
$fallback.Text=if($Preview){'仅预览界面：不会启动控制台、安装 SDK 或写配置。'}else{'正在建立原生交互控制台。若系统阻止嵌入，会明确切换到独立终端，并在此同步完整工具输出。'}
$console.Controls.Add($fallback)
# 真实可拖动上下分隔，终端维持原生控件并在调整时同步尺寸。
$split=New-Object Windows.Forms.SplitContainer
$split.Dock='Fill';$split.Orientation=[Windows.Forms.Orientation]::Horizontal;$split.SplitterWidth=8
$split.Size=New-Object Drawing.Size($form.ClientSize.Width,($form.ClientSize.Height-$bottom.Height))
$split.SplitterDistance=265;$split.Panel1MinSize=265;$split.Panel2MinSize=180
$split.FixedPanel=[Windows.Forms.FixedPanel]::None;$split.IsSplitterFixed=$false
$split.BackColor=[Drawing.Color]::DimGray;$split.Panel1.BackColor=$form.BackColor
$top.Dock='Fill';$split.Panel1.Controls.Add($top);$split.Panel2.Controls.Add($console)
$form.Controls.Add($split);$split.BringToFront()
$script:consoleHandle=[IntPtr]::Zero;$script:consoleStyle=0;$script:embedded=$false;$script:worker=$null;$script:done=$false;$script:processed=0;$script:rawTail=New-JobsSetupLogTailState -Path (Join-Path $session 'raw.log');$script:consoleParent=[IntPtr]::Zero;$script:embedAttempts=0
$states=@{};$names=@{pending='未开始';running='执行中';waiting='等待用户';done='已完成';failed='失败 / 待处理';skipped='不适用'}
$colors=@{pending=[Drawing.Color]::Gray;running=[Drawing.Color]::RoyalBlue;waiting=[Drawing.Color]::DarkOrange;done=[Drawing.Color]::ForestGreen;failed=[Drawing.Color]::Firebrick;skipped=[Drawing.Color]::Gray}
# 控制台尺寸跟随下半面板，保留原生 TTY 和 fzf。
$resize={if($script:embedded-and[JobsEmbeddedConsole]::IsWindow($script:consoleHandle)){[void][JobsEmbeddedConsole]::MoveWindow($script:consoleHandle,0,0,$console.ClientSize.Width,$console.ClientSize.Height,$true)}}
$console.Add_Resize($resize)
$split.Add_SplitterMoved($resize)
$timer=New-Object Windows.Forms.Timer;$timer.Interval=200
$timer.Add_Tick({
 if($Preview){return}
 try{
  $hwndPath=Join-Path $session 'console-hwnd.txt'
  if(-not$script:embedded-and(Test-Path -LiteralPath $hwndPath)-and$script:embedAttempts-lt30){
   $script:embedAttempts++
   $handle=[IntPtr][long]([IO.File]::ReadAllText($hwndPath))
   # 必须在 reparent 前验证可见且 client rect 非零，消息专用 HWND 不进入嵌入。
   if([JobsEmbeddedConsole]::HasDrawableClient($handle)){
    $script:consoleHandle=$handle;$script:consoleStyle=[JobsEmbeddedConsole]::GetStyle($handle,-16)
    $script:consoleParent=[JobsEmbeddedConsole]::GetParent($handle)
    [void][JobsEmbeddedConsole]::SetStyle($handle,-16,[JobsEmbeddedConsole]::ChildStyle($script:consoleStyle))
    [void][JobsEmbeddedConsole]::SetParent($handle,$console.Handle)
    if([JobsEmbeddedConsole]::GetParent($handle)-eq$console.Handle){
     [void][JobsEmbeddedConsole]::MoveWindow($handle,0,0,$console.ClientSize.Width,$console.ClientSize.Height,$true)
     [void][JobsEmbeddedConsole]::ShowWindow($handle,5)
     if([JobsEmbeddedConsole]::HasDrawableClient($handle)){$script:embedded=$true;$fallback.Visible=$false;$status.Text='下方是真实原生 CMD：fzf、许可证及运行控制均可直接输入。'}
    }
    if(-not $script:embedded){[void][JobsEmbeddedConsole]::SetParent($handle,$script:consoleParent);[void][JobsEmbeddedConsole]::SetStyle($handle,-16,$script:consoleStyle);[void][JobsEmbeddedConsole]::ShowWindow($handle,5);$status.Text='系统未允许嵌入，交互终端在独立窗口；下方增量显示原始日志末尾，完整文件保留。'}
   }else{$fallback.Visible=$true;$status.Text='控制台 HWND 不可见或无客户区，保持独立终端；下方增量显示日志末尾，完整文件保留。'}
  }
  if(-not $script:embedded -and $script:embedAttempts -ge 30){$status.Text='本系统未提供可嵌入控制台，交互在独立 CMD；下方仅显示日志末尾约20万字符，完整文件保留。'}
  if($script:worker -and $script:worker.HasExited -and -not $script:done){$status.Text='本次控制台已退出；请检查完整日志确认最后成功阶段。';$script:done=$true}
  $events=Join-Path $session 'events.jsonl'
  if(Test-Path -LiteralPath $events){
   $lines=[IO.File]::ReadAllLines($events)
   while($script:processed-lt$lines.Count){
    $event=$lines[$script:processed]|ConvertFrom-Json
    $script:processed++
    if($event.node-eq'overall'){$status.Text=$event.detail;$script:done=$event.state-in@('done','failed')}
    elseif($labels.ContainsKey($event.node)){
     $states[$event.node]=$event.state;$label=$labels[$event.node]
     if($null-ne$event.PSObject.Properties['version']-and-not[string]::IsNullOrWhiteSpace([string]$event.version)){$versionLabel=$versionLabels[$event.node];$versionLabel.Text='版本：'+[string]$event.version;$toolTips.SetToolTip($versionLabel,[string]$event.version);$toolTips.SetToolTip($label,[string]$event.version+"`r`n"+[string]$event.detail)}
     if($event.state-eq'skipped'-and$event.node-in$componentNodes){$versionLabels[$event.node].Text='版本：不适用';$toolTips.SetToolTip($versionLabels[$event.node],[string]$event.detail)}
     $original=($label.Text-split' · ')[0];$label.Text=$original+' · '+$names[$event.state];$label.ForeColor=$colors[$event.state]
     for($g=0;$g-lt$groups.Count;$g++){
      $groupStates=@();for($k=1;$k-lt$groups[$g].Count;$k+=2){$node=$groups[$g][$k];$groupStates+=if($states.ContainsKey($node)){$states[$node]}else{'pending'}}
      $groupState=if('failed'-in$groupStates){'failed'}elseif('waiting'-in$groupStates){'waiting'}elseif('running'-in$groupStates){'running'}elseif(@($groupStates|Where-Object{$_-notin@('done','skipped')}).Count-eq0){'done'}else{'pending'}
      $heads[$g].ForeColor=$colors[$groupState]
     }
     $status.Text=$event.detail
    }
   }
  }
  if(-not$script:embedded){
   $chunk=Read-JobsSetupLogTail -State $script:rawTail
   if($chunk.Changed){
    if($chunk.Reset){$fallback.Clear()}
    if($chunk.Text.Length){$fallback.AppendText($chunk.Text)}
    if($fallback.TextLength-gt$script:rawTail.MaxDisplayChars){
     $trim=$fallback.TextLength-$script:rawTail.MaxDisplayChars
     $visible=$fallback.Text
     if($trim-gt0-and$trim-lt$visible.Length-and[char]::IsLowSurrogate($visible[$trim])-and[char]::IsHighSurrogate($visible[$trim-1])){$trim++}
     $fallback.Select(0,$trim);$fallback.SelectedText=''
    }
    $fallback.SelectionStart=$fallback.TextLength;$fallback.ScrollToCaret()
   }
  }
 }catch{# 写入中的最后一行或窗口创建尚未完成，下一轮读取同一游标。
 }
})
$form.Add_Shown({
 if($Preview){return}
 try{
  $start=New-Object Diagnostics.ProcessStartInfo
  $conhost=Join-Path ([Environment]::GetFolderPath('System')) 'conhost.exe'
  $cmd=Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
  $command='/d /v:off /s /c ""%JOBS_SETUP_POWERSHELL%" -NoLogo -NoProfile -STA -ExecutionPolicy Bypass -File "%JOBS_SETUP_WORKER%""'
  $start.FileName=$conhost;$start.Arguments='"'+$cmd+'" '+$command
  $start.UseShellExecute=$false;$start.CreateNoWindow=$false;$start.WorkingDirectory=$Target
  $start.EnvironmentVariables['JOBS_SETUP_POWERSHELL']=Join-Path $PSHOME 'powershell.exe'
  $start.EnvironmentVariables['JOBS_SETUP_WORKER']=Join-Path $PSScriptRoot 'ProjectSetupWorker.ps1'
  $start.EnvironmentVariables['JOBS_SETUP_TARGET']=$Target;$start.EnvironmentVariables['JOBS_SETUP_SESSION']=$session
  try{$script:worker=[Diagnostics.Process]::Start($start)}catch{$start.FileName=$cmd;$start.Arguments=$command;$script:worker=[Diagnostics.Process]::Start($start);$status.Text='conhost 不可用，使用独立 CMD 交互回退。'}
  $timer.Start()
 }catch{$status.Text='启动失败：'+$_.Exception.Message;$script:done=$true}
})
$form.Add_FormClosing({
 param($sender,$event)
 if($script:worker-and-not$script:worker.HasExited){
  $choice=if($script:done){[Windows.Forms.DialogResult]::Yes}else{[Windows.Forms.MessageBox]::Show('是：停止本次任务及子进程后关闭。否：转为独立终端继续运行。取消：返回仪表盘。','本次任务仍在进行',[Windows.Forms.MessageBoxButtons]::YesNoCancel)}
  if($choice-eq[Windows.Forms.DialogResult]::Cancel){$event.Cancel=$true;return}
  if($choice-eq[Windows.Forms.DialogResult]::No){if($script:embedded){[void][JobsEmbeddedConsole]::SetParent($script:consoleHandle,$script:consoleParent);[void][JobsEmbeddedConsole]::SetStyle($script:consoleHandle,-16,$script:consoleStyle);[void][JobsEmbeddedConsole]::ShowWindow($script:consoleHandle,5)}}
  else{& (Join-Path ([Environment]::GetFolderPath('System')) 'taskkill.exe') /PID $script:worker.Id /T /F | Out-Null;if($LASTEXITCODE-ne0){$event.Cancel=$true;[void][Windows.Forms.MessageBox]::Show('停止本次子进程树失败，仪表盘保留。请在原始终端检查 UAC / 安装器状态后重试。','停止失败');return}}
 }
 $timer.Stop()
})
try{[void]$form.ShowDialog()}finally{$timer.Dispose();$toolTips.Dispose();$form.Dispose()}
