# Action.psm1 | JobsDiskSpaceInfo
# Created by Jobs on 2026年11月15日，星期日.
Set-StrictMode -Version 2.0
# 清理必须由原生菜单创建独立控制台；通用路径动作不绕过交互门禁。
function Invoke-JobsFeature {
    param([string]$Target, [switch]$Interactive)
    throw '请点击磁盘空间行，在独立终端中选择并确认清理。'
}
Export-ModuleMember -Function Invoke-JobsFeature
