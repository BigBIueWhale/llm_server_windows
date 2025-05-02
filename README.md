# LLM Server Windows 10/11
Turn a Windows 10/11 PC into an Ollama server that runs on startup (not on user login).

To be used as a reliable endpoint for https://github.com/BigBIueWhale/ollama_load_balancer/

# Ollama Setup & Startup Scripts

This project is based on two fundamental scripts.

1. [double_click_install.bat](./double_click_install.bat) to install and configure Ollama, setup firewall rule, and create startup item to run [on_startup.ps1](./on_startup.ps1) on boot - running as SYSTEM user.

2. [on_startup.ps1](./on_startup.ps1) script launches Ollama then reboots ollama on set times based on `$restartMinutes = @(` variable definition. This is to increase robustness- for example: what happens when Ollama decides to use the CPU instead of GPU? The reboot makes everything work again.

## Install
1. Download `OllamaSetup.exe` installer for Windows (I used version 0.6.7) and copy to this project root directory.
2. Install Ollama manually on an online PC (or virtual machine).
3. Run `ollama pull qwq:32b` (for example) on the online PC.
4. Copy the created `C:/Users/{USERNAME}/.ollama` into this project root directory.
5. Double-click `double_click_install.bat` and agree to admin request. Now Ollama will run on startup.
6. Don't move this project directory anywhere else, because then the startup item will stop working.

## Uninstall
Double-click `double_click_uninstall.bat` (requires admin privileges).

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
