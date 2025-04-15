function Show-ErrorAndWait {
    param(
        [string]$message,
        [string]$title = "Error"
    )
    # Print error message to console with red text.
    Write-Host "[$title] $message" -ForegroundColor Red
    # Load Windows.Forms if not already loaded.
    [void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    [System.Windows.Forms.MessageBox]::Show($message, $title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    Read-Host -Prompt "Press ENTER to exit"
    exit 1
}

function Show-InfoAndWait {
    param(
        [string]$message,
        [string]$title = "Information"
    )
    # Print informational message to console.
    Write-Host "[$title] $message" -ForegroundColor Green
    # Load Windows.Forms if not already loaded.
    [void][Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    [System.Windows.Forms.MessageBox]::Show($message, $title, [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Read-Host -Prompt "Press ENTER to exit"
}

# Check for Administrator rights. If not, display error and wait.
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Show-ErrorAndWait "This script must be run as an Administrator." "Insufficient Privileges"
}

# Kill any running instances of "ollama.exe" and "ollama app.exe"
Get-Process -Name "ollama" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process $_.Id -Force }
Get-Process -Name "ollama app" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process $_.Id -Force }

# Run the installer (OllamaSetup.exe) as the current user in a detached background process.
$installerPath = Join-Path $PSScriptRoot "OllamaSetup.exe"
if (Test-Path $installerPath) {
    Write-Host "Starting installation in detached mode..."
    Start-Process -FilePath $installerPath
} else {
    Show-ErrorAndWait "Installer not found at $installerPath" "Installer Error"
}

# Wait in a loop for the "ollama.exe" process to appear, then kill it and "ollama app.exe".
while (-not (Get-Process -Name "ollama" -ErrorAction SilentlyContinue)) {
    Start-Sleep -Seconds 1
}
Get-Process -Name "ollama" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process $_.Id -Force }
Get-Process -Name "ollama app" -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process $_.Id -Force }

# Remove the automatically created startup shortcut for Ollama from the user's Startup folder.
$startupFolder = [Environment]::GetFolderPath("Startup")
$ollamaShortcut = Join-Path $startupFolder "Ollama.lnk"
if (Test-Path $ollamaShortcut) {
    Remove-Item $ollamaShortcut -Force
}

# Create a scheduled task to run on_startup.ps1 as SYSTEM at boot (before user logon).
# The task action sets the current directory to the project folder.
$projectPath = $PSScriptRoot
$taskName = "OllamaOnStartup"
# Build the command that the scheduled task will execute by invoking cmd.exe to change to the project folder
# and then running the on_startup.ps1 script.
$action = "cmd.exe /c cd /d `"$projectPath`" && powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$projectPath\on_startup.ps1`""
Write-Host "Creating scheduled task..."
# Execute schtasks.exe and capture output, including error messages.
$taskResult = schtasks.exe /Create /TN $taskName /SC ONSTART /RL HIGHEST /RU "SYSTEM" /TR $action /F 2>&1
# Check the return code and display error if the task creation failed.
if ($LASTEXITCODE -ne 0) {
    Show-ErrorAndWait "Error creating scheduled task. Exit code: $LASTEXITCODE. Output: $taskResult" "Task Creation Error"
}

# Copy the ".ollama" folder to "C:\WINDOWS\system32\config\systemprofile\.ollama"
$sourceOllama = Join-Path $PSScriptRoot ".ollama"
$destOllama = "C:\WINDOWS\system32\config\systemprofile\.ollama"
if (Test-Path $destOllama) {
    try {
        Remove-Item -LiteralPath $destOllama -Recurse -Force -ErrorAction Stop
    } catch {
        Show-ErrorAndWait "Error removing existing .ollama folder at '$destOllama'. Error details: $_" "Removal Error"
    }
}
Write-Host "Copying... $sourceOllama to $destOllama"
try {
    Copy-Item -Path $sourceOllama -Destination $destOllama -Recurse -Force -ErrorAction Stop
    Write-Host "Successfully copied models."
} catch {
    Show-ErrorAndWait "Error copying .ollama folder to '$destOllama'. Error details: $_" "Copy Error"
}

# Write the current username to ".username.txt" for later use by on_startup.ps1.
try {
    $currUser = $env:USERNAME
    Set-Content -Path (Join-Path $PSScriptRoot ".username.txt") -Value $currUser -ErrorAction Stop
} catch {
    Show-ErrorAndWait "Error writing .username.txt. Error details: $_" "File Write Error"
}

# Final confirmation to user
Show-InfoAndWait "Installation completed successfully." "Installation Complete"
