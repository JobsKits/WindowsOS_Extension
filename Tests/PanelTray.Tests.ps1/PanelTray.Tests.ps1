# PanelTray.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年11月16日，星期一.
# 只运行真实关闭/恢复/释放控制器与内存窗口边界，不安装、不部署、不启动业务进程。
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$module=Import-Module (Join-Path $root 'Scripts/Installer.psm1') -Force -PassThru -DisableNameChecking
$script:checks=0
# 失败保留具体语义，并以非零状态退出。
function Assert-Tray { param([bool]$Value,[string]$Message) if (-not $Value) { throw ('FAIL: '+$Message) }; $script:checks++ }
# 内存资源记录释放次数，不触碰真实窗口/托盘。
function New-TrayResource {
    $r=[pscustomobject]@{Visible=$false;Enabled=$true;Text='';ToolTipText='';BackColor='';ForeColor='';DisposeCalls=0;StopCalls=0}
    $r | Add-Member ScriptMethod Dispose { $this.DisposeCalls++ }
    $r | Add-Member ScriptMethod Stop { $this.Enabled=$false;$this.StopCalls++ }
    return $r
}
# 选择框是唯一替换的UI边界；所有任务保全判断仍执行生产Request方法。
function Invoke-TrayClose {
    param($State,$EventArgs=$null,[switch]$Exit)
    & $module {
        param($s,$e,$exitNow)
        function Show-JobsPanelCloseChoice { param($State) $State.PromptCalls++;if($State.PromptStartsTask){$State.Running=$true};return $State.NextChoice }
        Request-JobsPanelClose $s $e -Exit:$exitNow
    } $State $EventArgs ([bool]$Exit)
}
# 构造可观察的窗口/进程边界，Started故意为true覆盖“完成后仍可退出”。
function New-TrayFixture {
    $form=[pscustomobject]@{Visible=$true;IsDisposed=$false;ShowInTaskbar=$true;WindowState='Maximized';BackColor='background';ForeColor='foreground';DialogResult='None';Tag=$null;CancelButton=$null;HideCalls=0;ShowCalls=0;ActivateCalls=0;BringCalls=0;CloseCalls=0;OwnerState=$null;RequestCallback=$null}
    $form | Add-Member ScriptMethod Hide { $this.Visible=$false;$this.HideCalls++ }
    $form | Add-Member ScriptMethod Show { $this.Visible=$true;$this.ShowCalls++ }
    $form | Add-Member ScriptMethod Activate { $this.ActivateCalls++ }
    $form | Add-Member ScriptMethod BringToFront { $this.BringCalls++ }
    $form | Add-Member ScriptMethod Dispose { $this.IsDisposed=$true }
    $form | Add-Member ScriptMethod Close {
        $this.CloseCalls++
        $e=[pscustomobject]@{Cancel=$false}
        & $this.RequestCallback $this.OwnerState $e
        if(-not $e.Cancel){$this.IsDisposed=$true;$this.Visible=$false}
    }
    $callback={
        param($s,$e)
        & $module {
            param($state,$argsValue)
            function Show-JobsPanelCloseChoice { param($State) $State.PromptCalls++;if($State.PromptStartsTask){$State.Running=$true};return $State.NextChoice }
            Request-JobsPanelClose $state $argsValue
        } $s $e
    }.GetNewClosure()
    $clock=New-Object Diagnostics.Stopwatch;$clock.Start()
    $state=[pscustomobject]@{
        Running=$false;Started=$true;Pump=$null;Operation='Install';Language='zh-Hans';Theme='light';Form=$form
        ExitRequested=$false;SelectionAccepted=$false;ClosePromptOpen=$false;TrayHidden=$false;TrayWindowState='Normal';TrayDisposed=$false;TrayError=''
        TrayIcon=(New-TrayResource);TrayMenu=(New-TrayResource);TrayRestore=(New-TrayResource);TrayStatus=(New-TrayResource);TrayExit=(New-TrayResource);TrayOwnedIcon=(New-TrayResource)
        Timer=(New-TrayResource);PreferenceTimer=(New-TrayResource);LogMenu=(New-TrayResource);ToolTip=(New-TrayResource);Font=(New-TrayResource);LogView=[pscustomobject]@{Font=(New-TrayResource)}
        StatusLabel=[pscustomobject]@{Text='任务状态原文';};StatusSource='任务状态原文';Logs=(New-Object 'Collections.Generic.List[object]')
        RunClocks=@{Install=$clock};FeatureStates=@{a='Succeeded'};Progress=[pscustomobject]@{Style='';Value=0;Maximum=1}
        RequestPath='';LogPath='fixture-tray.log';CancelButton=[pscustomobject]@{Enabled=$true;Text='关闭'}
        PromptCalls=0;NextChoice='Tray';PromptStartsTask=$false;SelectionToken=[guid]::NewGuid().ToString('N');LoopObserved=$false
    }
    $form.OwnerState=$state;$form.RequestCallback=$callback
    return $state
}
foreach($operation in @('Install','Uninstall','Cleanup')) {
    $s=New-TrayFixture;$s.Operation=$operation;$s.Running=$true;$e=[pscustomobject]@{Cancel=$false}
    Invoke-TrayClose $s $e
    Assert-Tray ($e.Cancel -and $s.TrayHidden -and -not $s.Form.Visible -and $s.TrayIcon.Visible) '所有进行中任务关闭直接退到托盘'
    Assert-Tray ($s.PromptCalls -eq 0 -and -not $s.ExitRequested) '任务中不询问且不保留退出标记'
    Assert-Tray ($s.Timer.Enabled -and $s.Timer.StopCalls -eq 0 -and $s.Timer.DisposeCalls -eq 0 -and -not $s.Form.IsDisposed) '后台保留Timer及原窗口'
    Assert-Tray (-not $s.TrayExit.Enabled -and $s.TrayExit.ToolTipText.Length -gt 0) '忙碌托盘出口禁用并说明原因'
    $identity=$s.Form;$token=$s.SelectionToken
    $s.ExitRequested=$true
    Invoke-TrayClose $s $e -Exit
    Assert-Tray ($s.PromptCalls -eq 0 -and $s.Form.CloseCalls -eq 0 -and -not $s.ExitRequested -and $s.TrayWindowState -ceq 'Maximized') '重复关闭和直接调用退出仍保全任务及原尺寸'
    & $module {param($x) Show-JobsPanelFromTray $x} $s
    Assert-Tray ($s.Form.Visible -and $s.Form.ShowInTaskbar -and -not $s.TrayHidden -and $s.Form.WindowState -ceq 'Maximized') '托盘恢复原最大化窗口'
    Assert-Tray ([object]::ReferenceEquals($identity,$s.Form) -and $s.SelectionToken -ceq $token -and $s.Timer.DisposeCalls -eq 0) '恢复保留同一窗口/勾选状态/生命周期'
    $s.RunClocks.Install.Stop()
}
foreach($choice in @('Tray','Exit','Cancel')) {
    $s=New-TrayFixture;$s.NextChoice=$choice;$e=[pscustomobject]@{Cancel=$false}
    Invoke-TrayClose $s $e
    Assert-Tray ($s.PromptCalls -eq 1) '仅空闲关闭弹一次选择'
    if($choice -eq 'Exit'){Assert-Tray (-not $e.Cancel -and $s.ExitRequested -and -not $s.TrayHidden) '明确完全退出才允许关闭'}
    elseif($choice -eq 'Tray'){Assert-Tray ($e.Cancel -and $s.TrayHidden -and $s.Timer.DisposeCalls -eq 0) '空闲选托盘仍保持窗口/计时器资源'}
    else{Assert-Tray ($e.Cancel -and $s.Form.Visible -and -not $s.TrayHidden -and $s.Form.DialogResult -ceq 'None') '取消选择框保留原窗口'}
    $s.RunClocks.Install.Stop()
}
$s=New-TrayFixture;$s.NextChoice='Exit';$s.PromptStartsTask=$true;$e=[pscustomobject]@{Cancel=$false}
Invoke-TrayClose $s $e
Assert-Tray ($e.Cancel -and $s.TrayHidden -and -not $s.ExitRequested) '选择框期间出现任务，退出复检转后台'
$s.RunClocks.Install.Stop()
foreach($probe in @(@($false,$false,$true),@($true,$false,$true),@($true,$true,$false))) {
    $s=New-TrayFixture;$s.Pump=[pscustomobject]@{Process=[pscustomobject]@{HasExited=$probe[0]};Drained=$probe[1];Lines=[pscustomobject]@{IsEmpty=$probe[2]}}
    Invoke-TrayClose $s ([pscustomobject]@{Cancel=$false}) -Exit
    Assert-Tray ($s.TrayHidden -and $s.Form.CloseCalls -eq 0 -and $s.PromptCalls -eq 0) '进程未退/输出未排空/队列未空均不可退出'
    $s.RunClocks.Install.Stop()
}
$s=New-TrayFixture;$s.Pump=[pscustomobject]@{};Invoke-TrayClose $s ([pscustomobject]@{Cancel=$false}) -Exit
Assert-Tray ($s.TrayHidden -and $s.Form.CloseCalls -eq 0) '无法判断进程时保守保全后台'
$s.RunClocks.Install.Stop()
$s=New-TrayFixture;$s.ClosePromptOpen=$true;$e=[pscustomobject]@{Cancel=$false};Invoke-TrayClose $s $e
Assert-Tray ($e.Cancel -and $s.PromptCalls -eq 0) '选择框防重入不弹重复框'
$s.RunClocks.Install.Stop()
$s=New-TrayFixture;$s.Running=$true;$s.TrayIcon=$null;Invoke-TrayClose $s ([pscustomobject]@{Cancel=$false})
Assert-Tray ($s.Form.Visible -and $s.Form.ShowInTaskbar -and -not $s.TrayHidden -and $s.Timer.Enabled) '托盘不可用保留可见窗口，不丢失运行中的任务'
$s.RunClocks.Install.Stop()
$s=New-TrayFixture;$icon=$s.TrayIcon;$menu=$s.TrayMenu;$owned=$s.TrayOwnedIcon
& $module {param($x) Stop-JobsPanelTray $x;Stop-JobsPanelTray $x} $s
Assert-Tray ($icon.DisposeCalls -eq 1 -and $menu.DisposeCalls -eq 1 -and $owned.DisposeCalls -eq 1 -and -not $icon.Visible) '完全退出托盘资源只释放一次'
Assert-Tray ($null -eq $s.TrayIcon -and $null -eq $s.TrayMenu -and $null -eq $s.TrayOwnedIcon -and $s.TrayDisposed) '完全退出清空托盘/菜单/自有图标引用'
$s.RunClocks.Install.Stop()
foreach($language in @('zh-Hans','zh-Hant','bo','en','ja','fr','es','de','ru','ko')) {
    $s=New-TrayFixture;$s.Language=$language
    & $module {param($x) Update-JobsPanelTray $x} $s
    foreach($text in @('关闭管理面板','退到系统托盘','完全退出','保留窗口','面板空闲。请选择退到系统托盘继续保留窗口，或完全退出。','显示管理面板','当前状态','任务进行中，暂时不能完全退出；可恢复窗口查看日志。','无法显示系统托盘，窗口保持打开。')) {
        $value=Get-JobsPanelText $text $language
        Assert-Tray (-not [string]::IsNullOrWhiteSpace($value)) '托盘/选择框十语完整'
        if($language -ne 'zh-Hans'){Assert-Tray ($value -cne $text) '新增文案不回退简体中文'}
    }
    Assert-Tray ($s.TrayExit.Enabled -and $s.TrayStatus.Text.EndsWith('任务状态原文') -and $s.TrayIcon.Text.Length -le 63) '十语状态保留原文且通知提示在旧API长度内'
    $s.RunClocks.Install.Stop()
}
$text=& $module {Get-JobsPanelTrayText (('x'*61)+'🧪文字')}
Assert-Tray ($text.Length -le 63 -and -not [char]::IsHighSurrogate($text[$text.Length-2])) '托盘长Unicode提示不切断代理对'
# 只替换原生绘色边界，实际执行选择框的三主题/十语绑定及字体克隆生命周期。
$presentation=New-TrayFixture
$parentFont=$presentation.Font
$parentFont | Add-Member NoteProperty Name 'Fixture UI'
$parentFont | Add-Member NoteProperty SizeInPoints 10.0
$parentFont | Add-Member ScriptMethod Clone {
    $f=[pscustomobject]@{Name=$this.Name;SizeInPoints=$this.SizeInPoints;DisposeCalls=0}
    $f | Add-Member ScriptMethod Dispose {$this.DisposeCalls++}
    return $f
}
$choice=[pscustomobject]@{Form=[pscustomobject]@{Text='';Font=$null;StyleState=$null};Label=[pscustomobject]@{Text=''};Tray=[pscustomobject]@{Text=''};Exit=[pscustomobject]@{Text=''};Keep=[pscustomobject]@{Text=''};Font=$null}
$fonts=New-Object 'Collections.Generic.List[object]'
foreach($language in @('zh-Hans','zh-Hant','bo','en','ja','fr','es','de','ru','ko')) {
    foreach($preference in @('light','dark','system')) {
        $presentation.Language=$language
        $presentation.Theme=Resolve-JobsPanelTheme -Preference $preference -SystemDark $true
        $parentFont.SizeInPoints=$(if($language -ceq 'bo'){11.0}else{10.0})
        & $module {
            param($c,$s)
            function Set-JobsPanelControlTheme {param($Control,$State) $Control.StyleState=$State}
            Update-JobsPanelCloseChoice $c $s
        } $choice $presentation
        if(-not $fonts.Contains($choice.Font)){[void]$fonts.Add($choice.Font)}
        Assert-Tray ($choice.Form.Text -ceq (Get-JobsPanelText '关闭管理面板' $language) -and $choice.Label.Text -ceq (Get-JobsPanelText '面板空闲。请选择退到系统托盘继续保留窗口，或完全退出。' $language)) '选择框标题/说明逐主题十语真实绑定'
        Assert-Tray ($choice.Tray.Text -ceq (Get-JobsPanelText '退到系统托盘' $language) -and $choice.Exit.Text -ceq (Get-JobsPanelText '完全退出' $language) -and $choice.Keep.Text -ceq (Get-JobsPanelText '保留窗口' $language)) '选择框三个动作随当前语言更新'
        Assert-Tray ([object]::ReferenceEquals($choice.Form.StyleState,$presentation) -and -not [object]::ReferenceEquals($choice.Font,$parentFont) -and $choice.Font.SizeInPoints -eq $parentFont.SizeInPoints) '选择框继承同一主题状态但字体独立拥有'
    }
}
Assert-Tray ($parentFont.DisposeCalls -eq 0 -and @($fonts | Where-Object { -not [object]::ReferenceEquals($_,$choice.Font) -and $_.DisposeCalls -ne 1 }).Count -eq 0) '换语言释放旧自有字体，不释放父窗字体'
$choice.Font.Dispose();$presentation.RunClocks.Install.Stop()

