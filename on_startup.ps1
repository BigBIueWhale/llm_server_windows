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

# Create on_startup log file with a unique timestamp.
$onStartupLogFile = Join-Path $logDir ("on_startup_" + (Get-Date -Format "yyyy_MM_dd_HH_mm_ss") + ".log")

# Define a function to log messages instead of printing to the console.
function Write-Log {
    param([string]$msg)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - $msg" | Out-File -FilePath $onStartupLogFile -Append
}

# Log startup message.
Write-Log "Startup script initiated."

# Read the username from .username.txt to determine which user's installation to use.
$usernameFile = Join-Path $scriptDir ".username.txt"
if (-not (Test-Path $usernameFile)) {
    Write-Log "ERROR: .username.txt file not found in script directory."
    exit 1
}
$username = Get-Content $usernameFile -ErrorAction Stop

# Change the location to the installed Ollama directory.
$ollamaPath = "C:\Users\$username\AppData\Local\Programs\Ollama"
if (-not (Test-Path $ollamaPath)) {
    Write-Log "ERROR: Ollama installation directory not found: $ollamaPath"
    exit 1
}
Set-Location $ollamaPath
Write-Log "Changed directory to Ollama installation: $ollamaPath"

# *******************************
# CONFIGURATION
# *******************************
# This is the array of hours (0-23, military time) during which the process should be restarted.
# Example: Restart at midnight, noon, 1 PM, and 11 PM.
# $restartHours = @(0, 12, 13, 23)
# For a single-hour restart schedule (e.g. only at 5 A.M), you could use:
$restartHours = @(5)

# -------------------------------
# FUNCTION TO LAUNCH OLLAMA PROCESS
# -------------------------------
function Start-Ollama {
    # Create a log file for the new process run based on a timestamp.
    $timestamp = Get-Date -Format "yyyy_MM_dd_HH_mm_ss"
    $ollamaLogFile = Join-Path $logDir ("ollama_" + $timestamp + ".log")

    Write-Log "Launching CMD process at $(Get-Date) with ollama log file: $ollamaLogFile"

    # Prepare a command that sets OLLAMA_HOST and starts the server, redirecting output to the ollama log file.
    $cmd = 'set OLLAMA_HOST=0.0.0.0 && ollama.exe serve > "' + $ollamaLogFile + '" 2>&1'

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c $cmd"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $ollamaPath

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    if ($process.Start()) {
        return [PSCustomObject]@{
            Process = $process
            LogFile = $ollamaLogFile
        }
    }
    else {
        Write-Log "ERROR: Failed to start ollama process."
        throw "Failed to start process"
    }
}

# -------------------------------
# INITIAL LAUNCH
# -------------------------------
$cmdProcessObj = Start-Ollama

# Track the last hour we checked. Initialize to -1 to ensure the first check runs.
$lastCheckedHour = -1
# Flag to track if a restart has already happened within the current hour.
$restartedThisHour = $false

# -------------------------------
# MAIN LOOP
# -------------------------------
while ($true) {
    # Get the current hour (0-23) from local time.
    $currentHour = (Get-Date).Hour

    # Reset the restart flag if the hour has changed since the last check.
    if ($currentHour -ne $lastCheckedHour) {
        $restartedThisHour = $false
        $lastCheckedHour = $currentHour
    }

    # Check if the current hour is in our restart schedule AND we haven't already restarted in this specific hour.
    if ($restartHours -contains $currentHour -and $restartedThisHour -eq $false) {
        $restartedThisHour = $true # Set the flag to prevent multiple restarts in the same hour
        Write-Log "Restart triggered at hour $currentHour. Preparing to restart process..."

        # -------------------------------
        # TERMINATE EXISTING PROCESSES USING windows_pkill.ps1
        # -------------------------------
        $killScript = Join-Path $scriptDir "windows_pkill.ps1"
        if (-not (Test-Path $killScript)) {
            Write-Log "Kill script windows_pkill.ps1 not found in $scriptDir. Skipping kill step."
        } else {
            # Kill the CMD process that was started.
            Write-Log "Killing CMD process with PID $($cmdProcessObj.Process.Id) using windows_pkill.ps1"

            $pinfo = New-Object System.Diagnostics.ProcessStartInfo
            $pinfo.FileName = "powershell.exe"
            $pinfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$killScript`" -ptokill $($cmdProcessObj.Process.Id) -waitTimeout 30000"
            $pinfo.RedirectStandardOutput = $true
            $pinfo.RedirectStandardError = $true
            $pinfo.UseShellExecute = $false

            $p = New-Object System.Diagnostics.Process
            $p.StartInfo = $pinfo
            $p.Start() | Out-Null
            $p.WaitForExit()

            $output = $p.StandardOutput.ReadToEnd()
            $output += $p.StandardError.ReadToEnd()
            $output | Out-File $onStartupLogFile -Append

            # Also, kill any lingering ollama.exe processes.
            $ollamaProcs = Get-Process -Name "ollama" -ErrorAction SilentlyContinue
            if ($ollamaProcs) {
                foreach ($proc in $ollamaProcs) {
                    Write-Log "Killing ollama.exe process with PID $($proc.Id) using windows_pkill.ps1"

                    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
                    $pinfo.FileName = "powershell.exe"
                    $pinfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$killScript`" -ptokill $($proc.Id) -waitTimeout 30000"
                    $pinfo.RedirectStandardOutput = $true
                    $pinfo.RedirectStandardError = $true
                    $pinfo.UseShellExecute = $false

                    $p = New-Object System.Diagnostics.Process
                    $p.StartInfo = $pinfo
                    $p.Start() | Out-Null
                    $p.WaitForExit()

                    $output = $p.StandardOutput.ReadToEnd()
                    $output += $p.StandardError.ReadToEnd()
                    $output | Out-File $onStartupLogFile -Append
                }
            } else {
                Write-Log "No ollama.exe processes found to kill."
            }
        }

        # -------------------------------
        # RELAUNCH THE OLLAMA PROCESS
        # -------------------------------
        $cmdProcessObj = Start-Ollama   
    }

    # Poll every second.
    Start-Sleep -Seconds 1
}
