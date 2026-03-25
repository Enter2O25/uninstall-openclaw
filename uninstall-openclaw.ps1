[CmdletBinding()]
param(
    [ValidateSet('full', 'app')]
    [string]$Mode,
    [switch]$Yes,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$script:Actions = 0
$script:CandidatePaths = New-Object System.Collections.Generic.List[string]
$script:EnvironmentPaths = New-Object System.Collections.Generic.List[string]

$PackageNames = @(
    'openclaw',
    'open-claw',
    'open_claw'
)

$EnvironmentVariableNames = @(
    'OPENCLAW_HOME',
    'OPENCLAW_CONFIG',
    'OPENCLAW_DATA_DIR',
    'OPENCLAW_CACHE_DIR',
    'OPENCLAW_VENV'
)

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Write-WarnLine {
    param([string]$Message)
    Write-Warning $Message
}

function Invoke-Step {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action,
        [Parameter(Mandatory = $true)]
        [string]$Preview
    )

    if ($DryRun) {
        Write-Info "[dry-run] $Preview"
        return
    }

    & $Action
}

# 中文注释：路径统一去重，避免同一路径被反复删除导致日志噪音。
function Add-UniquePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$EnvironmentPath
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    if ($EnvironmentPath) {
        if (-not $script:EnvironmentPaths.Contains($Path)) {
            $null = $script:EnvironmentPaths.Add($Path)
        }
        return
    }

    if (-not $script:CandidatePaths.Contains($Path)) {
        $null = $script:CandidatePaths.Add($Path)
    }
}

function Add-ExistingPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$EnvironmentPath
    )

    if (Test-Path -LiteralPath $Path) {
        Add-UniquePath -Path $Path -EnvironmentPath:$EnvironmentPath
    }
}

# 中文注释：命令路径发现后，只在目录名本身明确指向 OpenClaw 时才继续扩展，避免误删公共目录。
function Discover-CommandPaths {
    $commands = @('openclaw', 'open-claw', 'OpenClaw')

    foreach ($commandName in $commands) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue
        if (-not $command) {
            continue
        }

        Add-ExistingPath -Path $command.Source
        try {
            $commandDirectory = Split-Path -Path $command.Source -Parent
            if ($commandDirectory -and (Split-Path -Path $commandDirectory -Leaf) -match '(?i)open[-_]?claw') {
                Add-UniquePath -Path $commandDirectory
            }
            $parentDirectory = Split-Path -Path $commandDirectory -Parent
            if ($parentDirectory -and (Split-Path -Path $parentDirectory -Leaf) -match '(?i)open[-_]?claw') {
                Add-UniquePath -Path $parentDirectory
            }
        } catch {
            Write-WarnLine "解析命令路径失败：$($command.Source)"
        }
    }
}

