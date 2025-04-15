# Taken from https://gist.github.com/caesay/8424486e0d2565ec2ab7dfb96de5d334

param($ptokill)

# This script sends a signal to the specified process by attaching to the console 
# of the target process and raising Ctrl-Break or Ctrl-C to all processes which
# share that console. It is intended to provide a cleaner way to exit than simply
# killing the process outright, which gives no opportunity to clean up gracefully

$script = '
    [DllImport("kernel32.dll")] static extern bool FreeConsole();
    [DllImport("kernel32.dll")] static extern bool AttachConsole(uint dwProcessId);
    [DllImport("kernel32.dll")] static extern bool GenerateConsoleCtrlEvent(uint dwCtrlEvent, uint dwProcessGroupId);
    [DllImport("kernel32.dll")] static extern uint GetLastError();
    public static uint SendSignal(uint p)
    {
        bool success;
        success = FreeConsole();
        if (!success) return GetLastError();

        success = AttachConsole(p);
        if (!success) return GetLastError();

        success = GenerateConsoleCtrlEvent(1, 0);
        if (!success) return GetLastError();

        return 0;
    }'

Write-Output "Sending signal to $ptokill"
Add-Type -Namespace 'SIGNAL' -Name 'Console' -MemberDefinition $script
exit [SIGNAL.Console]::SendSignal($ptokill)
