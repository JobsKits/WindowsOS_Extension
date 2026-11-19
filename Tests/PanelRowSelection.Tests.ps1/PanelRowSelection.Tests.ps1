# PanelRowSelection.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年11月16日，星期一.
# 只运行生产行命中/事件控制器，窗口边界为内存对象，不执行安装、卸载、清理或真实日志动作。
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$module=Import-Module (Join-Path $root 'Scripts/Installer.psm1') -Force -PassThru -DisableNameChecking
$script:checks=0
# 所有失败均以非零状态报告具体边界。
function Assert-Row {param([bool]$Value,[string]$Message) if(-not $Value){throw ('FAIL: '+$Message)};$script:checks++}
Add-Type @'
using System;
using System.Collections.Generic;
using System.Drawing;
namespace JobsRowProbe {
    public class Input : EventArgs { public string Button;public int X,Y;public bool Handled; }
    public class Area { public int Length; }
    public class Control {
        public string Kind="",Tag="";public int Left,Top,Width,Height,Changes,FocusCalls,ActionCalls;public bool Enabled=true;
        public Area LinkArea=new Area();public Point AutoScrollPosition;
        public int Bottom{get{return Top+Height;}}public Size ClientSize{get{return new Size(Width,Height);}}
        public readonly List<Control> Controls=new List<Control>();
        private bool selected;
        public bool Checked{get{return selected;}set{if(selected==value)return;selected=value;Changes++;if(CheckedChanged!=null)CheckedChanged(this,EventArgs.Empty);}}
        public event EventHandler CheckedChanged,MouseLeave,Scroll,Deactivate;
        public event EventHandler<Input> MouseDown,MouseMove,MouseUp,MouseWheel;
        public Control GetChildAtPoint(Point p){foreach(var c in Controls)if(new Rectangle(c.Left,c.Top,c.Width,c.Height).Contains(p))return c;return null;}
        public bool Focus(){FocusCalls++;return true;}
        public void Space(){if(Enabled&&Kind=="check")Checked=!Checked;}
        public Input Send(string phase,string button,int x,int y){
            var e=new Input{Button=button,X=x,Y=y};
            if(phase=="Down"&&MouseDown!=null)MouseDown(this,e);
            if(phase=="Move"&&MouseMove!=null)MouseMove(this,e);
            if(phase=="Up"){
                if(button=="Left"&&Enabled&&Kind=="check")Checked=!Checked;
                if(button=="Left"&&Enabled&&(Kind=="button"||(Kind=="status"&&LinkArea.Length>0)))ActionCalls++;
                if(MouseUp!=null)MouseUp(this,e);
            }
            if(phase=="Wheel"&&MouseWheel!=null)MouseWheel(this,e);
            if(phase=="Leave"&&MouseLeave!=null)MouseLeave(this,EventArgs.Empty);
            if(phase=="Scroll"&&Scroll!=null)Scroll(this,EventArgs.Empty);
            if(phase=="Deactivate"&&Deactivate!=null)Deactivate(this,EventArgs.Empty);
            return e;
        }
    }
}
'@
# 固定边界模拟真实平铺GroupBox，保留生产hit-test及控件优先级判断。
function New-RowControl {param([string]$Kind,[int]$Left,[int]$Top,[int]$Width,[int]$Height) $c=New-Object JobsRowProbe.Control;$c.Kind=$Kind;$c.Left=$Left;$c.Top=$Top;$c.Width=$Width;$c.Height=$Height;return $c}
function New-RowFixture {
    $box=New-RowControl group 0 0 600 180
    $rows=@{};$labels=@{};$checks=@()
    foreach($entry in @(@('a',70,40),@('b',110,50))){
        $id=$entry[0];$top=$entry[1];$height=$entry[2]
        $check=New-RowControl check 8 $top 24 $height;$check.Tag=$id
        $icon=New-RowControl icon 36 $top 32 $height
        $title=New-RowControl title 76 $top 330 $height
        $status=New-RowControl status 440 $top 150 $height
        foreach($control in @($check,$icon,$title,$status)){$box.Controls.Add($control)}
        $rows[$id]=[pscustomobject]@{Check=$check;Icon=$icon;Title=$title};$labels[$id]=$status;$checks+=,$check
    }
    $button=New-RowControl button 10 26 75 30;$box.Controls.Add($button)
    $group=[pscustomobject]@{Box=$box;Checks=$checks}
    $state=[pscustomobject]@{Running=$false;Pump=$null;Scale=1.0;GroupDragKey='';Groups=@($group);FeatureRows=$rows;FeatureLabels=$labels;ContentPanel=(New-RowControl content 0 0 640 400);Form=(New-RowControl form 0 0 800 600);Button=$button}
    & $module {param($s) Initialize-JobsFeatureRowSelection $s} $state
    return $state
}
# 只产生完整事件序列；不调用生产函数的替代实现。
function Click-RowControl {param($Control,[int]$X=4,[int]$Y=6,[string]$Button='Left') [void]$Control.Send('Down',$Button,$X,$Y);[void]$Control.Send('Up',$Button,$X,$Y)}
foreach($region in @('Icon','Title','Status','Gap','LeftBlank','RightBlank')) {
    $s=New-RowFixture;$check=$s.FeatureRows.a.Check
    $c=$s.FeatureRows.a.Icon;$x=4;$y=6
    switch($region){'Title'{$c=$s.FeatureRows.a.Title};'Status'{$c=$s.FeatureLabels.a};'Gap'{$c=$s.Groups[0].Box;$x=420;$y=80};'LeftBlank'{$c=$s.Groups[0].Box;$x=3;$y=80};'RightBlank'{$c=$s.Groups[0].Box;$x=598;$y=80}}
    Click-RowControl $c $x $y
    Assert-Row ($check.Checked -and $check.Changes -eq 1 -and $check.FocusCalls -eq 1) ('普通行区域单击只切换一次：'+$region)
    [void]$c.Send('Up','Left',$x,$y);[void]$s.Groups[0].Box.Send('Up','Left',420,80)
    Assert-Row ($check.Checked -and $check.Changes -eq 1) '重复或父级MouseUp不造成第二次切换'
    Click-RowControl $c $x $y
    Assert-Row (-not $check.Checked -and $check.Changes -eq 2) '下次独立点击仍可取消勾选'
}
$s=New-RowFixture;$check=$s.FeatureRows.a.Check
Click-RowControl $check
Assert-Row ($check.Checked -and $check.Changes -eq 1 -and $check.FocusCalls -eq 0) '原生checkbox只由自身AutoCheck切换，未附加第二个toggle'
$check.Space()
Assert-Row (-not $check.Checked -and $check.Changes -eq 2) 'Space沿用原生checkbox事件，新增行逻辑不截获键盘'
foreach($point in @(@(20,10),@(20,45),@(20,170),@(-1,80),@(600,80))){$s=New-RowFixture;Click-RowControl $s.Groups[0].Box $point[0] $point[1];Assert-Row ($s.FeatureRows.a.Check.Changes -eq 0 -and $s.FeatureRows.b.Check.Changes -eq 0) '组头/组尾/行外空白不被算作功能行'}
$s=New-RowFixture;Click-RowControl $s.Groups[0].Box 420 110
Assert-Row ($s.FeatureRows.b.Check.Checked -and -not $s.FeatureRows.a.Check.Checked) '相邻行边界按实际半开区间命中下一行'
$s=New-RowFixture;$target=$s.FeatureRows.a.Title
$s.FeatureRows.a.Check.add_CheckedChanged({[void]$target.Send('Up','Left',4,6)}.GetNewClosure())
Click-RowControl $target
Assert-Row ($s.FeatureRows.a.Check.Changes -eq 1) 'CheckedChanged重入抬起也只切换一次'
$s=New-RowFixture;$status=$s.FeatureLabels.a;[void]$status.Send('Down','Left',4,6);$status.LinkArea.Length=6;[void]$status.Send('Up','Left',4,6)
Assert-Row ($status.ActionCalls -eq 1 -and $s.FeatureRows.a.Check.Changes -eq 0) '按下后变为失败链接时，原动作优先且不误勾选'
$s=New-RowFixture;$s.FeatureLabels.a.LinkArea.Length=6
Click-RowControl $s.FeatureLabels.a
Assert-Row ($s.FeatureLabels.a.ActionCalls -eq 1 -and $s.FeatureRows.a.Check.Changes -eq 0) '失败日志链接执行自己的动作，不改变勾选'
$s.Running=$true;Click-RowControl $s.FeatureLabels.a
Assert-Row ($s.FeatureLabels.a.ActionCalls -eq 2 -and $s.FeatureRows.a.Check.Changes -eq 0) '执行中仍保留只读日志链接动作'
$s=New-RowFixture;Click-RowControl $s.Button
Assert-Row ($s.Button.ActionCalls -eq 1 -and $s.FeatureRows.a.Check.Changes -eq 0) '组内独立按钮保留自己的事件'
$action=New-RowControl button 410 70 30 40;$s.Groups[0].Box.Controls.Insert(0,$action)
Click-RowControl $s.Groups[0].Box 420 80
Assert-Row ($s.FeatureRows.a.Check.Changes -eq 0) '行内新增独立动作子控件优先于背景hit-test'
foreach($condition in @('busy','disabled','drag','pump')){
    $s=New-RowFixture
    switch($condition){'busy'{$s.Running=$true};'disabled'{$s.FeatureRows.a.Check.Enabled=$false};'drag'{$s.GroupDragKey='group-token'};'pump'{$s.Pump=[pscustomobject]@{Process=[pscustomobject]@{HasExited=$true};Drained=$false;Lines=[pscustomobject]@{IsEmpty=$true}}}}
    Click-RowControl $s.FeatureRows.a.Title
    Assert-Row ($s.FeatureRows.a.Check.Changes -eq 0) ('锁定的整行不改变勾选：'+$condition)
}
foreach($cancel in @('move','leave','wheel','scroll','scrollSnapshot','deactivate','crossSource','right','busyAfterDown','disabledAfterDown','dragAfterDown')){
    $s=New-RowFixture;$c=$s.FeatureRows.a.Title;[void]$c.Send('Down','Left',4,6)
    switch($cancel){
        'move'{[void]$c.Send('Move','Left',30,6);[void]$c.Send('Move','Left',4,6)}
        'leave'{[void]$c.Send('Leave','None',4,6)}
        'wheel'{$e=$c.Send('Wheel','None',4,6);Assert-Row (-not $e.Handled) '不消费原生滚动消息'}
        'scroll'{[void]$s.ContentPanel.Send('Scroll','None',0,0)}
        'scrollSnapshot'{$s.ContentPanel.AutoScrollPosition=New-Object Drawing.Point(0,-20)}
        'deactivate'{[void]$s.Form.Send('Deactivate','None',0,0)}
        'crossSource'{$c=$s.FeatureRows.a.Icon}
        'right'{[void]$c.Send('Down','Right',4,6)}
        'busyAfterDown'{$s.Running=$true}
        'disabledAfterDown'{$s.FeatureRows.a.Check.Enabled=$false}
        'dragAfterDown'{$s.GroupDragKey='group-token'}
    }
    [void]$c.Send('Up','Left',4,6)
    Assert-Row ($s.FeatureRows.a.Check.Changes -eq 0) ('拖动/滚动/取消/竞态不误切换：'+$cancel)
}
$s=New-RowFixture;$s.Scale=2;[void]$s.FeatureRows.a.Title.Send('Down','Left',4,6);[void]$s.FeatureRows.a.Title.Send('Move','Left',14,6);[void]$s.FeatureRows.a.Title.Send('Up','Left',14,6)
Assert-Row ($s.FeatureRows.a.Check.Changes -eq 1) '点击小范围容差随DPI缩放'
$s=New-RowFixture;$s.Scale=2;[void]$s.FeatureRows.a.Title.Send('Down','Left',4,6);[void]$s.FeatureRows.a.Title.Send('Up','Left',20,6)
Assert-Row ($s.FeatureRows.a.Check.Changes -eq 0) '即使没有Move事件，Up也校验移动阈值'
$s=New-RowFixture;[void]$s.FeatureRows.a.Title.Send('Down','Left',4,6);$s.FeatureRows.a.Check.Top=120;$s.FeatureRows.a.Title.Top=120;[void]$s.FeatureRows.a.Title.Send('Up','Left',4,6)
Assert-Row ($s.FeatureRows.a.Check.Changes -eq 0) '按下后布局变化不能切换旧位置候选'
$source=Join-Path $root 'Scripts/Installer.psm1';$hash=(Get-FileHash $source).Hash
$copies=@((Join-Path $root 'Scripts/SelectionPanel.psm1'),(Join-Path $root 'Infrastructure/SelectionPanel.psm1'))+@(Get-ChildItem $root -Directory -Filter Jobs*|ForEach-Object{Join-Path $_.FullName 'Scripts/SelectionPanel.psm1'}|Where-Object{[IO.File]::Exists($_)})
foreach($copy in $copies){Assert-Row ((Get-FileHash $copy).Hash -ceq $hash) '38份管理面板保持同源'}
Write-Host ('PASS: PanelRowSelection.Tests.ps1 ('+$script:checks+' assertions; native Windows input: False)')
