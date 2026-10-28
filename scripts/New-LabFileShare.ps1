<#
.SYNOPSIS
    Creates a lab file-server folder, applies NTFS permissions, and publishes it as an SMB share.

.DESCRIPTION
    New-LabFileShare.ps1 is the scripted version of Steps 2–5 of BUILD-GUIDE.md.
    It performs three jobs, in order:

      1. Creates the folder (if it does not already exist).
      2. Applies NTFS permissions: it grants the read group ReadAndExecute and
         the modify group Modify. Optionally (with -DisableInheritance) it
         removes permission inheritance so the folder does not pick up broad
         access from its parent - the right choice for restricted folders
         such as HR and Finance.
      3. Creates the SMB share (if it does not already exist) with the same
         groups: Read on the share for the read group, Change for the modify
         group.

    Remember that share permissions and NTFS permissions combine and the
    MORE RESTRICTIVE result wins for the user.

    The script is safe to re-run: it checks before creating the folder and
    the share, and it re-applying the ACL rules is harmless. It does not
    remove any existing permissions other than inherited ones when
    -DisableInheritance is used (it converts inherited entries to explicit
    entries, then inheritance is off going forward).

    Local groups (e.g. FS-Finance-Read) must exist before you run this script.
    Create them first, for example:
        New-LocalGroup -Name "FS-Finance-Read"
        New-LocalGroup -Name "FS-Finance-Modify"

.PARAMETER Path
    Full path of the folder to create and share, e.g. D:\Shares\Finance

.PARAMETER ShareName
    Name of the SMB share users will connect to, e.g. Finance (\\fs01\Finance).

.PARAMETER ReadGroup
    Name of the local group that gets read access (NTFS ReadAndExecute,
    share Read).

.PARAMETER ModifyGroup
    Name of the local group that gets modify access (NTFS Modify,
    share Change).

.PARAMETER DisableInheritance
    Switch. If present, NTFS inheritance is disabled on the folder
    (inherited entries are converted to explicit entries, not deleted).

.EXAMPLE
    .\New-LabFileShare.ps1 -Path "D:\Shares\Finance" -ShareName "Finance" `
        -ReadGroup "FS-Finance-Read" -ModifyGroup "FS-Finance-Modify" -DisableInheritance

    Creates the Finance share with inheritance disabled and group-based ACLs.

.EXAMPLE
    .\New-LabFileShare.ps1 -Path "D:\Shares\Shared" -ShareName "Shared" `
        -ReadGroup "FS-Shared-Read" -ModifyGroup "FS-Shared-Modify"

    Creates the Shared share, leaving NTFS inheritance on (typical for a
    broadly-shared folder).

.NOTES
    Requires: Windows PowerShell 5.1, run as Administrator.
    Requires: The SmbShare module (built into Windows Server 2012+ and
              Windows 8+ Pro) and the local groups to already exist.
    Author:  Homelab File Server project (self-directed learning lab).
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string]$ShareName,

    [Parameter(Mandatory = $true)]
    [string]$ReadGroup,

    [Parameter(Mandatory = $true)]
    [string]$ModifyGroup,

    [Parameter(Mandatory = $false)]
    [switch]$DisableInheritance
)

# --- Safety: groups must exist, otherwise the ACL step would fail halfway ---
foreach ($group in @($ReadGroup, $ModifyGroup)) {
    if (-not (Get-LocalGroup -Name $group -ErrorAction SilentlyContinue)) {
        Write-Warning "Local group '$group' does not exist. Create it first with: New-LocalGroup -Name '$group'"
        return
    }
}

# --- Step 1: create the folder if needed ------------------------------------
if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -Path $Path -ItemType Directory -Force | Out-Null
    Write-Host "Created folder: $Path"
} else {
    Write-Host "Folder already exists: $Path"
}

# --- Step 2: NTFS permissions ----------------------------------------------
$acl = Get-Acl -LiteralPath $Path

if ($DisableInheritance) {
    # $true  = disable inheritance
    # $false = keep (convert) the currently inherited entries as explicit ones
    $acl.SetAccessRuleProtection($true, $false)
    Write-Host "NTFS inheritance disabled on $Path (inherited entries converted to explicit)."
}

# Build the two access rules. ContainerInherit + ObjectInherit make the rule
# flow down to subfolders and files inside this folder.
$inheritFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor `
                [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
$propagation  = [System.Security.AccessControl.PropagationFlags]::None
$allow        = [System.Security.AccessControl.AccessControlType]::Allow

$readRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $ReadGroup,
    [System.Security.AccessControl.FileSystemRights]::ReadAndExecute,
    $inheritFlags, $propagation, $allow)

$modifyRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $ModifyGroup,
    [System.Security.AccessControl.FileSystemRights]::Modify,
    $inheritFlags, $propagation, $allow)

$acl.AddAccessRule($readRule)
$acl.AddAccessRule($modifyRule)
Set-Acl -LiteralPath $Path -AclObject $acl
Write-Host "NTFS rules added: $ReadGroup = ReadAndExecute, $ModifyGroup = Modify"

# --- Step 3: SMB share -------------------------------------------------------
if (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue) {
    Write-Host "SMB share '$ShareName' already exists - leaving it unchanged."
} else {
    New-SmbShare -Name $ShareName -Path $Path `
        -ReadAccess $ReadGroup -ChangeAccess $ModifyGroup | Out-Null
    Write-Host "SMB share created: \\$env:COMPUTERNAME\$ShareName  ->  $Path"
}

Write-Host ""
Write-Host "Verify with:  Get-SmbShare -Name '$ShareName'   and   (Get-Acl '$Path').Access"
