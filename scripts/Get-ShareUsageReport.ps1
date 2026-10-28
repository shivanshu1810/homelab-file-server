<#
.SYNOPSIS
    Report-only summary of SMB share and volume usage.

.DESCRIPTION
    Get-ShareUsageReport.ps1 answers the two questions behind every
    "the drive is full" ticket:

      1. How much data is in each share? (size used + number of files)
      2. How full is the volume underneath it, and is it over threshold?

    For every SMB share on the local machine (excluding the built-in
    administrative shares such as C$, ADMIN$ and IPC$) the script measures
    the share's folder, counts its files, looks up the volume the path
    lives on, and prints a table. Any volume whose used space is at or
    over -ThresholdPercent is flagged with "*** OVER THRESHOLD ***" so it
    stands out when you paste the output into a ticket.

    This script is REPORT-ONLY. It never deletes, moves, compresses or
    modifies anything. Safe to run on a schedule or during an incident.

.PARAMETER ThresholdPercent
    Volume usage percentage (1-100) at or above which a share row is
    flagged. Default: 80.

.EXAMPLE
    .\Get-ShareUsageReport.ps1
    Lists all shares using the default 80% threshold.

.EXAMPLE
    .\Get-ShareUsageReport.ps1 -ThresholdPercent 90
    Only flags volumes that are 90% full or more.

.NOTES
    Requires: Windows PowerShell 5.1, run as Administrator (to enumerate
    shares reliably). Measuring very large shares can take a while - the
    script walks every file once.
    Author: Homelab File Server project (self-directed learning lab).
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 100)]
    [int]$ThresholdPercent = 80
)

Write-Host ""
Write-Host "Share usage report for $env:COMPUTERNAME - $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
Write-Host "Flag threshold: volumes at or over $ThresholdPercent% full"
Write-Host ""

$results = foreach ($share in (Get-SmbShare | Where-Object { $_.Name -notmatch '\$$' -and $_.Name -ne 'IPC$' })) {

    $path = $share.Path
    $sizeBytes = 0
    $fileCount = 0

    if (Test-Path -LiteralPath $path) {
        $measure = Get-ChildItem -LiteralPath $path -Recurse -File -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum
        if ($null -ne $measure) {
            $sizeBytes = [int64]$measure.Sum
            $fileCount = $measure.Count
        }
    }

    # Work out which volume this share lives on (drive letter of the path).
    $driveLetter = Split-Path -Path $path -Qualifier          # e.g. "D:"
    $volume = $null
    $volUsedPct = $null
    if ($driveLetter) {
        $volume = Get-Volume -DriveLetter $driveLetter.TrimEnd(':') -ErrorAction SilentlyContinue
    }
    if ($volume -and $volume.Size -gt 0) {
        $volUsedPct = [math]::Round((($volume.Size - $volume.SizeRemaining) / $volume.Size) * 100, 1)
    }

    $flag = ''
    if ($null -ne $volUsedPct -and $volUsedPct -ge $ThresholdPercent) {
        $flag = '*** OVER THRESHOLD ***'
    }

    [PSCustomObject]@{
        Share       = $share.Name
        Path        = $path
        'Share GB'  = [math]::Round($sizeBytes / 1GB, 2)
        Files       = $fileCount
        Volume      = $driveLetter
        'Vol Used %' = $volUsedPct
        'Vol Free GB' = if ($volume) { [math]::Round($volume.SizeRemaining / 1GB, 2) } else { $null }
        Flag        = $flag
    }
}

$results | Format-Table -AutoSize

$over = $results | Where-Object { $_.Flag -ne '' }
if ($over) {
    Write-Host "ACTION NEEDED - over threshold ($ThresholdPercent%):" -ForegroundColor Yellow
    foreach ($row in $over) {
        Write-Host ("  {0} ({1}) on volume {2} is {3}% full." -f $row.Share, $row.Path, $row.Volume, $row.'Vol Used %') -ForegroundColor Yellow
    }
    Write-Host "Next steps: identify the largest folders, check quotas (BUILD-GUIDE Step 7)," -ForegroundColor Yellow
    Write-Host "and contact the data owner before deleting anything." -ForegroundColor Yellow
} else {
    Write-Host "All volumes are below the $ThresholdPercent% threshold." -ForegroundColor Green
}
