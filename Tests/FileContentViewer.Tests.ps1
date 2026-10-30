# FileContentViewer.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月27日，星期二.
# 临时文件和隔离终端输出，不安装、不注册，不读取用户业务文件。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'JobsFileContentViewer/Scripts/FileViewer.ps1')
. (Join-Path $PSScriptRoot 'NativeFixtures.ps1')
$script:assertions = 0
function Assert-Viewer {
    param([bool]$Condition, [string]$Reason)
    $script:assertions++
    if (-not $Condition) { throw ('FAIL: ' + $Reason) }
}
function Assert-ViewerThrows {
    param([scriptblock]$Run, [string]$Reason)
    $threw = $false
    try { & $Run | Out-Null } catch { $threw = $true }
    Assert-Viewer $threw $Reason
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsViewer-' + [guid]::NewGuid().ToString('N'))
$savedLimit = [Environment]::GetEnvironmentVariable('JOBS_FILE_VIEWER_MAX_BYTES')
$savedOut = [Console]::Out
$script:prompts = @()
$script:answers = New-Object 'Collections.Generic.Queue[string]'
$script:hostMessages = @()
function Write-Host { param($Object, $ForegroundColor) $script:hostMessages += [string]$Object }
function Read-Host {
    param($Prompt)
    $script:prompts += $Prompt
    if ($script:answers.Count -eq 0) { return $null }
    return $script:answers.Dequeue()
}
function Invoke-ViewerFixture {
    param([string]$Path, [string[]]$Answers = @())
    $script:prompts = @()
    $script:answers.Clear()
    $script:hostMessages = @()
    foreach ($answer in $Answers) { $script:answers.Enqueue($answer) }
    $writer = New-Object IO.StringWriter
    [Console]::SetOut($writer)
    try {
        Invoke-JobsFileContentViewer -Target $Path
        return $writer.ToString()
    } finally { [Console]::SetOut($savedOut); $writer.Dispose() }
}
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    Remove-Item Env:JOBS_FILE_VIEWER_MAX_BYTES -ErrorAction SilentlyContinue
    Assert-Viewer ((Get-JobsFileViewerLimit) -eq 1048576) '默认阈值为 1 MiB'
    foreach ($invalid in @('0', '-1', '1.5', 'YES', '9223372036854775808', ' 12')) {
        $env:JOBS_FILE_VIEWER_MAX_BYTES = $invalid
        Assert-ViewerThrows { Get-JobsFileViewerLimit } ('非法阈值停止：' + $invalid)
    }
    $env:JOBS_FILE_VIEWER_MAX_BYTES = '12'
    Assert-Viewer ((Get-JobsFileViewerLimit) -eq 12) '自定义阈值按字节处理'
    $file = Join-Path $temporary "中文 & %TEMP% ' `$() [literal].txt"
    $text = '中文 $(throw "must not run") & %TEMP%'
    [IO.File]::WriteAllText($file, $text, (New-Object Text.UTF8Encoding($false)))
    $hash = (Get-FileHash -LiteralPath $file).Hash
    $before = [IO.File]::GetLastWriteTimeUtc($file)
    foreach ($answer in @('', 'yes', ' YES', 'NO')) {
        $result = Invoke-ViewerFixture -Path $file -Answers @($answer)
        Assert-Viewer ($result.Length -eq 0 -and $script:prompts.Count -eq 1) '大文件取消前不输出内容，只有精确 YES 执行'
        Assert-Viewer (($script:hostMessages -join '') -match '未读取文件内容') '取消文案明确未读取正文'
    }
    $result = Invoke-ViewerFixture -Path $file
    Assert-Viewer ($result.Length -eq 0) '输入结束默认取消'
    $result = Invoke-ViewerFixture -Path $file -Answers @('YES')
    Assert-Viewer ($result -ceq $text) '确认后只显示文件原文，特殊路径和脚本正文不求值'
    Assert-Viewer ((Get-FileHash -LiteralPath $file).Hash -ceq $hash -and [IO.File]::GetLastWriteTimeUtc($file) -eq $before) '查看不改文件内容或修改时间'

    $env:JOBS_FILE_VIEWER_MAX_BYTES = ([IO.FileInfo]$file).Length.ToString()
    $result = Invoke-ViewerFixture -Path $file
    Assert-Viewer ($result -ceq $text -and $script:prompts.Count -eq 0) '恰好阈值直接输出'
    $env:JOBS_FILE_VIEWER_MAX_BYTES = '1048576'
    foreach ($encoding in @((New-Object Text.UTF8Encoding($true)), [Text.Encoding]::Unicode, [Text.Encoding]::BigEndianUnicode, [Text.Encoding]::UTF32)) {
        [IO.File]::WriteAllText($file, "中文🙂`r`n下一行", $encoding)
        $result = Invoke-ViewerFixture -Path $file
        Assert-Viewer ($result -ceq "中文🙂`n下一行" -and $script:prompts.Count -eq 0) ('识别 Unicode BOM：' + $encoding.WebName)
    }
    # 第 8192 字节落在 UTF-8 多字节中间，4096 字符落在代理对/CRLF中间。
    foreach ($text in @(('a' * 8191 + '中文🙂'), ('a' * 4095 + '🙂end'), ('a' * 4095 + "`r`nend"), ('a' * 4095 + "`rend"))) {
        [IO.File]::WriteAllText($file, $text, (New-Object Text.UTF8Encoding($false)))
        $result = Invoke-ViewerFixture -Path $file
        $expected = $text.Replace("`r`n", "`n").Replace("`r", '\r')
        Assert-Viewer ($result -ceq $expected -and $script:prompts.Count -eq 0) '采样/输出跨块保持 UTF-8、多码点与CRLF内容'
    }
    [IO.File]::WriteAllText($file, ('safe' + [char]27 + ']0;title' + [char]7 + [char]0), (New-Object Text.UTF8Encoding($false)))
    $result = Invoke-ViewerFixture -Path $file
    Assert-Viewer ($result.Length -eq 0 -and $script:prompts.Count -eq 1) '疑似二进制默认取消'
    $result = Invoke-ViewerFixture -Path $file -Answers @('YES')
    Assert-Viewer ($result -ceq 'safe\u001B]0;title\u0007\u0000') '危险终端控制符仅以转义文字输出'
    [IO.File]::WriteAllBytes($file, [byte[]]@(255, 128, 65))
    $result = Invoke-ViewerFixture -Path $file -Answers @('YES')
    Assert-Viewer ($result -ceq ([string][char]65533 + [char]65533 + 'A')) '未知编码确认后替换无效字节'
    Assert-ViewerThrows { Invoke-ViewerFixture -Path $temporary } '目录后台拒绝'
    Assert-ViewerThrows { Invoke-ViewerFixture -Path (Join-Path $temporary 'missing') } '已删除文件后台拒绝'
    $link = Join-Path $temporary 'link.txt'
    if (New-JobsTestSymbolicLink -Path $link -Target $file) {
        Assert-ViewerThrows { Invoke-ViewerFixture -Path $link } '符号链接后台拒绝'
    }
    $largeText = 'x' * 1048577
    [IO.File]::WriteAllText($file, $largeText, (New-Object Text.UTF8Encoding($false)))
    $result = Invoke-ViewerFixture -Path $file -Answers @('YES')
    Assert-Viewer ($result -ceq $largeText -and $script:prompts.Count -eq 1) '超过默认阈值的大型无换行文本可流式完整查看'
    $installer = Import-Module (Join-Path $root 'JobsFileContentViewer/Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    $manifest = Get-Content -LiteralPath (Join-Path $root 'JobsFileContentViewer/Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $plan = @(Get-JobsPackageRegistryPlan -Manifest $manifest -ReleasePath $temporary -PowerShellPath 'C:\Windows\powershell.exe')
    Assert-Viewer ($plan.Count -eq 2) '本包只注册文件 handler 与本包 CLSID'
    Assert-Viewer ($plan[0].Key -ceq 'Software\Classes\*\shellex\ContextMenuHandlers\Jobs.WindowsExtension.file-content-viewer') '无目录或背景菜单'
    Remove-Module $installer
    # 真实子进程经过生产 Action，验证输出编码，不使用内存 StringWriter 代替终端编码。
    [IO.File]::WriteAllText($file, ('a' * 4095 + '🙂中文'), (New-Object Text.UTF8Encoding($false)))
    $harness = Join-Path $temporary 'ViewerProcess.ps1'
    $actionPath = (Join-Path $root 'JobsFileContentViewer/Scripts/Action.psm1').Replace("'", "''")
    $harnessBody = 'param([string]$Target)' + [Environment]::NewLine +
        "Import-Module '$actionPath' -DisableNameChecking" + [Environment]::NewLine +
        'Invoke-JobsFeature -Target $Target'
    [IO.File]::WriteAllText($harness, $harnessBody, (New-Object Text.UTF8Encoding($true)))
    Import-Module (Join-Path $root 'JobsFileContentViewer/Scripts/Common.psm1') -DisableNameChecking
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $start.Arguments = ((@('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $harness, '-Target', $file) | ForEach-Object { Quote-JobsArgument $_ }) -join ' ')
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.StandardOutputEncoding = New-Object Text.UTF8Encoding($false, $true)
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(15000)) { $process.Kill(); throw '真实编码输出夹具超时。' }
        Assert-Viewer ($process.ExitCode -eq 0) ('真实 Action 子进程成功：' + $stderr.GetAwaiter().GetResult())
        Assert-Viewer ($stdout.GetAwaiter().GetResult().Contains(('a' * 4095 + '🙂中文'))) '真实UTF8字节输出保留中文和跨块emoji'
    } finally { $process.Dispose() }
    [Console]::WriteLine(('PASS: FileContentViewer.Tests.ps1 ({0} assertions)' -f $script:assertions))
} finally {
    [Console]::SetOut($savedOut)
    [Environment]::SetEnvironmentVariable('JOBS_FILE_VIEWER_MAX_BYTES', $savedLimit)
    if ([IO.Directory]::Exists($temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
