# LLM Server Windows 10/11
Turn a Windows 10/11 PC into an Ollama server that runs on startup (not on user login).

To be used as a reliable endpoint for https://github.com/BigBIueWhale/ollama_load_balancer/

**📚 [Architecture & KV Cache Control API Documentation](./ARCHITECTURE.md)**

# Ollama Setup & Startup Scripts

This project is based on two fundamental scripts.

1. [double_click_install.bat](./double_click_install.bat) to install and configure Ollama, setup firewall rule, and create startup item to run [on_startup.ps1](./on_startup.ps1) on boot - running as SYSTEM user.

2. [on_startup.ps1](./on_startup.ps1) script launches Ollama then reboots ollama on set times based on `$restartHours = @(` variable definition. This is to increase robustness- for example: what happens when Ollama has memory leaks that accumulate over time?

## Install
1. Download `OllamaSetup.exe` installer for Windows (I used version 0.6.7) and copy to this project root directory.
2. Install Ollama manually on an online PC (or virtual machine).
3. Run `ollama pull qwq:32b` (for example) on the online PC.
4. Copy the created `C:/Users/{USERNAME}/.ollama` into this project root directory.
5. Double-click `double_click_install.bat` and agree to admin request. Now Ollama will run on startup.
6. Don't move this project directory anywhere else, because then the startup item will stop working.

## Uninstall
Double-click `double_click_uninstall.bat` (requires admin privileges).

## Update Ollama (Windows 10/11) - ADHD-Friendly Guide

### Understand What You're Updating

**The "product" is THIS PROJECT FOLDER.** It contains the service that manages Ollama.

**This folder must live at:** `C:\Users\{YourUsername}\Documents\llm_server_windows\` (or any permanent path you choose, but NEVER move it after installation)

**What's in this folder:**
- Scripts that run Ollama as a service (`install.ps1`, `on_startup.ps1`, etc.)
- `.ollama/` folder with your downloaded models (~20-60GB)
- `OllamaSetup.exe` (the Ollama installer you download)
- `.username.txt` (created during install, tracks which user installed)

**What gets installed where:**
1. **Ollama app** → `C:\Users\{YourUsername}\AppData\Local\Programs\Ollama\` (installed for the user running the install script)
2. **Models copy** → `C:\WINDOWS\system32\config\systemprofile\.ollama` (copied from `.ollama/` in project folder)
3. **Scheduled task** → Runs `on_startup.ps1` from THIS folder at boot as SYSTEM user, with HARDCODED absolute path (install.ps1:66)

**Admin requirements:**
- **Install/Uninstall:** MUST run as admin (creates scheduled task, modifies system folders, firewall rules)
- **Normal operation:** Runs as SYSTEM automatically (you never touch it)

**Why you CANNOT move this folder after install:** The scheduled task has `cd /d "C:\Users\...\llm_server_windows"` hardcoded (install.ps1:66). Moving folder = service looks for old path = breaks.

### Update Steps (5-10 minutes, server down)

**Goal:** Replace Ollama application in AppData with new version. This folder and models stay intact.

**Steps (DO NOT SKIP OR REORDER):**

**1. Download New Ollama**
- https://ollama.com/download/windows → download `OllamaSetup.exe`
- Save anywhere temporary (Downloads, Desktop)

**2. Uninstall (REQUIRES ADMIN)**
- Go to project folder: `C:\Users\{YourUsername}\Documents\llm_server_windows\`
- Right-click `double_click_uninstall.bat` → "Run as administrator"
- Ollama GUI uninstaller appears → complete it
- Wait for "Uninstallation completed" popup → OK
- **Removes:** Scheduled task (uninstall.ps1:37), firewall rule, system profile models, Ollama from AppData
- **Keeps:** THIS folder (scripts, `.ollama/` models, `.username.txt`)

**3. Replace Installer File**
- In project folder: delete old `OllamaSetup.exe` if it exists
- Copy NEW `OllamaSetup.exe` from Downloads → paste here (next to README.md)
- **Why:** install.ps1:38 runs `OllamaSetup.exe` from project folder. Wrong file = wrong version.

**4. Reinstall (REQUIRES ADMIN)**
- In project folder, right-click `double_click_install.bat` → "Run as administrator"
- Wait 2-5 minutes
- "Installation completed successfully" popup → OK
- **Creates:** New Ollama in AppData, scheduled task pointing to THIS folder, models copy in system profile, firewall rule, `.username.txt`

**5. Reboot & Verify**
- **Reboot Windows** (scheduled task runs at boot only)
- After boot, wait 1 minute
- Browser: http://localhost:11434 → "Ollama is running"
- Command prompt: `ollama --version` → new version

### Critical Rules:
- 🔴 **NEVER move project folder after install** - scheduled task has hardcoded path
- 🔴 **NEVER delete `.ollama/`** - your models, gets copied to system profile
- 🔴 **NEVER delete `.username.txt`** - on_startup.ps1:28 reads it to find Ollama path
- 🔴 **NEVER run install from different folder** - creates conflicting scheduled task

### Troubleshooting:
**Old version still shows?** You didn't delete old `OllamaSetup.exe` before step 4. Uninstall → verify deletion → reinstall.

**Not running after reboot?** Task Scheduler → find `OllamaOnStartup` → check status. Task Manager → `ollama.exe` should run as "SYSTEM". Check `logs/on_startup_*.log`.

**Can I move this folder?** Before install: yes. After install: no (breaks scheduled task). To move: uninstall → move → reinstall.

**Can I delete this folder?** After install: no (scheduled task needs it). After uninstall: yes (but lose models).

## Security
This project is not secure at all, for multiple reasons:

1. [on_startup.ps1](./on_startup.ps1) will run as SYSTEM user- which means Ollama itself will run as admin. This is a workaround for the reality that the PC might not automatically log in- the we want the Ollama server to continue running reliably in the background.

2. [on_startup.ps1](./on_startup.ps1) will possibly exist in a user-accessible folder that a non-admin can edit to contain arbitrary code.

3. The Ollama installation itself it for the current user (because that's how Ollama works), but then it's executed as admin. Normally such programs should be installed as admin globally so that the EXEs and DLLs can't be modified by a non-admin.

4. Firewall rule that's added points to the `ollama.exe` file in the local user folder, which can be replaced (by a non-admin) with a malicious executable which now has access to listen on all interfaces on TCP port 11434.

## Absolute Paths & Key Directories

- **Project Folder:**  
  This folder contains the following items:
  - `OllamaSetup.exe` – the installer file.
  - `.ollama/` – the source folder to be copied.
  - `install.ps1` – installer script.
  - `on_startup.ps1` – startup script.
  - `.username.txt` – created during installation, used to record the install user.
  - `logs/` - created by `on_startup.ps1`, various debug prints of the ollama process, and of the powershell script itself.

- **SYSTEM Profile Folder:**  
  The content of `.ollama\` is copied to the SYSTEM profile at:
  ```
  C:\WINDOWS\system32\config\systemprofile\.ollama
  ```

- **Ollama Installation Directory:**  
  The startup script expects Ollama to be installed under the user’s AppData folder:
  ```
  C:\Users\<username>\AppData\Local\Programs\Ollama
  ```

- **Fallback Error Log:**  
  In `on_startup.ps1`, if any error occurs before the main log file is ready, errors are logged to:
  ```
  C:\llm_log.txt
  ```
