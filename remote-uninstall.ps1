[CmdletBinding()]
param(
    [ValidateSet('full', 'app')]
    [string]$Mode,
    [switch]$Yes,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$script:RemoteBaseUrl = if ($env:OPENCLAW_REMOTE_BASE_URL) {
    $env:OPENCLAW_REMOTE_BASE_URL.TrimEnd('/')
} else {
    'https://raw.githubusercontent.com/Enter2O25/uninstall-openclaw/main'
}
$script:TargetScriptName = 'uninstall-openclaw.ps1'
$script:InvokeParams = @{}

if ($PSBoundParameters.ContainsKey('Mode')) {
    $script:InvokeParams.Mode = $Mode
}
if ($Yes.IsPresent) {
    $script:InvokeParams.Yes = $true
}
if ($DryRun.IsPresent) {
    $script:InvokeParams.DryRun = $true
}

# 中文注释：远程入口只负责下载最新主脚本并转发参数，避免 Windows 侧出现双份卸载逻辑。
function Invoke-RemoteUninstall {
    $scriptUrl = "$script:RemoteBaseUrl/$script:TargetScriptName"

    try {
        $scriptContent = (Invoke-WebRequest -UseBasicParsing -Uri $scriptUrl).Content
    } catch {
        throw "下载远程卸载脚本失败：$scriptUrl"
    }

    $scriptBlock = [ScriptBlock]::Create($scriptContent)
    & $scriptBlock @script:InvokeParams
}

Invoke-RemoteUninstall
