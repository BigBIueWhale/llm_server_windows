# -------------------------------
# SETUP & INITIAL CONFIGURATION
# -------------------------------

# Determine the directory where this script resides.
$scriptDir = $PSScriptRoot

# Create a "logs" folder within this directory if it doesn't exist.
$logDir = Join-Path $scriptDir "logs"
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory | Out-Null
}

# Read the username from .username.txt to determine which user's installation to use.
$usernameFile = Join-Path $scriptDir ".username.txt"
if (-not (Test-Path $usernameFile)) {
    Write-Error ".username.txt file not found in script directory."
    exit 1
}
$username = Get-Content $usernameFile -ErrorAction Stop

# Change the location to the installed Ollama directory.
$ollamaPath = "C:\Users\$username\AppData\Local\Programs\Ollama"
if (-not (Test-Path $ollamaPath)) {
    Write-Error "Ollama installation directory not found: $ollamaPath"
    exit 1
}
Set-Location $ollamaPath

# *******************************
# CONFIGURATION
# *******************************
# This is the array of minutes (0-59) during which the process should be restarted.
$restartMinutes = @(0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48, 50, 52, 54, 56, 58)
# For a single-minute restart schedule (e.g. only at minute 59), you could use:
# $restartMinutes = @(59)

# ------------------------------------
# DEFINE HELPER FUNCTIONALITY
# ------------------------------------

# Add a C# type that exposes GenerateConsoleCtrlEvent, which we need to simulate CTRL+C.
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class ConsoleCtrlHelper {
    public const uint CTRL_C_EVENT = 0;
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool GenerateConsoleCtrlEvent(uint dwCtrlEvent, uint dwProcessGroupId);
}
"@

# Function to send the CTRL+C signal to a given process (assumed to be in its own process group)
function Send-CtrlC {
    param(
        [System.Diagnostics.Process]$Process
    )
    if ($Process -and -not $Process.HasExited) {
        Write-Output "Sending CTRL+C to process group with ID: $($Process.Id)"
        # Note: The second parameter is the process group ID.
        [ConsoleCtrlHelper]::GenerateConsoleCtrlEvent([ConsoleCtrlHelper]::CTRL_C_EVENT, [uint32]$Process.Id) | Out-Null
    }
}

# Function to launch the Ollama process.
# It builds a log file name, builds a command that sets the OLLAMA_HOST variable, and runs the service.
# It returns an object containing both the Process and the log file name.
function Start-Ollama {
    # Create a log file for the new process run based on a timestamp.
    $timestamp = Get-Date -Format "yyyy_MM_dd_HH_mm_ss"
    $logFile = Join-Path $logDir "$timestamp.log"
    
    # Prepare a command that sets OLLAMA_HOST and starts the server, redirecting output to the log file.
    $cmd = 'set OLLAMA_HOST=0.0.0.0 && ollama.exe serve > "' + $logFile + '" 2>&1'
    Write-Output "Launching CMD process at $(Get-Date) with log file: $logFile"
    
    # Create a ProcessStartInfo to run cmd.exe with the desired command.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    # Running with /c will execute the command and then exit.
    $psi.Arguments = "/c $cmd"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    if ($process.Start()) {
        # NOTE: For GenerateConsoleCtrlEvent to target only this process, it must be in its own process group.
        # This script assumes that the new process group ID is the same as the process ID.
        return [PSCustomObject]@{
            Process = $process
            LogFile = $logFile
        }
    }
    else {
        throw "Failed to start process"
    }
}

# -------------------------------
# INITIAL LAUNCH
# -------------------------------
$cmdProcessObj = Start-Ollama

# To prevent repeatedly restarting within the same minute, store the last processed minute.
$lastRestartedMinute = -1

# -------------------------------
# MAIN LOOP
# -------------------------------
while ($true) {
    # Get the current minute (0-59) from local time.
    $currentMinute = (Get-Date).Minute

    # Check if the current minute is in our restart schedule and hasn't been processed yet.
    if ($restartMinutes -contains $currentMinute -and $currentMinute -ne $lastRestartedMinute) {
        Write-Output "[$(Get-Date)] Restart scheduled at minute $currentMinute. Preparing to restart process..."

        try {
            if (-not $cmdProcessObj.Process.HasExited) {
                # Attempt a graceful shutdown: send CTRL+C
                Send-CtrlC -Process $cmdProcessObj.Process

                # Wait until the process exits or up to 30 seconds, checking every second.
                $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                while (-not $cmdProcessObj.Process.HasExited -and $stopwatch.Elapsed.TotalSeconds -lt 30) {
                    Start-Sleep -Seconds 1
                }

                if (-not $cmdProcessObj.Process.HasExited) {
                    Write-Output "Process did not exit gracefully within 30 seconds. Logging timeout error..."
                    # Append timeout error message to the current (most recent) log file.
                    Add-Content -Path $cmdProcessObj.LogFile -Value "$(Get-Date) Timeout error: Process did not exit gracefully after CTRL+C."
                    
                    # Force-kill the process.
                    $cmdProcessObj.Process.Kill()
                    Write-Output "Process killed forcefully after timeout."
                    
                    # Wait an additional 30 seconds before relaunching.
                    Start-Sleep -Seconds 30
                }
                else {
                    Write-Output "Process exited gracefully."
                }
            }
        }
        catch {
            Write-Output "Warning: An error occurred while trying to gracefully terminate the process: $_"
        }

        # Relaunch the process.
        $cmdProcessObj = Start-Ollama

        # Update the last restarted minute to avoid duplicate restarts during the same minute.
        $lastRestartedMinute = $currentMinute
    }

    # Poll every second.
    Start-Sleep -Seconds 1
}
