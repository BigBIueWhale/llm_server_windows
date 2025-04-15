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
# This is the array of minutes (0-59) during which the process should be restarted.
$restartMinutes = @(0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 34, 36, 38, 40, 42, 44, 46, 48, 50, 52, 54, 56, 58)
# For a single-minute restart schedule (e.g. only at minute 59), you could use:
# $restartMinutes = @(59)

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
        Write-Log "Restart scheduled at minute $currentMinute. Preparing to restart process..."

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

        # Update the last restarted minute to avoid duplicate restarts during the same minute.
        $lastRestartedMinute = $currentMinute
    }

    # Poll every second.
    Start-Sleep -Seconds 1
}
