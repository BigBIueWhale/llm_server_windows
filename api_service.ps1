# -------------------------------
# API SERVICE FOR KV CACHE CONTROL
# -------------------------------
# This script provides HTTP endpoints for the load balancer to control KV cache quantization

param(
    [string]$scriptDir,
    [string]$logFile,
    [string]$username
)

function Write-ApiLog {
    param([string]$msg)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - [API] $msg" | Out-File -FilePath $logFile -Append
}

Write-ApiLog "API Service starting on port 11435..."

# Create HTTP listener
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:11435/")

try {
    $listener.Start()
    Write-ApiLog "API Service listening on http://+:11435/"
} catch {
    Write-ApiLog "ERROR: Failed to start HTTP listener. Error: $_"
    exit 1
}

# Main request loop
while ($listener.IsListening) {
    try {
        # GetContext() blocks until request arrives
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        $method = $request.HttpMethod
        $url = $request.RawUrl

        Write-ApiLog "Received $method $url from $($request.RemoteEndPoint)"

        # Route handling
        if ($method -eq "POST" -and $url -eq "/set-kv-cache") {
            # Read JSON body
            $reader = New-Object System.IO.StreamReader($request.InputStream)
            $body = $reader.ReadToEnd()
            $reader.Close()

            Write-ApiLog "Request body: $body"

            try {
                # Parse JSON
                $json = $body | ConvertFrom-Json
                $kvCacheType = $json.type

                # Validate input
                if ($kvCacheType -ne "q8_0" -and $kvCacheType -ne "q16") {
                    $response.StatusCode = 400
                    $responseBody = '{"error": "Invalid type. Must be q8_0 or q16"}'
                    Write-ApiLog "ERROR: Invalid KV cache type: $kvCacheType"
                } else {
                    # Update config file
                    $configFile = Join-Path $scriptDir "kv_cache_config.txt"
                    Set-Content -Path $configFile -Value $kvCacheType -Force
                    Write-ApiLog "Updated config to: $kvCacheType"

                    # Start background job to kill Ollama (non-blocking)
                    $killScript = Join-Path $scriptDir "windows_pkill.ps1"

                    # Find ollama processes to kill
                    $ollamaProcs = Get-Process -Name "ollama" -ErrorAction SilentlyContinue

                    if ($ollamaProcs) {
                        foreach ($proc in $ollamaProcs) {
                            Write-ApiLog "Starting background kill job for PID $($proc.Id)"
                            Start-Job -ScriptBlock {
                                param($killScript, $pid, $logFile)

                                $pinfo = New-Object System.Diagnostics.ProcessStartInfo
                                $pinfo.FileName = "powershell.exe"
                                $pinfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$killScript`" -ptokill $pid -waitTimeout 10000"
                                $pinfo.RedirectStandardOutput = $true
                                $pinfo.RedirectStandardError = $true
                                $pinfo.UseShellExecute = $false

                                $p = New-Object System.Diagnostics.Process
                                $p.StartInfo = $pinfo
                                $p.Start() | Out-Null
                                $p.WaitForExit()

                                $output = $p.StandardOutput.ReadToEnd()
                                $output += $p.StandardError.ReadToEnd()

                                $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                                "$timestamp - [KILL JOB] PID $pid completed. Output: $output" | Out-File -FilePath $logFile -Append
                            } -ArgumentList $killScript, $proc.Id, $logFile | Out-Null
                        }
                        Write-ApiLog "Kill jobs started, Ollama will restart automatically"
                    } else {
                        Write-ApiLog "No Ollama processes found to kill"
                    }

                    # Return 202 Accepted immediately
                    $response.StatusCode = 202
                    $responseBody = "{`"status`": `"accepted`", `"kv_cache_type`": `"$kvCacheType`", `"message`": `"Config updated, Ollama restarting`"}"
                }
            } catch {
                $response.StatusCode = 400
                $responseBody = "{`"error`": `"Invalid JSON: $_`"}"
                Write-ApiLog "ERROR: Failed to parse JSON: $_"
            }

        } elseif ($method -eq "GET" -and $url -eq "/health") {
            # Check if Ollama is running
            $ollamaProcs = Get-Process -Name "ollama" -ErrorAction SilentlyContinue

            if ($ollamaProcs) {
                $response.StatusCode = 200

                # Read current config
                $configFile = Join-Path $scriptDir "kv_cache_config.txt"
                $currentConfig = "unknown"
                if (Test-Path $configFile) {
                    $currentConfig = Get-Content $configFile -Raw
                    $currentConfig = $currentConfig.Trim()
                }

                $responseBody = "{`"status`": `"healthy`", `"ollama_running`": true, `"kv_cache_type`": `"$currentConfig`"}"
            } else {
                $response.StatusCode = 503
                $responseBody = '{"status": "unhealthy", "ollama_running": false}'
            }

        } else {
            # 404 for unknown routes
            $response.StatusCode = 404
            $responseBody = '{"error": "Not found"}'
        }

        # Send response
        $response.ContentType = "application/json"
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($responseBody)
        $response.ContentLength64 = $buffer.Length
        $response.OutputStream.Write($buffer, 0, $buffer.Length)
        $response.Close()

        Write-ApiLog "Response: $($response.StatusCode) - $responseBody"

    } catch {
        Write-ApiLog "ERROR in request loop: $_"
        try {
            $response.StatusCode = 500
            $response.Close()
        } catch {
            # Ignore errors closing response
        }
    }
}

Write-ApiLog "API Service stopped"
