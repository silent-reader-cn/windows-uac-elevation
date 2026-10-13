<#
.SYNOPSIS
    Run one command elevated via UAC, then print its output.

.DESCRIPTION
    An elevated process does not inherit this session's stdout/stderr, so the
    output is redirected to a log file and read back afterwards.

    IMPORTANT: this script's own exit code reflects Start-Process only, NOT the
    inner command. Always judge success by the printed log.

    Paths inside -Command must be NATIVE Windows paths (C:\... or C:/...).
    Folder paths are not translated by MSYS here.

.PARAMETER Command
    The command line to run elevated. Accepts a single string.

.PARAMETER LogPath
    Where the elevated process writes its output. Defaults to
    %TEMP%\uac-elevation.log

.PARAMETER KeepLog
    Do not delete an existing log file before running.

.EXAMPLE
    .\Elevate-Command.ps1 -Command "C:\ProgramData\chocolatey\bin\nssm.exe restart ComfyUI"

.EXAMPLE
    .\Elevate-Command.ps1 "sc.exe query ComfyUI" -LogPath "C:\tmp\svc.log"

.NOTES
    Complex quoting: if the inner command itself contains double quotes, wrap
    the whole thing in a small .cmd file and elevate that file instead.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Command,

    [string]$LogPath = (Join-Path $env:TEMP 'uac-elevation.log'),

    [switch]$KeepLog
)

$ErrorActionPreference = 'Stop'

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (Test-IsAdmin) {
    Write-Host '[!] Already elevated - running the command directly.' -ForegroundColor Yellow
    & cmd.exe /c $Command
    exit $LASTEXITCODE
}

if (-not $KeepLog -and (Test-Path -LiteralPath $LogPath)) {
    Remove-Item -LiteralPath $LogPath -Force
}

# cmd /c keeps redirection semantics predictable, and survives UAC elevation.
$inner = '/c "' + $Command + ' > "' + $LogPath + '" 2>&1"'

Write-Host "[*] Elevating (UAC may prompt): $Command" -ForegroundColor Cyan
try {
    Start-Process -FilePath 'cmd.exe' -ArgumentList $inner -Verb RunAs -Wait
}
catch {
    Write-Error "Elevation failed or was cancelled by the user: $($_.Exception.Message)"
    exit 3
}

Write-Host '--- output of the elevated command -------------------------------------'
if (Test-Path -LiteralPath $LogPath) {
    Get-Content -LiteralPath $LogPath
    Write-Host '------------------------------------------------------------------------'
    Write-Host "[i] Log: $LogPath"
}
else {
    Write-Host '------------------------------------------------------------------------'
    Write-Warning "No log was produced at $LogPath - check that -Command used native Windows paths."
    exit 2
}

Write-Host '[i] Reminder: this script''s exit code reflects Start-Process only.' -ForegroundColor DarkGray
exit 0
