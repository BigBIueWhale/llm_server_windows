# LLM Server Architecture - KV Cache Control System

## Ports
- **11434**: Ollama inference API (default Ollama port)
- **11435**: KV Cache Control API (for load balancer)

## Process Architecture

```
Task Scheduler (SYSTEM, starts at boot)
  └─> on_startup.ps1 [PERSISTENT SERVICE]
      ├─> api_service.ps1 (Background Job) [Port 11435]
      └─> cmd.exe → ollama.exe [Port 11434]
```

## Operation Cycle

### 1. Installation Phase (`install.ps1`)
1. Kills existing Ollama instances
2. Runs `OllamaSetup.exe` → installs to `C:\Users\{user}\AppData\Local\Programs\Ollama`
3. Kills Ollama started by installer
4. Removes auto-created startup shortcut
5. Creates scheduled task `OllamaOnStartup` (runs as SYSTEM at boot)
6. Copies `.ollama` models to `C:\WINDOWS\system32\config\systemprofile\.ollama`
7. Saves username to `.username.txt`
8. Creates firewall rule for port 11434

### 2. Runtime Phase (`on_startup.ps1`)
**Triggers:** System boot (via scheduled task)

**Initialization:**
1. Creates log directory and timestamped log file
2. Reads username from `.username.txt`
3. Changes to Ollama installation directory
4. Launches Ollama via `Start-Ollama` function
5. Starts `api_service.ps1` as background job

**Main Loop (polls every 1 second):**
1. **Health Check**: Detects if Ollama process died → auto-restart with current config
2. **Scheduled Restart**: At configured hours (default: 5 AM), gracefully kills and restarts Ollama

### 3. Start-Ollama Function
1. Reads `kv_cache_config.txt` (q8_0 or q16)
2. Creates timestamped log file for Ollama output
3. Launches cmd.exe with environment variables:
   - `OLLAMA_HOST=0.0.0.0` (bind all interfaces)
   - `OLLAMA_KEEP_ALIVE=-1` (keep model loaded indefinitely)
   - `OLLAMA_FLASH_ATTENTION=1` (enable flash attention)
   - `OLLAMA_KV_CACHE_TYPE={config}` (q8_0 or q16)
   - `OLLAMA_NUM_PARALLEL=1` (single request at a time)
4. Returns process object for health monitoring

### 4. API Service (`api_service.ps1`)
**Runs:** Background job started by on_startup.ps1
**Port:** 11435
**Protocol:** HTTP

#### Endpoints:

**POST /set-kv-cache**
- **Body:** `{"type": "q8_0"}` or `{"type": "q16"}`
- **Action:**
  1. Validates type (must be q8_0 or q16)
  2. Writes to `kv_cache_config.txt`
  3. Starts background job to kill Ollama via `windows_pkill.ps1` (10s timeout)
  4. Returns `202 Accepted` immediately (non-blocking)
- **Response Time:** < 100ms
- **Restart Time:** 5-15s total (kill: 3-10s, detect+restart: 1-2s, init: 1-3s)

**GET /health**
- **Response 200:** `{"status": "healthy", "ollama_running": true, "kv_cache_type": "q8_0"}`
- **Response 503:** `{"status": "unhealthy", "ollama_running": false}`

### 5. Graceful Termination (`windows_pkill.ps1`)
**Process:**
1. Recursively finds all child processes via WMI
2. Sends Ctrl-Break signal to each process (via `windows_signal.ps1`)
3. Waits up to 10s for graceful shutdown
4. Force kills with `taskkill /F` if still alive

**Timing:**
- Signal phase: 1-2s
- Graceful shutdown: 2-5s (typical)
- Force kill: Immediate (if timeout exceeded)
- **Total: 3-10s**

## Configuration Files

### kv_cache_config.txt
- **Location:** Project root
- **Content:** Single line: `q8_0` or `q16`
- **Default:** `q8_0`
- **Effect:** Read on each Ollama start, controls `OLLAMA_KV_CACHE_TYPE`

### .username.txt
- **Location:** Project root
- **Content:** Windows username of installer
- **Purpose:** Locate Ollama installation path at runtime

## Load Balancer Integration

### Switching KV Cache Type
```bash
# Switch to q16 (higher precision, more VRAM)
curl -X POST http://{pc-ip}:11435/set-kv-cache \
  -H "Content-Type: application/json" \
  -d '{"type": "q16"}'

# Response: 202 Accepted (immediate)
# Ollama restarts within 5-15 seconds
```

### Health Check
```bash
curl http://{pc-ip}:11435/health

# Response 200: Ollama is running
# Response 503: Ollama is down/restarting
```

### Recommended Flow
1. Send POST /set-kv-cache to node
2. Poll GET /health until returns 200
3. Verify `kv_cache_type` matches requested value
4. Route traffic to node

## Restart Scenarios

| Trigger | Kill Method | Restart By | Config Read | Downtime |
|---------|------------|------------|-------------|----------|
| API request | `windows_pkill.ps1` (bg job) | Health check loop | Yes (new config) | 5-15s |
| Scheduled (5 AM) | `windows_pkill.ps1` (blocking) | Explicit relaunch | Yes (current config) | 5-15s |
| Crash/unexpected | N/A | Health check loop | Yes (current config) | 1-5s |

## Logs
- **Location:** `logs/` directory (created at runtime)
- **on_startup_{timestamp}.log**: Main service log, includes API events
- **ollama_{timestamp}.log**: Ollama stdout/stderr per launch
- **Retention:** Manual cleanup (no auto-rotation)

## Security Notes
- Runs as SYSTEM account (full privileges)
- HTTP API has no authentication (internal network only)
- Port 11434 firewall rule auto-created (public+private networks)
- Port 11435 requires manual firewall rule if needed

## KV Cache Quantization

### q8_0 (8-bit quantization)
- **VRAM Usage:** ~50% of q16
- **Speed:** Faster inference
- **Quality:** Minimal degradation for most tasks
- **Use Case:** Default, high throughput

### q16 (16-bit, no quantization)
- **VRAM Usage:** 2x q8_0
- **Speed:** Slower inference
- **Quality:** Full precision
- **Use Case:** Tasks requiring maximum accuracy

### Runtime Switching
- No model reload required (only KV cache affected)
- Context cleared on restart
- Switching triggers full Ollama restart
