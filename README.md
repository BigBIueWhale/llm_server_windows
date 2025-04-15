# LLM Server Windows 10/11
Turn a Windows 10/11 PC into an Ollama server that runs on startup (not on user login).

# Ollama Setup & Startup Scripts

This project folder contains two PowerShell scripts used for installing and launching Ollama on Windows 10/11 systems. The scripts are designed to be run side-by-side and perform the following actions:

## Install
1. Download `OllamaSetup.exe` installer for Windows (I used version 0.6.5) and copy to this project root directory.
2. Install Ollama manually on an online PC (or virtual machine).
3. Run `ollama pull qwq:9b` on the online PC.
4. Copy the created `C:/Users/{USERNAME}/.ollama` into this project root directory.
5. Double-click `double_click_install.bat` and agree to admin request. Now Ollama will run on startup.
6. Don't move this project directory anywhere else, because then the startup item will stop working.

## Uninstall
Double-click `double_click_uninstall.bat` (requires admin privileges).

## Operation

- **install.ps1:**  
  - **Admin Check:** Ensures the script is running with Administrator privileges, showing an error message box if not.
  - **Process Termination:** Kills any running instances of `ollama.exe` and `ollama app.exe`.
  - **Installation:** Programmatically runs `OllamaSetup.exe` (showing progress) without requiring extra user interaction.
  - **Post-Installation Process Handling:** Waits for `ollama.exe` to start, then kills it (as well as `ollama app.exe`).
  - **Startup Item Management:** Removes the automatically-created startup shortcut for Ollama.
  - **Scheduled Task Creation:** Creates a scheduled task to run `on_startup.ps1` as SYSTEM on boot (before user login). This task sets its working directory to the project folder.
  - **File Copy with Error Handling:** Copies the `.ollama` folder from the project directory to `C:\WINDOWS\system32\config\systemprofile\.ollama` (overwriting any existing copy). If an error occurs during copy, a message box notifies the user.
  - **User Tracking:** Writes the username (of the account used for installation) to a `.username.txt` file, so that the startup script knows where Ollama was installed.

- **on_startup.ps1:**  
  - **Logging Setup:** Creates a local `logs` folder (inside the project folder) for output logs.
  - **User Context:** Reads the username from `.username.txt` to determine the correct Ollama installation path.
  - **Execution:** Changes directory to `C:\Users\<username>\AppData\Local\Programs\Ollama` and launches `ollama.exe serve`.
  - **Output Redirection:** Pipes the output and error streams to a timestamped log file in the `logs` folder.
  - **Error Logging:** Any error encountered before the main log file is set up is written into a temporary fallback log file at `C:\llm_log.txt`.
  - **Kill-revive loop** For robustness, kills Ollama (attempts to kill gracefully) and relaunches it continuously forever at the configured minute(s) within the hour. Can be configured by editing `$restartMinutes = @(0)`.

## Absolute Paths & Key Directories

- **Project Folder:**  
  This folder contains the following items:
  - `OllamaSetup.exe` – the installer file.
  - `.ollama\` – the source folder to be copied.
  - `install.ps1` – installer script.
  - `on_startup.ps1` – startup script.
  - `.username.txt` – created during installation, used to record the install user.

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
