param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json')
)

$ErrorActionPreference = 'Continue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$defaults = [ordered]@{
    processName = 'ollama'
    executablePath = 'ollama.exe'
    logFileName = 'guardian.log'
}

$config = [ordered]@{}
foreach ($key in $defaults.Keys) {
    $config[$key] = $defaults[$key]
}

if (Test-Path -LiteralPath $ConfigPath) {
    try {
        $raw = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in $raw.PSObject.Properties) {
            if ($config.Contains($property.Name)) {
                $config[$property.Name] = $property.Value
            }
        }
    } catch {
        Write-Host "Failed to read config: $($_.Exception.Message)"
    }
}

$processName = [System.IO.Path]::GetFileNameWithoutExtension(
    ([string]$config.processName).Trim()
)

if ([string]::IsNullOrWhiteSpace($processName)) {
    $processName = [System.IO.Path]::GetFileNameWithoutExtension(
        ([string]$config.executablePath).Trim()
    )
}

$processes = @(Get-Process -Name $processName -ErrorAction SilentlyContinue)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$logPath = Join-Path $scriptDir ([string]$config.logFileName)

Write-Host 'LocalAI Guardian Status'
Write-Host '======================='
Write-Host "Target process : $processName"
Write-Host "Running        : $($processes.Count -gt 0)"
Write-Host "Process count  : $($processes.Count)"

if ($processes.Count -gt 0) {
    $processes |
        Select-Object Id, ProcessName, StartTime, Path |
        Format-Table -AutoSize
}

if (Test-Path -LiteralPath $logPath) {
    Write-Host ''
    Write-Host 'Last 20 log lines:'
    Get-Content -LiteralPath $logPath -Tail 20 -Encoding UTF8
}

if ($processes.Count -eq 0) {
    exit 1
}

exit 0
