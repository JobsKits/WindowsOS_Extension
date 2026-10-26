# RunPermissions.ps1 | shared source embedded independently in both permission packages
# Created by Jobs on 2026年10月24日，星期六.
# Only the current user's ExecuteFile ACE changes; all original DACL bytes are retained as SDDL.

# Reject namespace aliases, directories and reparse ancestors before obtaining the locked file handle.
function Assert-JobsPermissionPath {
    param([string]$Path)
    if (-not [IO.Path]::IsPathRooted($Path) -or $Path.StartsWith('\\') -or $Path -match '[\x00-\x1f]' -or $Path.Substring(2).Contains(':')) { throw '只支持本机无控制字符的普通文件路径，不支持 UNC、设备命名空间或备用数据流。' }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (-not [Jobs.RunPermissionFile]::IsExecutablePath($item.FullName)) { throw '只支持可执行文件或脚本格式，普通文档不提供运行权限操作。' }
    if ($item.PSIsContainer) { throw '运行权限只适用于一个普通文件。' }
    $current = $item
    while ($null -ne $current) {
        if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw '文件及父路径不能经过符号链接、联接或其它重解析点。' }
        if ($current -is [IO.FileInfo]) { $current = $current.Directory } else { $current = $current.Parent }
    }
    $drive = New-Object IO.DriveInfo([IO.Path]::GetPathRoot($item.FullName))
    if ($drive.DriveFormat -cne 'NTFS') { throw '此功能只支持具有 Windows 文件 ACL 的本机 NTFS 卷。' }
    return $item.FullName
}
# Atomically publish one precise per-file permission snapshot.
function Set-JobsPermissionRecord {
    param([string]$Path, [string]$Text)
    $temporary = $Path + '.' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        [IO.File]::WriteAllText($temporary, $Text, (New-Object Text.UTF8Encoding($true)))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary, $Path, [NullString]::Value) }
        else { [IO.File]::Move($temporary, $Path) }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}
