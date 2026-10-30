# FileVolumes.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年10月28日，星期三.
# 仅临时目录、真实文件流、注册计划和独立打包；不注册或打开菜单。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'JobsFileVolumes/Scripts/FileVolumes.ps1')
. (Join-Path $root 'JobsFileVolumes/Scripts/SelectionRequest.ps1')
. (Join-Path $PSScriptRoot 'NativeFixtures.ps1')
$script:assertions = 0
function Assert-Volumes {
    param([bool]$Condition, [string]$Message)
    $script:assertions++
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
}
function Assert-VolumesThrows {
    param([scriptblock]$Run, [string]$Message)
    $threw = $false
    try { & $Run | Out-Null } catch { $threw = $true }
    Assert-Volumes $threw $Message
}
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsVolumes-' + [guid]::NewGuid().ToString('N'))
try {
    [void][IO.Directory]::CreateDirectory($temporary)
    $file = Join-Path $temporary "中文 & %TEMP% ' `$() [x]@extra.bin"
    $data = New-Object byte[] 3145733
    $random = New-Object Random 492
    $random.NextBytes($data)
    [IO.File]::WriteAllBytes($file, $data)
    $digest = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    $split = Invoke-JobsFileSplit -Path $file -LimitBytes 300000
    Assert-Volumes ($split -ceq ($file + '.chunks')) '拆分采用完整源文件名.chunks目录'
    $parts = @(Get-ChildItem -LiteralPath $split -File)
    Assert-Volumes ($parts.Count -eq 11) '均匀拆分为ceil(size/limit)卷'
    Assert-Volumes (@($parts | Where-Object { $_.Length -gt 300000 -or $_.Length -lt 1 }).Count -eq 0) '每卷正长度且不超过上限'
    Assert-Volumes ((Get-FileHash -LiteralPath $file).Hash -ceq $digest) '拆分保留源文件且内容不变'
    $reverse = @($parts | Sort-Object Name -Descending | ForEach-Object FullName)
    $group = Get-JobsVolumeGroup -Paths $reverse
    Assert-Volumes ($group.Files[0].Name.EndsWith('@1of11') -and $group.Files[10].Name.EndsWith('@11of11')) '按数值排序而非字典序或选择序'
    $merged = Invoke-JobsFileMerge -Paths $reverse
    Assert-Volumes ((Get-FileHash -LiteralPath $merged).Hash -ceq $digest) '跨块真实随机字节拆分再合并SHA256一致'
    Assert-Volumes (@(Get-ChildItem -LiteralPath $split -File).Count -eq 12) '合并后原有11分卷保留'
    Assert-VolumesThrows { Invoke-JobsFileMerge -Paths $reverse } '同名合并目标不覆盖'
    Assert-Volumes ((Get-FileHash -LiteralPath $merged).Hash -ceq $digest) '拒绝覆盖后原有目标不变'
    Assert-VolumesThrows { Invoke-JobsFileSplit -Path $file -LimitBytes 300000 } '同名分卷目录不覆盖'
    foreach ($limit in @([long]0, [long]-1, [long]$data.Length, [long]($data.Length + 1))) {
        Assert-VolumesThrows { Invoke-JobsFileSplit -Path $file -LimitBytes $limit } '零负数/文件不大于上限均拒绝'
    }
    Assert-VolumesThrows { Get-JobsVolumeGroup -Paths @($reverse[0]) } '单卷不能触发合并'
    Assert-VolumesThrows { Get-JobsVolumeGroup -Paths @($reverse[0], $reverse[0]) } '重复路径拒绝'
    Assert-VolumesThrows { Get-JobsVolumeGroup -Paths @($reverse[0], $reverse[1]) } '不扫描目录补齐未选分卷'
    Assert-VolumesThrows { Get-JobsVolumeGroup -Paths @($reverse + $file) } '混入普通文件拒绝'
    Assert-VolumesThrows { Get-JobsVolumeFile $temporary } '目录拒绝'
    $bad = Join-Path $temporary 'bad.bin@1of2'
    $bad2 = Join-Path $temporary 'bad.bin@2of2'
    [IO.File]::WriteAllBytes($bad, [byte[]]@(1)); [IO.File]::WriteAllBytes($bad2, [byte[]]@())
    Assert-VolumesThrows { Get-JobsVolumeGroup @($bad, $bad2) } '空卷拒绝'
    [IO.File]::WriteAllBytes($bad2, [byte[]]@(2))
    $duplicate = Join-Path $temporary 'bad.bin@01of2'
    [IO.File]::WriteAllBytes($duplicate, [byte[]]@(3))
    Assert-VolumesThrows { Get-JobsVolumeGroup @($bad, $duplicate) } '补零后的编号重复拒绝'
    foreach ($name in @('CON@1of2', 'nul.txt@1of2', 'com1@1of2', 'abc.@1of2', 'abc @1of2', '.@1of2', '..@1of2', 'a@0of2', 'a@3of2', 'a@1of0', 'a@1000000000of2', "bad`nname@1of2")) {
        Assert-VolumesThrows { Get-JobsVolumePart $name } ('非法卷名拒绝：' + $name)
    }
    $one = Get-JobsVolumePart 'x@nested.tar.gz@001of002'
    Assert-Volumes ($one.Name -ceq 'x@nested.tar.gz' -and $one.Index -eq 1 -and $one.Total -eq 2) '最后一个@解析且兼容补零'
    # Windows共享锁真实验证；Mac / PS7 的文件共享语义不推断为NTFS锁。
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $writer = [IO.File]::Open($bad, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        try { Assert-VolumesThrows { Invoke-JobsFileMerge @($bad, $bad2) } '输入已有写入者时停止且不创建结果' } finally { $writer.Dispose() }
    }
    $link = Join-Path $temporary 'linked@1of2'
    if (New-JobsTestSymbolicLink -Path $link -Target $bad) { Assert-VolumesThrows { Get-JobsVolumeFile $link } '真实符号链接拒绝' }
    $snapshot = Get-JobsVolumeFile $bad
    [IO.File]::AppendAllText($bad, 'changed')
    Assert-VolumesThrows { Assert-JobsVolumeUnchanged $snapshot } '输入状态变化拒绝发布'
    # 流失败必须保留独占候选、源文件及全部分卷；不产生看似完整的结果。
    $functionBody = ${function:Add-JobsVolumeStream}
    function Add-JobsVolumeStream { throw 'injected read failure' }
    try { Assert-VolumesThrows { Invoke-JobsFileMerge -Paths @($bad, $bad2) } '中途失败向调用者报告失败' }
    finally { ${function:Add-JobsVolumeStream} = $functionBody }
    Assert-Volumes (-not [IO.File]::Exists((Join-Path $temporary 'bad.bin'))) '失败候选不会发布为完整文件'
    Assert-Volumes (@(Get-ChildItem -LiteralPath $temporary -Force -Filter '.JobsMerge-*.partial').Count -eq 1) '失败候选保留供排查'
    $module = Import-Module (Join-Path $root 'JobsFileVolumes/Scripts/PackageInstaller.psm1') -PassThru -DisableNameChecking
    $manifest = Get-Content -LiteralPath (Join-Path $root 'JobsFileVolumes/Extension.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $plan = @(Get-JobsPackageRegistryPlan -Manifest $manifest -ReleasePath $temporary -PowerShellPath 'C:\Windows\powershell.exe')
    Assert-Volumes ($plan.Count -eq 2 -and $plan[0].Key -ceq 'Software\Classes\*\shellex\ContextMenuHandlers\Jobs.WindowsExtension.file-volumes') '只注册文件动态handler和本包CLSID'
    Assert-Volumes ($plan[1].InProcServer -ceq (Join-Path $temporary 'bin/JobsFileVolumesContextMenu.dll')) '原生DLL归本包且无静态菜单降级'
    Remove-Module $module
    $requestDirectory = Join-Path ([IO.Path]::GetTempPath()) 'JobsFileVolumes'
    [void][IO.Directory]::CreateDirectory($requestDirectory)
    $requests = @()
    try {
        $request = Join-Path $requestDirectory ('selection-' + [guid]::NewGuid().ToString() + '.json')
        $requests += $request
        $json = ConvertTo-Json -InputObject @($file, $bad) -Compress
        [IO.File]::WriteAllText($request, $json, (New-Object Text.UTF8Encoding($false)))
        $selection = @(Read-JobsVolumeRequest $request)
        Assert-Volumes ($selection.Count -eq 2 -and $selection[0] -ceq $file -and $selection[1] -ceq $bad) 'JSON精确路径含中文和脚本符号按数据往返'
        Assert-Volumes (-not [IO.File]::Exists($request)) '成功消费只删除本次临时请求'
        foreach ($invalid in @('[]', '[null]', '[42]', '[""]', '"path"', '{"path":"x"}', '[["x"]]', '["x",["y"]]', '["x"')) {
            $request = Join-Path $requestDirectory ('selection-' + [guid]::NewGuid().ToString() + '.json')
            $requests += $request
            [IO.File]::WriteAllText($request, $invalid, (New-Object Text.UTF8Encoding($false)))
            Assert-VolumesThrows { Read-JobsVolumeRequest $request } ('无效清单拒绝：' + $invalid)
            Assert-Volumes ([IO.File]::Exists($request)) '无效请求不擅自删除文件'
        }
        $outside = Join-Path $temporary ('selection-' + [guid]::NewGuid().ToString() + '.json')
        [IO.File]::WriteAllText($outside, '["x"]')
        Assert-VolumesThrows { Read-JobsVolumeRequest $outside } '拒绝本包临时目录之外请求'
        Assert-Volumes ([IO.File]::Exists($outside)) '目录之外文件保持不动'
    } finally {
        foreach ($request in $requests) { if ([IO.File]::Exists($request)) { [IO.File]::Delete($request) } }
    }
    [Console]::WriteLine(('PASS: FileVolumes.Tests.ps1 ({0} assertions)' -f $script:assertions))
} finally {
    if ([IO.Directory]::Exists($temporary)) { Remove-Item -LiteralPath $temporary -Recurse -Force }
}
