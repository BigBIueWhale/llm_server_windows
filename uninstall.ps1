# Global error log variable
$ErrorLog = @()

function Log-Error {
    param(
        [string]$Message,
        [string]$Title = "Error"
    )
    Write-Host "[$Title] $Message" -ForegroundColor Red
    # Load Windows.Forms for a pop-up message.
    [void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    # Record the error for a final summary.
    $Global:ErrorLog += "[$Title] $Message"
}

function Log-Info {
    param(
        [string]$Message,
        [string]$Title = "Information"
    )
    Write-Host "[$Title] $Message" -ForegroundColor Green
    # Load Windows.Forms for a pop-up message.
    [void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    [System.Windows.Forms.MessageBox]::Show($Message, $Title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
}

# Check for Administrator rights.
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole] "Administrator")
if (-not $isAdmin) {
    Log-Error "This script is not running as an Administrator. Some operations may fail due to insufficient privileges." "Insufficient Privileges"
}

# Remove the scheduled startup task.
Write-Host "Removing scheduled task 'OllamaOnStartup'..."
schtasks.exe /Delete /TN "OllamaOnStartup" /F | Out-Null
if ($LastExitCode -ne 0) {
    Log-Error "Error removing scheduled task 'OllamaOnStartup'. Exit code: $LastExitCode" "Task Removal Error"
} else {
    Write-Host "Scheduled task removed successfully."
}

# Kill any running instances of "ollama.exe" and "ollama app.exe".
try {
    Get-Process -Name "ollama" -ErrorAction SilentlyContinue | ForEach-Object { 
        Stop-Process $_.Id -Force -ErrorAction Stop 
        Write-Host "Stopped process: $($_.Id)"
    }
    Get-Process -Name "ollama app" -ErrorAction SilentlyContinue | ForEach-Object { 
        Stop-Process $_.Id -Force -ErrorAction Stop 
        Write-Host "Stopped process: $($_.Id)"
    }
} catch {
    Log-Error "Error stopping one or more processes: $_" "Process Termination Error"
}

# Remove the startup shortcut, if it exists.
$startupFolder = [Environment]::GetFolderPath("Startup")
$ollamaShortcut = Join-Path $startupFolder "Ollama.lnk"
if (Test-Path $ollamaShortcut) {
    Write-Host "Removing startup shortcut '$ollamaShortcut'..."
    try {
        Remove-Item $ollamaShortcut -Force -ErrorAction Stop
        if (Test-Path $ollamaShortcut) {
            Log-Error "Startup shortcut at '$ollamaShortcut' still exists after removal attempt." "Shortcut Removal Error"
        } else {
            Write-Host "Startup shortcut removed successfully."
        }
    } catch {
        Log-Error "Error removing startup shortcut at '$ollamaShortcut'. Error details: $_" "Shortcut Removal Error"
    }
} else {
    Write-Host "Startup shortcut '$ollamaShortcut' not found. Skipping removal."
}

# Delete the ".ollama" folder from the system directory.
$destOllama = "C:\WINDOWS\system32\config\systemprofile\.ollama"
if (Test-Path $destOllama) {
    Write-Host "Removing folder '$destOllama'..."
    try {
        Remove-Item -LiteralPath $destOllama -Recurse -Force -ErrorAction Stop
        if (Test-Path $destOllama) {
            Log-Error "Folder '$destOllama' still exists after removal attempt." "Folder Removal Error"
        } else {
            Write-Host "Folder removed successfully."
        }
    } catch {
        Log-Error "Error removing .ollama folder from '$destOllama'. Error details: $_" "Folder Removal Error"
    }
} else {
    Write-Host "Folder '$destOllama' does not exist. Skipping removal."
}

# Retrieve the installing username from ".username.txt".
$usernameFile = Join-Path $PSScriptRoot ".username.txt"
if (Test-Path $usernameFile) {
    try {
        $installedUser = (Get-Content $usernameFile -ErrorAction Stop).Trim()
        Write-Host "Installed user retrieved: $installedUser"
    } catch {
        Log-Error "Error reading the username from '.username.txt'. Error details: $_" "File Read Error"
        $installedUser = $env:USERNAME
        Write-Host "Defaulting to current user: $installedUser"
    }
} else {
    $installedUser = $env:USERNAME
    Write-Host "Warning: '.username.txt' not found. Defaulting to current user: $installedUser"
}

# Construct the full path to the per-user uninstaller.
$uninstallerPath = "C:\Users\$installedUser\AppData\Local\Programs\Ollama\unins000.exe"
if (-not (Test-Path $uninstallerPath)) {
    Log-Error "Uninstaller not found at '$uninstallerPath'" "Uninstaller Not Found"
} else {
    Write-Host "Found uninstaller at '$uninstallerPath'"
    # Run the uninstaller in the context of the installing user.
    if ($env:USERNAME -ieq $installedUser) {
        Write-Host "Running uninstaller for user '$installedUser'..."
        try {
            # Use -PassThru to capture process details, then check the exit code.
            $proc = Start-Process -FilePath $uninstallerPath -Wait -PassThru -ErrorAction Stop
            if ($proc.ExitCode -ne 0) {
                Log-Error "Uninstaller process exited with code $($proc.ExitCode)." "Uninstaller Error"
            } else {
                Write-Host "Uninstaller process completed successfully."
            }
        } catch {
            Log-Error "Error running the uninstaller: $_" "Uninstaller Error"
        }
    } else {
        Write-Host "Current user is '$env:USERNAME', but the installation belongs to '$installedUser'."
        Write-Host "Attempting to run the uninstaller as '$installedUser'."
        $commandLine = "`"$uninstallerPath`""
        $runasCommand = "runas.exe /user:$installedUser $commandLine"
        Write-Host "Please enter the password for '$installedUser' when prompted."
        try {
            cmd.exe /c $runasCommand | Out-Null
            if ($LastExitCode -ne 0) {
                Log-Error "Uninstaller executed under '$installedUser' returned exit code $LastExitCode." "Uninstaller Error"
            } else {
                Write-Host "Uninstaller process ran successfully under '$installedUser'."
            }
        } catch {
            Log-Error "Error running the uninstaller under user '$installedUser': $_" "Uninstaller Error"
        }
    }
}

# Final confirmation to the user.
if ($ErrorLog.Count -gt 0) {
    Log-Info "Uninstallation completed with errors. Please review the error log below:`n$($ErrorLog -join "`n")" "Uninstallation Complete (with Errors)"
} else {
    Log-Info "Uninstallation completed successfully." "Uninstallation Complete"
}
