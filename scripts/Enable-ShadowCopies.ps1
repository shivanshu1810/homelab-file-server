<#
.SYNOPSIS
    Enables and configures Volume Shadow Copy (VSS) shadow copies for a volume.

.DESCRIPTION
    Enable-ShadowCopies.ps1 does the three things vssadmin can do from the
    command line, and then shows you the result:

      1. Creates shadow-copy storage on the volume (if none exists yet),
         with a maximum size limit so snapshots cannot eat the whole disk.
      2. Creates one shadow copy immediately, so "Previous Versions" has
         something to show right away.
      3. Prints the current state: shadow storage associations and the
         list of existing shadow copies.

    WHAT THIS SCRIPT DOES NOT DO - SCHEDULING:
    vssadmin cannot create a recurring schedule. On Windows Server, the
    schedule is normally set in the volume's Properties -> Shadow Copies
    tab -> Settings -> Schedule (see BUILD-GUIDE.md Step 8). On any
    edition of Windows you can achieve the same result with Task
    Scheduler:

      1. Open Task Scheduler (taskschd.msc) -> Create Task.
      2. Name it e.g. "VSS Snapshot D 07:00".
      3. Trigger: Daily, 07:00 (create a second task for 12:00 if you
         want the classic twice-a-day pattern).
      4. Action: Start a program:
             Program:   vssadmin
             Arguments: Create Shadow /For=D:
      5. Settings: run with highest privileges, run whether user is
         logged on or not (SYSTEM account works).

    CONSERVATIVE BY DESIGN: this script never deletes shadow copies,
    never resizes existing storage DOWN, and never touches a volume other
    than the one you name. If shadow storage already exists it is left
    exactly as it is and the script just reports it.

.PARAMETER Volume
    The volume to enable shadow copies on, with or without the colon,
    e.g. "D" or "D:". Default: D

.PARAMETER MaxSizeMB
    Maximum disk space (in megabytes) shadow copies may use on the
    volume. Default: 2048 (2 GB) - plenty for a lab. Real servers often
    use 10-20% of the volume.

.EXAMPLE
    .\Enable-ShadowCopies.ps1
    Enables shadow copies on D: with a 2 GB storage limit and takes one
    snapshot immediately.

.EXAMPLE
    .\Enable-ShadowCopies.ps1 -Volume E -MaxSizeMB 5120
    Same, for the E: volume with a 5 GB limit.

.NOTES
    Requires: Windows PowerShell 5.1, run as Administrator.
    Uses the built-in vssadmin.exe tool. No files are modified other than
    VSS's own shadow storage on the target volume.
    Author: Homelab File Server project (self-directed learning lab).
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string]$Volume = 'D',

    [Parameter(Mandatory = $false)]
    [ValidateRange(300, 1048576)]
    [int]$MaxSizeMB = 2048
)

# Normalise the volume to the "D:" form vssadmin expects.
$vol = $Volume.TrimEnd(':').ToUpper() + ':'

if (-not (Test-Path -LiteralPath "$vol\")) {
    Write-Warning "Volume $vol does not appear to exist on this machine. Nothing was changed."
    return
}

Write-Host ""
Write-Host "Configuring shadow copies for volume $vol (max size $MaxSizeMB MB)..."

# --- Check the VSS service is not disabled ---------------------------------
$vss = Get-Service -Name VSS -ErrorAction SilentlyContinue
if ($vss -and $vss.StartType -eq 'Disabled') {
    Write-Warning "The Volume Shadow Copy service is set to Disabled. Set it to Manual (its normal state) and re-run this script."
    return
}
Write-Host "VSS service start type: $($vss.StartType) (Manual is normal - Windows starts it on demand)."

# --- Step 1: create shadow storage if none exists ---------------------------
$existingStorage = & vssadmin List ShadowStorage 2>$null | Out-String
if ($existingStorage -match "For volume: \($vol\)") {
    Write-Host "Shadow storage already exists for $vol - leaving its settings unchanged."
} else {
    Write-Host "Creating shadow storage on $vol (max $MaxSizeMB MB)..."
    & vssadmin Add ShadowStorage /For=$vol /On=$vol /MaxSize="$($MaxSizeMB)MB"
}

# --- Step 2: take one snapshot now ------------------------------------------
Write-Host "Creating an initial shadow copy of $vol..."
& vssadmin Create Shadow /For=$vol

# --- Step 3: report the resulting state --------------------------------------
Write-Host ""
Write-Host "=== Shadow storage ==="
& vssadmin List ShadowStorage

Write-Host ""
Write-Host "=== Shadow copies on $vol ==="
& vssadmin List Shadows /For=$vol

Write-Host ""
Write-Host "Reminder: vssadmin does not set a recurring schedule."
Write-Host "Set one via the volume Properties -> Shadow Copies -> Settings -> Schedule,"
Write-Host "or with Task Scheduler running:  vssadmin Create Shadow /For=$vol"
Write-Host "See BUILD-GUIDE.md Step 8 for the walkthrough."