# Keep only our own additive ACE; switching direction restores the exact saved base before adding it.
function Get-JobsPermissionReplacement {
    param([string]$Original, [string]$Sid, [bool]$Allow)
    return [Jobs.RunPermissionFile]::Build($Original, $Sid, $Allow)
}
# Execute one ACL transaction against the held file identity.
function Invoke-JobsPermissionChange {
    param($File, [string]$Sid, [ValidateSet('Grant', 'Revoke')][string]$Mode, [string]$RecordPath)
    $before = $File.Capture()
    $original = $before
    $previousText = $null
    if ([IO.File]::Exists($RecordPath)) {
        $previousText = [IO.File]::ReadAllText($RecordPath)
        $record = $previousText | ConvertFrom-Json -ErrorAction Stop
        foreach ($field in @('Version', 'Identity', 'Hash', 'Path', 'Sid', 'OriginalSddl', 'BeforeSddl', 'ExpectedSddl', 'Mode', 'Stage')) {
            if ($null -eq $record.PSObject.Properties[$field]) { throw ('权限记录缺少字段：' + $field) }
        }
        if ($record.Version -ne 1 -or $record.Identity -cne $File.Identity -or -not [string]::Equals($record.Path, $File.Path, [StringComparison]::OrdinalIgnoreCase) -or $record.Sid -cne $Sid -or $record.Mode -cnotin @('Grant', 'Revoke') -or $record.Stage -cnotin @('Prepared', 'Applied')) { throw '文件身份、路径或权限记录已变化；保留现场，请核对备份后人工处理。' }
        if ($before -cne $record.ExpectedSddl -and -not ($record.Stage -ceq 'Prepared' -and $before -ceq $record.BeforeSddl)) { throw 'DACL 已被外部修改，保留当前规则，不覆盖并发变更。' }
        $original = $record.OriginalSddl
        if ($record.Mode -ceq $Mode -and $before -ceq $record.ExpectedSddl) {
            if ($File.HasExecute() -ne ($Mode -ceq 'Grant')) { throw '记录存在但当前有效执行权限不符；未修改。' }
            Write-Host '当前文件已处于所选权限状态，没有重复写入。'
            return
        }
    }
    if ($File.HasExecute() -eq ($Mode -ceq 'Grant')) {
        Write-Host '当前文件已处于所选权限状态，没有重复写入。'
        return
    }
    $expected = Get-JobsPermissionReplacement $original $Sid ($Mode -ceq 'Grant')
    $next = [ordered]@{ Version = 1; Identity = $File.Identity; Hash = $File.Hash; Sid = $Sid; Path = $File.Path; OriginalSddl = $original; BeforeSddl = $before; ExpectedSddl = $expected; Mode = $Mode; Stage = 'Prepared'; Created = [DateTime]::UtcNow.ToString('o') }
    Set-JobsPermissionRecord $RecordPath ($next | ConvertTo-Json -Depth 5)
    $attempted = $false
    try {
        $attempted = $true
        $File.Apply($before, $expected)
        if ($File.HasExecute() -ne ($Mode -ceq 'Grant')) { throw '有效 ExecuteFile 权限未达到预期；可能存在组或继承的拒绝规则，不会删除其它规则。' }
        $next.Stage = 'Applied'
        Set-JobsPermissionRecord $RecordPath ($next | ConvertTo-Json -Depth 5)
    } catch {
        $errorRecord = $_
        if ($attempted) {
            $current = $File.Capture()
            if ($current -ceq $expected) { $File.Apply($expected, $before) }
            elseif ($current -cne $before) { throw ('权限操作失败且当前 DACL 已变化，停止回滚并保留精确备份：' + $RecordPath + '；' + $errorRecord.Exception.Message) }
        }
        if ($null -ne $previousText) { Set-JobsPermissionRecord $RecordPath $previousText }
        elseif ([IO.File]::Exists($RecordPath)) { [IO.File]::Delete($RecordPath) }
        throw $errorRecord
    }
    Write-Host ('已验证当前用户的 ExecuteFile：' + $Mode + '；精确恢复记录：' + $RecordPath)
}
# Both independently installed packages use the same per-user file identity records, not each other's code.
function Invoke-JobsRunPermissionAction {
    param([string]$Target, [ValidateSet('Grant', 'Revoke')][string]$Mode)
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw '运行权限菜单只支持 Windows。' }
    Write-Host ('Jobs ' + $(if ($Mode -ceq 'Grant') { '运行授权' } else { '解除运行授权' })) -ForegroundColor Cyan
    Write-Host ('目标：' + $Target)
    Write-Host '只修改这个普通 NTFS 文件对当前用户的 ExecuteFile ACL；解除会添加精确拒绝执行项，重新授权会撤回本工具拒绝并添加允许项。'
    Write-Host '其它 ACL 和继承设置保持原样；不会执行文件、改 ExecutionPolicy、移除来源标记或修改管理员权限。脚本仍可被有读取权限的解释器读取，此操作不是全面防执行隔离。'
    Write-Host '精确快照保存在当前用户 LOCALAPPDATA/Jobs/WindowsExtension/run-permissions。文件身份或外部 ACL 变化时停止；正常编辑内容后仍可切换；Ctrl+C 取消。'
    Write-Host '输入 YES 执行，任意其它输入取消：' -NoNewline
    $answer = [Console]::ReadLine()
    if ($null -eq $answer -or $answer -cne 'YES') { throw '已取消，没有修改文件权限。' }
    if (-not ('Jobs.RunPermissionFile' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'RunPermissionFile.cs') }
    $path = Assert-JobsPermissionPath $Target
    $file = $null
    $lock = $null
    try {
        $file = New-Object Jobs.RunPermissionFile($path)
        $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $root = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'Jobs/WindowsExtension/run-permissions'
        [void][IO.Directory]::CreateDirectory($root)
        $lock = [IO.File]::Open((Join-Path $root 'permissions.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $recordPath = Join-Path $root ($file.Identity + '-' + $sid + '.json')
        Invoke-JobsPermissionChange $file $sid $Mode $recordPath
    } finally {
        if ($null -ne $lock) { $lock.Dispose() }
        if ($null -ne $file) { $file.Dispose() }
    }
}