$windows=[Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
if(-not $windows) {
    # 仅替换Application.Run的原生消息循环边界，验证生产Show的finally直到真退出才运行。
    Add-Type @'
namespace System.Windows.Forms {
    public enum MouseButtons { Left, Right }
    public class MouseEventArgs : System.EventArgs { public MouseButtons Button; }
    public class ToolStripMenuItem {
        public bool Enabled=true; public string Text="",ToolTipText="";public object BackColor,ForeColor;
        public event System.EventHandler Click;
        public void PerformClick(){if(Click!=null)Click(this,System.EventArgs.Empty);}
    }
    public class ContextMenuStrip {
        public bool ShowItemToolTips;public object BackColor,ForeColor;public int DisposeCalls;
        public readonly System.Collections.Generic.List<object> Items=new System.Collections.Generic.List<object>();
        public event System.ComponentModel.CancelEventHandler Opening;
        public void Open(){if(Opening!=null)Opening(this,new System.ComponentModel.CancelEventArgs());}
        public void Dispose(){DisposeCalls++;}
    }
    public class NotifyIcon {
        public object Icon;public ContextMenuStrip ContextMenuStrip;public string Text="";public bool Visible;public int DisposeCalls;
        public event System.EventHandler<MouseEventArgs> MouseDoubleClick;
        public void DoubleClick(MouseButtons button){if(MouseDoubleClick!=null)MouseDoubleClick(this,new MouseEventArgs{Button=button});}
        public void Dispose(){DisposeCalls++;}
    }
    public static class Application {
        public static System.Action<object> RunAction;
        public static void Run(object form){RunAction(form);}
    }
}
'@
    $eventState=New-TrayFixture
    $originalIcon=New-TrayResource;$clonedIcon=New-TrayResource
    $originalIcon | Add-Member NoteProperty CloneResource $clonedIcon
    $originalIcon | Add-Member ScriptMethod Clone {return $this.CloneResource}
    $eventState.Form | Add-Member NoteProperty Icon $originalIcon
    & $module {param($x) Initialize-JobsPanelTray $x} $eventState
    Assert-Tray ($null -ne $eventState.TrayIcon -and [object]::ReferenceEquals($eventState.TrayOwnedIcon,$clonedIcon)) '生产托盘初始化复用原图标的自有克隆'
    $eventState.Running=$true;[void](& $module {param($x) Hide-JobsPanelToTray $x} $eventState)
    $eventState.TrayIcon.DoubleClick([Windows.Forms.MouseButtons]::Left)
    Assert-Tray ($eventState.Form.Visible -and -not $eventState.TrayHidden) '初始化返回后双击事件仍能访问所属模块恢复窗口'
    [void](& $module {param($x) Hide-JobsPanelToTray $x} $eventState)
    $eventState.TrayRestore.PerformClick()
    Assert-Tray ($eventState.Form.Visible -and -not $eventState.TrayHidden) '托盘恢复菜单事件恢复同一窗口'
    $eventState.TrayExit.PerformClick()
    Assert-Tray ($eventState.TrayHidden -and -not $eventState.Form.IsDisposed -and $eventState.PromptCalls -eq 0) '即使程序触发禁用出口事件，运行任务仍保全'
    $eventState.StatusLabel.Text='新的任务状态';$eventState.TrayMenu.Open()
    Assert-Tray ($eventState.TrayStatus.Text.EndsWith('新的任务状态') -and -not $eventState.TrayExit.Enabled) '打开菜单事件即时刷新当前状态及退出门禁'
    $eventState.Running=$false;$eventState.TrayExit.PerformClick()
    Assert-Tray ($eventState.Form.IsDisposed -and $eventState.ExitRequested) '空闲托盘出口事件真正关闭原窗口'
    $nativeIcon=$eventState.TrayIcon;$nativeMenu=$eventState.TrayMenu
    & $module {param($x) Stop-JobsPanelTray $x} $eventState
    Assert-Tray ($nativeIcon.DisposeCalls -eq 1 -and $nativeMenu.DisposeCalls -eq 1 -and $clonedIcon.DisposeCalls -eq 1 -and $originalIcon.DisposeCalls -eq 0) '生产事件资源释放不误释放共享原图标'
    $eventState.RunClocks.Install.Stop()
    $s=New-TrayFixture;$fixture=$s
    [Windows.Forms.Application]::RunAction=[Action[object]]{
        param($form)
        $fixture.Running=$true
        Invoke-TrayClose $fixture ([pscustomobject]@{Cancel=$false})
        $fixture.LoopObserved=($fixture.TrayHidden -and $fixture.Timer.DisposeCalls -eq 0 -and -not $fixture.Form.IsDisposed)
        & $module {
            param($x)
            function Add-JobsManagementLog {param($State,$Text,$Level) [void]$State.Logs.Add($Text)}
            Complete-JobsManagementRun $x $true '全部处理完成；退出码：0。'
        } $fixture
        if(-not $fixture.TrayHidden -or $fixture.Form.Visible){throw '完成时不应自动恢复或退出'}
        Invoke-TrayClose $fixture -Exit
    }.GetNewClosure()
    $result=& $module {
        param($fixture)
        function New-JobsFeatureSelectionForm {return $fixture}
        Show-JobsFeatureSelection
    } $s
    Assert-Tray ($null -eq $result -and $s.LoopObserved) '生产消息循环在隐藏期间保持活跃，空闲退出返回原null合同'
    Assert-Tray ($s.Form.IsDisposed -and $s.Timer.DisposeCalls -eq 1 -and $s.TrayDisposed) '完工仍驻留，显式退出才进入生产finally释放'
    $legacy=New-TrayFixture;$fixture=$legacy
    $choice=[pscustomobject]@{Features=@('fixture');Mode='Install'}
    [Windows.Forms.Application]::RunAction=[Action[object]]{
        param($form)
        $fixture.Form.Tag=$choice;$fixture.SelectionAccepted=$true;$fixture.Form.DialogResult='OK'
        $fixture.Form.Close()
    }.GetNewClosure()
    $returned=& $module {param($fixture) function New-JobsFeatureSelectionForm {return $fixture}; Show-JobsFeatureSelection} $legacy
    Assert-Tray ([object]::ReferenceEquals($returned,$choice) -and $returned.Features[0] -ceq 'fixture') '旧独立选择模式仍返回明确确认的同一选择结果'
    Assert-Tray ($legacy.PromptCalls -eq 0 -and $legacy.Form.IsDisposed -and $legacy.TrayDisposed) '确认选择不是关闭请求，不插入退出询问且释放资源'
    $legacy.RunClocks.Install.Stop()
    [Windows.Forms.Application]::RunAction=$null
} else { Write-Host 'SKIP: Application.Run循环边界夹具只在非Windows替换；真实托盘/窗口循环须原生单独验收。' }
$source=Join-Path $root 'Scripts/Installer.psm1';$hash=(Get-FileHash $source).Hash
$copies=@((Join-Path $root 'Scripts/SelectionPanel.psm1'),(Join-Path $root 'Infrastructure/SelectionPanel.psm1'))+@(Get-ChildItem $root -Directory -Filter Jobs*|ForEach-Object{Join-Path $_.FullName 'Scripts/SelectionPanel.psm1'}|Where-Object{[IO.File]::Exists($_)})
foreach($copy in $copies){Assert-Tray ((Get-FileHash $copy).Hash -ceq $hash) '38份托盘管理器一致'}
Write-Host ('PASS: PanelTray.Tests.ps1 ('+$script:checks+' assertions; native Windows tray: False)')
