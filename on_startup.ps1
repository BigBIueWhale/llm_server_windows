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

# Build a log file name based on the current timestamp.
$timestamp = Get-Date -Format "yyyy_MM_dd_HH_mm_ss"
$logFile = Join-Path $logDir "$timestamp.log"

# Prepare a command that explicitly sets OLLAMA_HOST in the cmd.exe environment,
# then starts the server and redirects all output to a log file.
$cmd = 'set OLLAMA_HOST=0.0.0.0 && ollama.exe serve > "' + $logFile + '" 2>&1'

# Launch "cmd.exe" with our command.
Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $cmd -NoNewWindow
