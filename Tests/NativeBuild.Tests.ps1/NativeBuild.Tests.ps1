# NativeBuild.Tests.ps1 | WindowsOS@Extension
# Created by Jobs on 2026年11月13日，星期五.
# 仅执行构建脚本的响应文件生成片段，检查 MSVC 实际按行处理 /link 的参数边界。
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$repository = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('JobsNative [中文] '' & ' + [guid]::NewGuid().ToString('N'))
$script:checks = 0
function Assert-NativeBuild {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw ('FAIL: ' + $Message) }
    $script:checks++
}
function Read-ClResponse {
    param([string]$Text)
    $compile = @()
    $link = @()
    foreach ($line in ($Text -split '\r?\n')) {
        $toLinker = $false
        foreach ($match in [regex]::Matches($line, '(?:[^\s"]|"[^"]*")+')) {
            $value = $match.Value.Replace('"', '')
            if ($value -ieq '/link') { $toLinker = $true; continue }
            if ($toLinker) { $link += $value } else { $compile += $value }
        }
    }
    return [pscustomobject]@{ Compile = $compile; Link = $link }
}
try {
    # 旧的逐行响应文件必须被识别为错误：/OUT 和 /DEF 不会继承上一行的 /link。
    $old = Read-ClResponse "/LD`n/link`n/OUT:wrong.dll`n/DEF:wrong.def"
    Assert-NativeBuild ($old.Compile -contains '/OUT:wrong.dll' -and $old.Link.Count -eq 0) '按 MSVC 物理行规则识别旧失败场景'
    $builds = @(Get-ChildItem -LiteralPath $repository -Directory | Where-Object { $_.Name -like 'Jobs*' } | ForEach-Object {
        $path = Join-Path $_.FullName 'Scripts/Build.ps1'
        if ([IO.File]::Exists($path)) { Get-Item -LiteralPath $path }
    })
    Assert-NativeBuild ($builds.Count -gt 0) '发现独立原生构建入口'
    foreach ($build in $builds) {
        $package = Split-Path -Parent $build.DirectoryName
        $packageName = Split-Path -Leaf $package
        $source = [IO.File]::ReadAllText($build.FullName)
        $block = [regex]::Match($source, '(?s)\$response = Join-Path \$output ''native\.rsp''.*?(?=\$buildStart =)')
        Assert-NativeBuild $block.Success ($packageName + ' 可隔离响应文件生成阶段')
        $output = Join-Path $temporary ($packageName + ' output')
        $scripts = Join-Path $temporary ($packageName + ' source/Scripts')
        [void][IO.Directory]::CreateDirectory($output)
        & ([scriptblock]::Create($block.Value))
        $response = Join-Path $output 'native.rsp'
        Assert-NativeBuild ([IO.File]::Exists($response)) ($packageName + ' 实际生成响应文件')
        $options = Read-ClResponse ([IO.File]::ReadAllText($response))
        $definition = [IO.File]::ReadAllText((Join-Path $build.DirectoryName 'ContextMenu.def'))
        $library = [regex]::Match($definition, '(?m)^LIBRARY\s+(\S+)').Groups[1].Value
        Assert-NativeBuild (-not [string]::IsNullOrWhiteSpace($library)) ($packageName + ' 导出定义声明本包 DLL')
        Assert-NativeBuild ($options.Link -contains ('/OUT:' + (Join-Path $output ($library + '.dll')))) ($packageName + ' 链接器接收准确输出路径')
        Assert-NativeBuild ($options.Link -contains ('/DEF:' + (Join-Path $scripts 'ContextMenu.def'))) ($packageName + ' 链接器接收导出定义')
        Assert-NativeBuild (@($options.Compile | Where-Object { $_ -match '^/(OUT|DEF):' }).Count -eq 0) ($packageName + ' 链接参数没有误传编译器')
        Assert-NativeBuild ($options.Compile -contains (Join-Path $scripts 'ContextMenu.cpp')) ($packageName + ' 中文空格及特殊字符源码路径不拆分')
        Assert-NativeBuild ($options.Compile -contains ('/Fo' + (Join-Path $output 'ContextMenu.obj'))) ($packageName + ' 对象文件输出路径不拆分')
        foreach ($libraryFile in @('shell32.lib', 'shlwapi.lib', 'ole32.lib', 'uuid.lib', 'user32.lib')) {
            Assert-NativeBuild ($options.Link -contains $libraryFile) ($packageName + ' 链接系统库 ' + $libraryFile)
        }
    }
    Write-Host ('PASS: NativeBuild.Tests.ps1 (' + $builds.Count + ' packages, ' + $script:checks + ' assertions)')
} finally {
    if ([IO.Directory]::Exists($temporary)) { [IO.Directory]::Delete($temporary, $true) }
}