function Load-CommonPaths {
    Add-ExistingPath -Path (Join-Path $env:USERPROFILE 'OpenClaw')
    Add-ExistingPath -Path (Join-Path $env:USERPROFILE '.openclaw')
    Add-ExistingPath -Path (Join-Path $env:APPDATA 'OpenClaw')
    Add-ExistingPath -Path (Join-Path $env:LOCALAPPDATA 'OpenClaw')
    Add-ExistingPath -Path (Join-Path $env:LOCALAPPDATA 'openclaw')
    Add-ExistingPath -Path (Join-Path $env:ProgramData 'OpenClaw')
    Add-ExistingPath -Path (Join-Path $env:ProgramFiles 'OpenClaw')
    if (${env:ProgramFiles(x86)}) {
        Add-ExistingPath -Path (Join-Path ${env:ProgramFiles(x86)} 'OpenClaw')
    }
    Add-ExistingPath -Path (Join-Path $env:USERPROFILE 'Desktop\OpenClaw.lnk')
    Add-ExistingPath -Path (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\OpenClaw.lnk')
    Add-ExistingPath -Path (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\OpenClaw.lnk')

    Discover-CommandPaths

    if ($env:OPENCLAW_EXTRA_PATHS) {
        foreach ($extraPath in ($env:OPENCLAW_EXTRA_PATHS -split ';')) {
            if (-not [string]::IsNullOrWhiteSpace($extraPath)) {
                Add-UniquePath -Path $extraPath
            }
        }
    }
}

# 中文注释：环境清理只针对明显属于 OpenClaw 的虚拟环境或专属目录，避免误删用户共享环境。
function Load-EnvironmentPaths {
    Add-ExistingPath -Path (Join-Path $env:USERPROFILE '.virtualenvs\openclaw') -EnvironmentPath
    Add-ExistingPath -Path (Join-Path $env:LOCALAPPDATA 'pipx\venvs\openclaw') -EnvironmentPath
    Add-ExistingPath -Path (Join-Path $env:USERPROFILE 'miniconda3\envs\openclaw') -EnvironmentPath
    Add-ExistingPath -Path (Join-Path $env:USERPROFILE 'anaconda3\envs\openclaw') -EnvironmentPath

    foreach ($installPath in $script:CandidatePaths) {
        if (Test-Path -LiteralPath $installPath -PathType Container) {
            Add-ExistingPath -Path (Join-Path $installPath '.venv') -EnvironmentPath
            Add-ExistingPath -Path (Join-Path $installPath 'venv') -EnvironmentPath
            Add-ExistingPath -Path (Join-Path $installPath 'env') -EnvironmentPath
        }
    }
}

function Select-ModeInteractively {
    Write-Host ""
    Write-Host "请选择卸载模式："
    Write-Host "  1. 全部卸载清理（包括环境）"
    Write-Host "  2. 保留环境，只卸载清理 OpenClaw"
    $choice = Read-Host "请输入选项 [1/2]"

    switch ($choice) {
        '1' { return 'full' }
        '2' { return 'app' }
        default { throw "无效选项：$choice" }
    }
}

function Confirm-Execution {
    param([Parameter(Mandatory = $true)][string]$SelectedMode)

    if ($Yes) {
        return
    }

    $modeLabel = if ($SelectedMode -eq 'full') {
        '全部卸载清理（包括环境）'
    } else {
        '保留环境，只卸载清理 OpenClaw'
    }

    Write-Host ""
    Write-Host "即将执行：$modeLabel"
    $answer = Read-Host '确认继续？[y/N]'
    if ($answer -notin @('y', 'Y', 'yes', 'YES')) {
        throw '用户已取消。'
    }
}

# 中文注释：先停进程和服务，再删文件，减少“文件正在被占用”的失败概率。
function Stop-OpenClawProcesses {
    $processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '(?i)openclaw' -or
        $_.ExecutablePath -match '(?i)openclaw' -or
        $_.CommandLine -match '(?i)openclaw'
    }

    foreach ($process in $processes) {
        Invoke-Step -Preview "Stop-Process -Id $($process.ProcessId) -Force" -Action {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        }
        $script:Actions++
    }
}

function Remove-OpenClawServices {
    $services = Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '(?i)openclaw' -or $_.DisplayName -match '(?i)openclaw'
    }

    foreach ($service in $services) {
        Invoke-Step -Preview "Stop-Service $($service.Name) -Force" -Action {
            Stop-Service -Name $service.Name -Force -ErrorAction SilentlyContinue
        }
        Invoke-Step -Preview "sc.exe delete $($service.Name)" -Action {
            sc.exe delete $service.Name | Out-Null
        }
        $script:Actions++
    }
}

# 中文注释：优先走系统登记的卸载入口，便于正确清理 MSI/安装器创建的项目。
function Invoke-RegistryUninstall {
    $registryKeys = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($registryKey in $registryKeys) {
        $entries = Get-ItemProperty -Path $registryKey -ErrorAction SilentlyContinue | Where-Object {
            $_.DisplayName -match '(?i)openclaw'
        }

        foreach ($entry in $entries) {
            $uninstallString = if ($entry.QuietUninstallString) { $entry.QuietUninstallString } else { $entry.UninstallString }
            if (-not $uninstallString) {
                continue
            }

            if ($uninstallString -match '(?i)msiexec(\.exe)?\s+/I') {
                $uninstallString = $uninstallString -replace '(?i)/I', '/X'
                if ($uninstallString -notmatch '(?i)/q') {
                    $uninstallString += ' /qn'
                }
            } elseif ($uninstallString -match '(?i)unins.*\.exe' -and $uninstallString -notmatch '(?i)\s/S(\s|$)') {
                $uninstallString += ' /S'
            }

            Invoke-Step -Preview "cmd.exe /c $uninstallString" -Action {
                Start-Process -FilePath 'cmd.exe' -ArgumentList '/c', $uninstallString -Wait -NoNewWindow
            }
            $script:Actions++
        }
    }
}

function Remove-UserPackages {
    foreach ($package in $PackageNames) {
        if (Get-Command npm -ErrorAction SilentlyContinue) {
            $npmOutput = & npm list -g --depth=0 $package 2>$null
            if ($LASTEXITCODE -eq 0 -and $npmOutput) {
                Invoke-Step -Preview "npm uninstall -g $package" -Action {
                    & npm uninstall -g $package
                }
                $script:Actions++
            }
        }

        if (Get-Command pipx -ErrorAction SilentlyContinue) {
            $pipxOutput = & pipx list 2>$null
            if ($pipxOutput -match "(?im)(^|\s)$([regex]::Escape($package))(\s|$)") {
                Invoke-Step -Preview "pipx uninstall $package" -Action {
                    & pipx uninstall $package
                }
                $script:Actions++
            }
        }
    }
}

