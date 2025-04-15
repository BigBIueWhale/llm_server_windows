# Helper function to display an error message and wait for user input before exiting.
function Show-ErrorAndWait {
    param(
        [string]$message,
        [string]$title = "Error"
    )
    # Load Windows.Forms if not already loaded.
    [void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    [System.Windows.Forms.MessageBox]::Show($message, $title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Read-Host -Prompt "Press ENTER to exit"
    exit 1
}

# Helper function to display an informational message and wait for ENTER.
function Show-InfoAndWait {
    param(
        [string]$message,
        [string]$title = "Information"
    )
    [void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    [System.Windows.Forms.MessageBox]::Show($message, $title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Read-Host -Prompt "Press ENTER to exit"
}

# Check for Administrator rights. If not, exit with an error.
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Show-ErrorAndWait "This script must be run as an Administrator." "Insufficient Privileges"
}

# Kill any running instances of "ollama.exe" and "ollama app.exe".
Get-Process -Name "ollama" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process $_.Id -Force }
Get-Process -Name "ollama app" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process $_.Id -Force }

# Remove the scheduled startup task created during installation.
try {
    schtasks.exe /Delete /TN "OllamaOnStartup" /F | Out-Null
} catch {
    Show-ErrorAndWait "Error removing scheduled task 'OllamaOnStartup': $_" "Task Removal Error"
}

# Remove the startup shortcut, if it exists.
$startupFolder = [Environment]::GetFolderPath("Startup")
$ollamaShortcut = Join-Path $startupFolder "Ollama.lnk"
if (Test-Path $ollamaShortcut) {
    try {
        Remove-Item $ollamaShortcut -Force
    } catch {
        Show-ErrorAndWait "Error removing startup shortcut at '$ollamaShortcut'. Error details: $_" "Shortcut Removal Error"
    }
}

# Delete the ".ollama" folder from the system directory.
$destOllama = "C:\WINDOWS\system32\config\systemprofile\.ollama"
if (Test-Path $destOllama) {
    try {
        Remove-Item -LiteralPath $destOllama -Recurse -Force -ErrorAction Stop
    } catch {
        Show-ErrorAndWait "Error removing .ollama folder from '$destOllama'. Error details: $_" "Folder Removal Error"
    }
}

# Retrieve the username of the installing user from ".username.txt".
$usernameFile = Join-Path $PSScriptRoot ".username.txt"
if (Test-Path $usernameFile) {
    try {
        $installedUser = (Get-Content $usernameFile -ErrorAction Stop).Trim()
    } catch {
        Show-ErrorAndWait "Error reading the username from '.username.txt'. Error details: $_" "File Read Error"
    }
} else {
    # Fall back to the current user if the file is missing.
    $installedUser = $env:USERNAME
    Write-Host "Warning: '.username.txt' not found. Defaulting to current user: $installedUser"
}

# Construct the full path to the per-user uninstaller.
$uninstallerPath = "C:\Users\$installedUser\AppData\Local\Programs\Ollama\unins000.exe"
if (-not (Test-Path $uninstallerPath)) {
    Show-ErrorAndWait "Uninstaller not found at '$uninstallerPath'" "Uninstaller Not Found"
}

# Now, run the uninstaller in the context of the installing user.
if ($env:USERNAME -ieq $installedUser) {
    # If the current user is the installing user, run the uninstaller directly.
    Write-Host "Running uninstaller for user '$installedUser'..."
    try {
        Start-Process -FilePath $uninstallerPath -Wait -ErrorAction Stop
    } catch {
        Show-ErrorAndWait "Error running the uninstaller: $_" "Uninstaller Error"
    }
} else {
    # Current user is different from the installing user.
    # Use runas to run the uninstaller as the installing user.
    Write-Host "Current user is '$env:USERNAME', but the installation belongs to '$installedUser'."
    Write-Host "Attempting to run the uninstaller as '$installedUser'."
    # Prepare the command line.
    $commandLine = "`"$uninstallerPath`""
    $runasCommand = "runas.exe /user:$installedUser $commandLine"
    Write-Host "Please enter the password for '$installedUser' when prompted."
    try {
        # Running via cmd so that runas can prompt for credentials.
        cmd.exe /c $runasCommand
    } catch {
        Show-ErrorAndWait "Error running the uninstaller under user '$installedUser': $_" "Uninstaller Error"
    }
}

# Final confirmation to user.
Show-InfoAndWait "Uninstallation completed successfully." "Uninstallation Complete"
