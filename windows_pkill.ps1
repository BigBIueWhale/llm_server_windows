# Taken from https://gist.github.com/caesay/8424486e0d2565ec2ab7dfb96de5d334

param (
    [Parameter(Mandatory = $true)]
    $ptokill,
    [int]$waitTimeout = 30000  # configurable wait timeout in milliseconds; default 30s
)

$scriptpath = $MyInvocation.MyCommand.Path
$dir = Split-Path $scriptpath
Write-host "My directory is $dir"

# check if the process is running. if not, exit. Get-Process throws if the process is not found, although
# since most exceptions are non-terminating, they won't trip a try/catch, so -ErrorAction is specified
try { if ((get-process -Id $ptokill -ErrorAction Stop).HasExited) { exit; } } catch {
    write-host "Process $ptokill does not exist."
    exit;
}

# get list of running processes with WMI
$plist = gwmi win32_process | select -property Name,ProcessId,ParentProcessId
$hash = @{}

function find_children {
    param($procid)
    $children = $plist | where { $_.ParentProcessId -eq $procid }
    foreach($c in $children) {
        find_children $c.ProcessId
        $hash[$c.ProcessId] = $c 
    }
}

# recursively find all children of parent process
find_children $ptokill

# list of all the processes to kill
$tokill = $hash.Keys + @($ptokill)

write-output "Requesting $($tokill.Count) processes to stop"

$tokill | foreach {
    # send a break signal to every process in the list: this needs to be done in a new process
    # because it will send a break signal to all the processes which share the same console
    $plist | where { $_.ProcessId -eq $_ } | foreach { write-host $_.Name }
    start-process -FilePath "powershell" -Wait -NoNewWindow -ArgumentList "`"$dir\windows_signal.ps1`"",$_
}

# we have now sent a signal to all of the processes: will wait for processes in the tree to exit, 
# up until the future time specified below, after which we'll stop waiting.
$waituntil = (get-date).AddSeconds($waitTimeout)

$tokill | foreach {
    $id = $_
    try {
        $p = get-process -ErrorAction Stop -Id $id
        $now = get-date

        # if the process is still running, and timenow < waituntil, lets try and wait for the process to exit
        if ((-not $p.HasExited) -and ($now -lt $waituntil)) {
            $willwait = ($waituntil - $now).TotalMilliseconds
            write-host "Waiting for $id to exit"
            if ($p.WaitForExit($willwait)) {
                write-output "Process $id has exited"
            }
        }

        # use taskkill.exe /F (force) to exit this process more brutally
        if (-not $p.HasExited) {
            write-output "Process $id did not respond to signal in time. Force quitting..."
            start-process -FilePath "taskkill.exe" -Wait -NoNewWindow -ArgumentList "/F","/PID",$id
        }
    }
    catch {
        write-output "Process $id has exited"
    }
}