function Remove-CondaEnvironment {
    if ($Mode -ne 'full') {
        return
    }

    if (-not (Get-Command conda -ErrorAction SilentlyContinue)) {
        return
    }

    $condaEnvList = & conda env list 2>$null
    if ($condaEnvList -match '(?im)(^|\s)openclaw(\s|$)') {
        Invoke-Step -Preview "conda env remove -n openclaw -y" -Action {
            & conda env remove -n openclaw -y
        }
        $script:Actions++
    }
}

# 中文注释：显式拦住盘符根目录等危险位置，避免路径识别异常时误删大范围目录。
function Remove-PathSafely {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    $dangerousPaths = @(
        [System.IO.Path]::GetPathRoot($Path),
        $env:USERPROFILE,
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:ProgramData,
        $env:windir,
        (Join-Path $env:windir 'System32')
    ) | Where-Object { $_ }

    if ($dangerousPaths -contains $Path) {
        Write-WarnLine "已跳过危险路径：$Path"
        return
    }

    Invoke-Step -Preview "Remove-Item -LiteralPath '$Path' -Recurse -Force" -Action {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
    }
    $script:Actions++
}

function Remove-CandidatePaths {
    foreach ($path in $script:CandidatePaths) {
        Remove-PathSafely -Path $path
    }
}

function Remove-EnvironmentPaths {
    foreach ($path in $script:EnvironmentPaths) {
        Remove-PathSafely -Path $path
    }
}

# 中文注释：注册表环境变量和 PATH 都需要同步清理，才能让“包括环境”真正落地。
function Remove-EnvironmentVariables {
    foreach ($scope in @('User', 'Machine')) {
        foreach ($variableName in $EnvironmentVariableNames) {
            $currentValue = [Environment]::GetEnvironmentVariable($variableName, $scope)
            if ([string]::IsNullOrWhiteSpace($currentValue)) {
                continue
            }

            try {
                Invoke-Step -Preview "清理 $scope 级环境变量 $variableName" -Action {
                    [Environment]::SetEnvironmentVariable($variableName, $null, $scope)
                }
                $script:Actions++
            } catch {
                Write-WarnLine "清理 $scope 级环境变量失败：$variableName"
            }
        }
    }
}

function Remove-PathEntriesContainingOpenClaw {
    foreach ($scope in @('User', 'Machine')) {
        $pathValue = [Environment]::GetEnvironmentVariable('Path', $scope)
        if ([string]::IsNullOrWhiteSpace($pathValue)) {
            continue
        }

        $filteredSegments = $pathValue -split ';' | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and $_ -notmatch '(?i)openclaw'
        }
        $newPathValue = ($filteredSegments -join ';')

        if ($newPathValue -eq $pathValue) {
            continue
        }

        try {
            Invoke-Step -Preview "清理 $scope 级 PATH 中的 OpenClaw 条目" -Action {
                [Environment]::SetEnvironmentVariable('Path', $newPathValue, $scope)
            }
            $script:Actions++
        } catch {
            Write-WarnLine "清理 $scope 级 PATH 失败。"
        }
    }
}

function Show-Summary {
    Write-Host ""
    Write-Host "清理完成。"
    if ($Mode -eq 'full') {
        Write-Host "模式：全部卸载清理（包括环境）"
    } else {
        Write-Host "模式：保留环境，只卸载清理 OpenClaw"
    }
    Write-Host "执行动作数：$script:Actions"
    Write-Host ""
    Write-Host "如果 OpenClaw 安装在自定义目录，可先设置 OPENCLAW_EXTRA_PATHS 后重跑。"
}

if (-not $Mode) {
    $Mode = Select-ModeInteractively
}

Load-CommonPaths
if ($Mode -eq 'full') {
    Load-EnvironmentPaths
}

Confirm-Execution -SelectedMode $Mode

Stop-OpenClawProcesses
Remove-OpenClawServices
Invoke-RegistryUninstall
Remove-UserPackages
Remove-CondaEnvironment
Remove-CandidatePaths

if ($Mode -eq 'full') {
    Remove-EnvironmentPaths
    Remove-EnvironmentVariables
    Remove-PathEntriesContainingOpenClaw
}

Show-Summary
