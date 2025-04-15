# LLM Server Windows 10/11
Turn a Windows 10/11 PC into an Ollama server that runs on startup (not on user login).

# Ollama Setup & Startup Scripts

This project folder contains two PowerShell scripts used for installing and launching Ollama on Windows 10/11 systems on startup.

The [on_startup.ps1](./on_startup.ps1) script reboots ollama on set times based on `$restartMinutes = @(` variable definition. This is to increase robustness- for example: what happens when Ollama decides to use the CPU instead of GPU? The reboot makes everything work again.

## Install
1. Download `OllamaSetup.exe` installer for Windows (I used version 0.6.5) and copy to this project root directory.
2. Install Ollama manually on an online PC (or virtual machine).
3. Run `ollama pull qwq:9b` on the online PC.
4. Copy the created `C:/Users/{USERNAME}/.ollama` into this project root directory.
5. Double-click `double_click_install.bat` and agree to admin request. Now Ollama will run on startup.
6. Don't move this project directory anywhere else, because then the startup item will stop working.

## Uninstall
Double-click `double_click_uninstall.bat` (requires admin privileges).

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

## Important Notes

- **Administrator Requirements:**  
  `install.ps1` must be run as an Administrator; otherwise, it will display an error message and exit.

- **Scheduled Task:**  
  The scheduled task created will run as SYSTEM at boot (before any user logs in). Be sure this behavior suits your environment.

- **Error Handling:**  
  Errors in critical operations (like copying folders or launching processes) will cause the scripts to fail. In `install.ps1`, errors produce message boxes to alert the user; in `on_startup.ps1`, errors are logged to `C:\llm_log.txt`.

- **Testing:**  
  It is highly recommended to test these scripts in a controlled environment before deploying them in production.

---
