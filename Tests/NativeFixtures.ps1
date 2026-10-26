# NativeFixtures.ps1 | WindowsOS@Extension 隔离原生夹具
# Created by Jobs on 2026年10月26日，星期一.
# 只在调用方临时目录生成探针；符号链接权限不足明确记录局部跳过。
function New-JobsTestArgumentProbe {
    param([string]$Directory)
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        $executable = Join-Path $Directory 'argv-probe.exe'
        $source = @'
using System;
using System.Text;
public static class JobsArgumentProbe {
    public static void Main(string[] args) {
        Console.OutputEncoding = new UTF8Encoding(false);
        StringBuilder json = new StringBuilder("[");
        for (int index = 0; index < args.Length; index++) {
            if (index != 0) json.Append(',');
            json.Append('"');
            foreach (char value in args[index]) {
                switch (value) {
                    case '"': json.Append("\\\""); break;
                    case '\\': json.Append("\\\\"); break;
                    default:
                        if (value < 32) json.Append("\\u").Append(((int)value).ToString("x4"));
                        else json.Append(value);
                        break;
                }
            }
            json.Append('"');
        }
        Console.Write(json.Append(']').ToString());
    }
}
'@
        # 5.1 Add-Type 的 OutputAssembly 会解析通配符；csc 接收字面文件路径。
        $sourcePath = Join-Path $Directory 'argv-probe.cs'
        [IO.File]::WriteAllText($sourcePath, $source, (New-Object Text.UTF8Encoding($true)))
        $compiler = Join-Path ([Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()) 'csc.exe'
        if (-not [IO.File]::Exists($compiler)) { throw '系统 .NET Framework C# 编译器不存在，无法执行真实 argv 夹具。' }
        $compilerOutput = @(& $compiler /nologo /target:exe /platform:anycpu /utf8output ('/out:' + $executable) $sourcePath 2>&1)
        if ($LASTEXITCODE -ne 0 -or -not [IO.File]::Exists($executable)) { throw ('原生 argv 夹具编译失败：' + ($compilerOutput -join [Environment]::NewLine)) }
        return [pscustomobject]@{ Executable = $executable; Prefix = [string[]]@() }
    }
    $script = Join-Path $Directory 'argv-probe.ps1'
    $body = '[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false); [Console]::Write((ConvertTo-Json -InputObject @($args) -Compress))'
    [IO.File]::WriteAllText($script, $body, (New-Object Text.UTF8Encoding($true)))
    return [pscustomobject]@{ Executable = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName; Prefix = [string[]]@('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $script) }
}

function New-JobsTestSymbolicLink {
    param([string]$Path, [string]$Target, [switch]$Directory)
    try {
        $linkType = [IO.File]
        if ($Directory) { $linkType = [IO.Directory] }
        $create = $linkType.GetMethod('CreateSymbolicLink', [type[]]@([string], [string]))
        if ($null -ne $create) {
            [void]$create.Invoke($null, [object[]]@($Path, $Target))
        } elseif ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
            if (-not ('Jobs.TestSymbolicLink' -as [type])) {
                Add-Type -TypeDefinition @'
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace Jobs {
    public static class TestSymbolicLink {
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.U1)]
        private static extern bool CreateSymbolicLinkW(string linkPath, string targetPath, uint flags);
        public static void Create(string linkPath, string targetPath, bool directory) {
            uint flags = directory ? 1u : 0u;
            if (CreateSymbolicLinkW(linkPath, targetPath, flags | 2u)) return;
            int error = Marshal.GetLastWin32Error();
            if (error == 87) {
                if (CreateSymbolicLinkW(linkPath, targetPath, flags)) return;
                error = Marshal.GetLastWin32Error();
            }
            throw new Win32Exception(error);
        }
    }
}
'@
            }
            [Jobs.TestSymbolicLink]::Create($Path, $Target, $Directory.IsPresent)
        } else { throw '当前运行时没有可用的符号链接 API。' }
    } catch {
        $errorObject = $_.Exception
        while ($null -ne $errorObject) {
            if ($errorObject -is [ComponentModel.Win32Exception] -and $errorObject.NativeErrorCode -eq 1314) {
                [Console]::WriteLine('SKIP: 当前 Windows 用户缺少符号链接权限，仅跳过此真实链接夹具：' + $Path)
                return $false
            }
            $errorObject = $errorObject.InnerException
        }
        throw
    }
    if (([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw ('链接夹具未正确创建：' + $Path) }
    return $true
}
