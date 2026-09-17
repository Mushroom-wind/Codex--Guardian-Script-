param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'),
    [switch]$Once
)

$ErrorActionPreference = 'Continue'

$DefaultConfig = [ordered]@{
    processName            = 'ollama'
    executablePath         = 'ollama.exe'
    arguments              = 'serve'
    workingDirectory       = ''
    startHidden            = $true
    checkIntervalSeconds   = 5
    restartDelaySeconds    = 5
    maxRestartsPerHour     = 12
    logFileName            = 'guardian.log'
    logMaxBytes            = 1048576
    logTailLines           = 1000
}

function Get-GuardianConfig {
    $merged = [ordered]@{}
    foreach ($key in $DefaultConfig.Keys) {
        $merged[$key] = $DefaultConfig[$key]
    }

    if (Test-Path -LiteralPath $ConfigPath) {
        try {
            $raw = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($property in $raw.PSObject.Properties) {
                if ($merged.Contains($property.Name)) {
                    $merged[$property.Name] = $property.Value
                }
            }
        } catch {
            Write-Host "Failed to read config.json: $($_.Exception.Message)"
        }
    } else {
        try {
            $merged | ConvertTo-Json -Depth 5 |
                Set-Content -LiteralPath $ConfigPath -Encoding UTF8
        } catch {
            Write-Host "Failed to create config.json: $($_.Exception.Message)"
        }
    }

    return [PSCustomObject]$merged
}

$cfg = Get-GuardianConfig
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogPath = Join-Path $ScriptDir ([string]$cfg.logFileName)

function Write-GuardianLog {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message

    try {
        Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8 -ErrorAction Stop

        if ((Test-Path -LiteralPath $LogPath) -and
            ((Get-Item -LiteralPath $LogPath).Length -gt [int64]$cfg.logMaxBytes)) {
            $tail = Get-Content -LiteralPath $LogPath -Tail ([int]$cfg.logTailLines) -Encoding UTF8
            Set-Content -LiteralPath $LogPath -Value $tail -Encoding UTF8
        }
    } catch {
        # Logging must not stop the watcher.
    }
}

function Get-TargetProcessName {
    $name = [string]$cfg.processName
    if (-not [string]::IsNullOrWhiteSpace($name)) {
        return [System.IO.Path]::GetFileNameWithoutExtension($name.Trim())
    }

    return [System.IO.Path]::GetFileNameWithoutExtension(([string]$cfg.executablePath).Trim())
}

function Get-TargetProcesses {
    $name = Get-TargetProcessName
    if ([string]::IsNullOrWhiteSpace($name)) {
        return @()
    }

    return @(Get-Process -Name $name -ErrorAction SilentlyContinue)
}

function Resolve-TargetExecutable {
    $configuredPath = ([string]$cfg.executablePath).Trim()

    if (-not [string]::IsNullOrWhiteSpace($configuredPath)) {
        if ([System.IO.Path]::IsPathRooted($configuredPath) -and
            (Test-Path -LiteralPath $configuredPath)) {
            return $configuredPath
        }

        $command = Get-Command $configuredPath -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($command -and $command.Source) {
            return [string]$command.Source
        }
    }

    $processName = Get-TargetProcessName
    if (-not [string]::IsNullOrWhiteSpace($processName)) {
        $command = Get-Command "$processName.exe" -ErrorAction SilentlyContinue |
            Select-Object -First 1

        if ($command -and $command.Source) {
            return [string]$command.Source
        }
    }

    return $null
}

function Start-TargetProcess {
    $executable = Resolve-TargetExecutable
    if (-not $executable) {
        Write-GuardianLog "Target executable was not found: $($cfg.executablePath)" 'ERROR'
        return $false
    }

    $startParameters = @{
        FilePath    = $executable
        ErrorAction = 'Stop'
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$cfg.arguments)) {
        $startParameters.ArgumentList = [string]$cfg.arguments
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$cfg.workingDirectory)) {
        $startParameters.WorkingDirectory = [string]$cfg.workingDirectory
    }

    if ([bool]$cfg.startHidden) {
        $startParameters.WindowStyle = 'Hidden'
    }

    try {
        Start-Process @startParameters | Out-Null
        Write-GuardianLog "Started: $executable $($cfg.arguments)"
        return $true
    } catch {
        Write-GuardianLog "Failed to start target process: $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

function Test-RestartBudget {
    param(
        [System.Collections.ArrayList]$History
    )

    $cutoff = (Get-Date).AddHours(-1)

    for ($index = $History.Count - 1; $index -ge 0; $index--) {
        if ([datetime]$History[$index] -lt $cutoff) {
            $History.RemoveAt($index)
        }
    }

    return ($History.Count -lt [int]$cfg.maxRestartsPerHour)
}

if (-not $Once) {
    $mutex = New-Object System.Threading.Mutex($false, 'Local\LocalAI-Guardian')
    $hasHandle = $false

    try {
        $hasHandle = $mutex.WaitOne(0)
    } catch {
        $hasHandle = $false
    }

    if (-not $hasHandle) {
        exit 0
    }
}

$restartHistory = New-Object System.Collections.ArrayList
$lastKnownState = $null

Write-GuardianLog '==== LocalAI Guardian started ===='

while ($true) {
    try {
        $processes = Get-TargetProcesses

        if ($processes.Count -gt 0) {
            if ($lastKnownState -ne 'running') {
                $processIds = ($processes | Select-Object -ExpandProperty Id) -join ', '
                Write-GuardianLog "Target is running. PID: $processIds"
                $lastKnownState = 'running'
            }
        } else {
            $processName = Get-TargetProcessName
            Write-GuardianLog "Target is not running: $processName" 'WARN'
            $lastKnownState = 'stopped'

            if (Test-RestartBudget $restartHistory) {
                if (Start-TargetProcess) {
                    [void]$restartHistory.Add((Get-Date))
                    Start-Sleep -Seconds ([int]$cfg.restartDelaySeconds)
                    $lastKnownState = 'starting'
                }
            } else {
                Write-GuardianLog "Restart limit reached: $($cfg.maxRestartsPerHour) per hour." 'ERROR'
                Start-Sleep -Seconds 60
                continue
            }
        }
    } catch {
        Write-GuardianLog "Guardian loop error: $($_.Exception.Message)" 'ERROR'
    }

    if ($Once) {
        break
    }

    Start-Sleep -Seconds ([int]$cfg.checkIntervalSeconds)
}

Write-GuardianLog '==== LocalAI Guardian stopped ===='
