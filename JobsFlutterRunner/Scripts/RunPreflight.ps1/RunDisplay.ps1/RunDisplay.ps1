# RunDisplay.ps1 | Flutter 运行链的终端展示。
# Created by Jobs on 2026年11月15日，星期日.
# 只格式化终端副本；返回数据、SDK原始日志与调用参数保持原文。

# 仅可靠交互控制台启用颜色；VT 不可用时不发送下划线控制序列。
function Test-JobsRunnerDisplayColor {
    return ((Test-JobsRunnerInteractiveMenu) -and -not (Test-Path Env:NO_COLOR) -and $env:PLAIN_OUTPUT -ne '1' -and $env:TERM -ine 'dumb')
}
# 编译本进程的展示过滤器，不安装组件、不修改宿主或持久配置。
function Initialize-JobsRunnerDisplay {
    if('Jobs.RunnerDisplayV1.Formatter'-as[type]){return}
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;
namespace Jobs.RunnerDisplayV1 {
    public static class Formatter {
        static readonly Regex Url = new Regex(@"\b[a-z][a-z0-9+.-]*://[^\x00-\x20<>""'，。；！？【】]+", RegexOptions.IgnoreCase);
        static readonly Regex Label = new Regex(@"\[(会话|依赖|警告|错误|构建|运行|下载|SDK|日志)\]");
        static string Emoji(string label) {
            switch(label) { case "会话": return "💬"; case "依赖": return "📦"; case "警告": return "⚠️"; case "错误": return "❌"; case "构建": return "🔨"; case "运行": return "▶️"; case "下载": return "⬇️"; case "SDK": return "🧰"; default: return "📝"; }
        }
        public static string Format(string text, bool color, bool underline, string foreground) {
            if(text == null) return "";
            if(text.IndexOf('\n')>=0 || text.IndexOf('\r')>=0) return Regex.Replace(text,@"[^\r\n]+",delegate(Match line){return Format(line.Value,color,underline,foreground);});
            string labelled=Label.Replace(text, delegate(Match match) {
                string emoji=Emoji(match.Groups[1].Value);
                return text.Substring(0,match.Index).TrimEnd().EndsWith(emoji,StringComparison.Ordinal) ? match.Value : emoji+" "+match.Value;
            });
            if(!color) return Regex.Replace(labelled, @"\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1b]*(?:\x07|\x1b\\))", "");
            bool error=Regex.IsMatch(labelled,@"(?im)\[错误\]|\[ERROR\]|^\s*(?:❌|error\b|fail(?:ed)?\b)|Exception:");
            string tone=error ? "31" : foreground;
            string result=Url.Replace(labelled,delegate(Match match) {
                string value=match.Value, tail="";
                while(value.Length>0 && ".,;:!?）]".IndexOf(value[value.Length-1])>=0) { tail=value[value.Length-1]+tail;value=value.Substring(0,value.Length-1); }
                while(value.EndsWith(")",StringComparison.Ordinal) && value.Split(')').Length>value.Split('(').Length) { tail=")"+tail;value=value.Substring(0,value.Length-1); }
                return "\x1b[32"+(underline?";4":"")+"m"+value+"\x1b["+(underline?"24;":"")+tone+"m"+tail;
            });
            return error ? "\x1b[31m"+result+"\x1b["+foreground+"m" : result;
        }
    }
    public sealed class Writer : TextWriter {
        readonly TextWriter target; readonly bool color, underline; readonly object gate=new object(); readonly StringBuilder pending=new StringBuilder();
        public Writer(TextWriter writer,bool useColor,bool useUnderline) {target=writer;color=useColor;underline=useUnderline;}
        public override Encoding Encoding {get{return target.Encoding;}}
        string Tone() {int n=(int)Console.ForegroundColor;int[] map={30,34,32,36,31,35,33,37,90,94,92,96,91,95,93,97};return n>=0&&n<map.Length?map[n].ToString():"39";}
        public override void Write(char value) {Write(value.ToString());}
        public override void Write(string value) {
            if(value==null)return;
            lock(gate){foreach(char ch in value){if(ch=='\r'||ch=='\n'){target.Write(Formatter.Format(pending.ToString(),color,underline,Tone()));pending.Length=0;target.Write(ch);}else{pending.Append(ch);if(pending.Length>=16384){target.Write(Formatter.Format(pending.ToString(),color,underline,Tone()));pending.Length=0;}}}}
        }
        public override void Flush() {lock(gate){if(pending.Length>0){target.Write(Formatter.Format(pending.ToString(),color,underline,Tone()));pending.Length=0;}target.Flush();}}
    }
}
'@
}
# 渲染脚本的结构化行，错误整行标红，URL单独绿色下划线。
function Write-JobsRunnerDisplayText {
    [CmdletBinding()]
    param([Parameter(Position=0)][AllowNull()][object]$Object,[switch]$NoNewline,[ConsoleColor]$ForegroundColor,[ConsoleColor]$BackgroundColor,[object]$Separator=' ')
    Initialize-JobsRunnerDisplay
    $text=if($Object-is[array]){$Object-join[string]$Separator}else{[string]$Object}
    $color=Test-JobsRunnerDisplayColor
    $property=$Host.UI.PSObject.Properties['SupportsVirtualTerminal']
    $underline=$color-and$null-ne$property-and[bool]$property.Value
    $tone=if($PSBoundParameters.ContainsKey('ForegroundColor')){[int]$ForegroundColor}else{[int][Console]::ForegroundColor}
    $codes=@(30,34,32,36,31,35,33,37,90,94,92,96,91,95,93,97)
    $foreground=if($tone-ge0-and$tone-lt$codes.Count){[string]$codes[$tone]}else{'39'}
    $display=[Jobs.RunnerDisplayV1.Formatter]::Format($text,($color-and$underline),$underline,$foreground)
    if($color-and-not$underline){
        $native=@{}
        if($PSBoundParameters.ContainsKey('BackgroundColor')){$native.BackgroundColor=$BackgroundColor}
        $normal=if($PSBoundParameters.ContainsKey('ForegroundColor')){$ForegroundColor}else{[Console]::ForegroundColor}
        if($display-match'(?im)\[错误\]|\[ERROR\]|^\s*(?:❌|error\b|fail(?:ed)?\b)|Exception:'){$normal=[ConsoleColor]::Red}
        $offset=0
        foreach($match in [regex]::Matches($display,'(?i)\b[a-z][a-z0-9+.-]*://[^\x00-\x20<>"''，。；！？【】]+')){
            if($match.Index-gt$offset){Microsoft.PowerShell.Utility\Write-Host $display.Substring($offset,$match.Index-$offset) -ForegroundColor $normal -NoNewline @native}
            Microsoft.PowerShell.Utility\Write-Host $match.Value -ForegroundColor Green -NoNewline @native
            $offset=$match.Index+$match.Length
        }
        if($offset-lt$display.Length){Microsoft.PowerShell.Utility\Write-Host $display.Substring($offset) -ForegroundColor $normal -NoNewline @native}
        if(-not$NoNewline){Microsoft.PowerShell.Utility\Write-Host}
        return
    }
    $options=@{NoNewline=[bool]$NoNewline}
    if($color-and$PSBoundParameters.ContainsKey('ForegroundColor')){$options.ForegroundColor=$ForegroundColor}
    if($color-and$PSBoundParameters.ContainsKey('BackgroundColor')){$options.BackgroundColor=$BackgroundColor}
    Microsoft.PowerShell.Utility\Write-Host $display @options
}
# SDK双流输出也经过展示过滤器，退出时精确还原原TextWriter。
function Start-JobsRunnerConsoleDisplay {
    Initialize-JobsRunnerDisplay
    $color=Test-JobsRunnerDisplayColor
    $property=$Host.UI.PSObject.Properties['SupportsVirtualTerminal'];$underline=$color-and$null-ne$property-and[bool]$property.Value
    $snapshot=[pscustomobject]@{Out=[Console]::Out;Error=[Console]::Error}
    [Console]::SetOut((New-Object Jobs.RunnerDisplayV1.Writer ([Console]::Out),($color-and$underline),$underline))
    [Console]::SetError((New-Object Jobs.RunnerDisplayV1.Writer ([Console]::Error),($color-and$underline),$underline))
    return $snapshot
}
# 正常、失败和可捕获中断均恢复本次接管的输出对象。
function Restore-JobsRunnerConsoleDisplay {
    param($Snapshot)
    if($null-eq$Snapshot){return}
    try { [Console]::Out.Flush();[Console]::Error.Flush() }
    finally { [Console]::SetOut($Snapshot.Out);[Console]::SetError($Snapshot.Error) }
}
