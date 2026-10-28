# Build Guide — Windows File Server & Storage Lab

Follow this guide top to bottom on your lab machine. Each step ends with a **✅ Checkpoint** so you can confirm it worked before moving on. If a checkpoint fails, stop and fix it there — file server problems compound (permissions on top of shares on top of snapshots).

**Assumptions**

- Your server is named (or you will rename it to) `fs01` — the examples use `fs01.lab.local` / `\\fs01\...`. Use whatever name your machine has; just substitute it everywhere.
- You are signed in as a local administrator.
- The data volume will be `D:`. If your second disk got a different letter, substitute it.
- Server path shown first (Windows Server 2022). Where Windows 10/11 Pro differs, the difference is called out honestly — mainly the quota step.

---

## Step 0 — Prepare the machine

1. Install Windows Server 2022 Evaluation (Desktop Experience) or Windows 10/11 Pro in a VM or on a spare PC.
2. Rename the computer to `fs01`:
   - Settings → System → About → Rename this PC → `fs01` → restart.
   - Or in PowerShell: `Rename-Computer -NewName "fs01" -Restart`
3. Set a static IP if you can (e.g. `192.168.1.50`). This makes `\\fs01\...` and name resolution boring and reliable, like a real office.

**✅ Checkpoint:** After restart, run `hostname` in a command prompt — it prints `fs01`.

---

## Step 1 — Prepare the data volume

You want shared data on its own volume, not on `C:`.

1. Attach a second virtual disk (10–20 GB) to the VM, or create a partition from free space on the physical disk.
2. Open **Disk Management** (`diskmgmt.msc`).
3. Initialise the new disk (GPT is fine), create a **New Simple Volume**, format it **NTFS**, assign letter **D:**, label it **DATA**.
   - NTFS is required — NTFS permissions and quotas do not exist on FAT32/exFAT.

**✅ Checkpoint:** `D:` appears in File Explorer, its file system shows **NTFS** (right-click → Properties), and you can create and delete a test file on it.

---

## Step 2 — Create the folder structure

In File Explorer or PowerShell, create:

```
D:\Shares
D:\Shares\HR
D:\Shares\Finance
D:\Shares\Shared
```

PowerShell version:

```powershell
New-Item -Path "D:\Shares\HR","D:\Shares\Finance","D:\Shares\Shared" -ItemType Directory -Force
```

**✅ Checkpoint:** All three folders exist under `D:\Shares`.

---

## Step 3 — Create the local security groups

Least privilege starts here. We grant access to **groups**, never to individual users.

Open **Computer Management** (`compmgmt.msc`) → Local Users and Groups → Groups, and create:

| Group | Purpose |
|---|---|
| `FS-HR-Read` | Can open and read files in HR |
| `FS-HR-Modify` | Can read, add, edit and delete files in HR |
| `FS-Finance-Read` | Read-only access to Finance |
| `FS-Finance-Modify` | Modify access to Finance |
| `FS-Shared-Read` | Read-only access to Shared |
| `FS-Shared-Modify` | Modify access to Shared |

PowerShell version:

```powershell
"FS-HR-Read","FS-HR-Modify","FS-Finance-Read","FS-Finance-Modify","FS-Shared-Read","FS-Shared-Modify" |
    ForEach-Object { New-LocalGroup -Name $_ -Description "File server lab access group" }
```

Then create two test users so you can prove permissions work (in real life these would be the employees):

- `lab.hr` — add to `FS-HR-Modify`
- `lab.fin` — add to `FS-Finance-Modify` and `FS-Shared-Modify`

Give both a password you'll remember (lab only). Adding a user to a group:

```powershell
Add-LocalGroupMember -Group "FS-HR-Modify" -Member "lab.hr"
```

**✅ Checkpoint:** In Computer Management, open `FS-HR-Modify` — `lab.hr` is listed as a member. (Group membership only takes effect at next sign-in — remember this, it explains half of all "access denied" tickets.)

---

## Step 4 — Set NTFS permissions (the part that actually protects the files)

How inheritance works here: new folders inherit permissions from their parent. `D:\Shares` inherits from the `D:` root. That's fine for the parent, but `HR` and `Finance` must **not** be readable by everyone just because the drive is — so on those two folders we **disable inheritance** and set explicit permissions. On `Shared`, inheritance can stay **on**, and we just add our groups.

### 4a. Finance (do this one first, it's the pattern)

1. Right-click `D:\Shares\Finance` → Properties → **Security** tab → **Advanced**.
2. Click **Disable inheritance** → choose **"Convert inherited permissions into explicit permissions on this object."** (Convert, don't remove — safer; you can then delete what you don't want.)
3. Back on the Security tab, **Edit** and **Remove** any broad entries you don't want (for example `Users` read access) — keep `SYSTEM` and `Administrators` at Full Control. Removing `SYSTEM`/Administrators will cause you pain later; don't.
4. **Add** `FS-Finance-Read` → allow **Read & execute, List folder contents, Read** (tick "Read & execute" and the rest follow).
5. **Add** `FS-Finance-Modify` → allow **Modify**.
6. OK your way out.

Repeat the same pattern for `HR` with the HR groups.

For `Shared`: leave inheritance ON, and simply **Add** `FS-Shared-Read` (Read & execute) and `FS-Shared-Modify` (Modify) on top of what it inherits.

The scripted version of exactly this step is `scripts\New-LabFileShare.ps1` in this repo — run it for a fourth folder (e.g. `D:\Shares\Projects`) once you've done one by hand.

**✅ Checkpoint:** Still signed in as administrator, open the **Advanced Security Settings** for Finance → **Effective Access** tab → select user `lab.hr` → View effective access. `lab.hr` should show **no access** to Finance. Now select `lab.fin` — Modify-level access appears. If `lab.hr` can read Finance, inheritance or a group is wrong — fix it now, not after sharing.

---

## Step 5 — Share the folders over SMB

Share permissions are the second lock on the door. Best practice for this lab: share permissions grant the **groups** Full/Change as appropriate, and NTFS (Step 4) does the fine-grained work. When the two disagree, the user gets the **more restrictive** result.

For each folder: right-click → Properties → **Sharing** tab → **Advanced Sharing** → tick **Share this folder**:

| Share name | Path | Share permissions |
|---|---|---|
| `HR` | `D:\Shares\HR` | `FS-HR-Read`: Read · `FS-HR-Modify`: Change · remove `Everyone` |
| `Finance` | `D:\Shares\Finance` | `FS-Finance-Read`: Read · `FS-Finance-Modify`: Change · remove `Everyone` |
| `Shared` | `D:\Shares\Shared` | `FS-Shared-Read`: Read · `FS-Shared-Modify`: Change · remove `Everyone` |

Or the PowerShell one-liner per share (this is what the script does):

```powershell
New-SmbShare -Name "Finance" -Path "D:\Shares\Finance" `
    -ReadAccess "FS-Finance-Read" -ChangeAccess "FS-Finance-Modify"
```

Verify the server is actually serving SMB:

```powershell
Get-SmbShare
Get-Service LanmanServer   # the "Server" service — must be Running
Test-NetConnection -ComputerName fs01 -Port 445   # from the client PC
```

**✅ Checkpoint:** `Get-SmbShare` lists HR, Finance and Shared, and the port 445 test from the client succeeds (`TcpTestSucceeded : True`).

---

## Step 6 — Map the drive from a client PC

On the client PC (or your host machine), sign in as `lab.fin` if it's a lab domain-less setup you'll be prompted for credentials — use `fs01\lab.fin` so Windows knows the account lives on the server.

1. File Explorer → This PC → **Map network drive**.
2. Drive letter `F:`, folder `\\fs01\Finance`, tick **Reconnect at sign-in**.
3. Repeat with `S:` → `\\fs01\Shared`.
4. Command-line equivalent (and what login scripts/GPOs do in real offices):

```
net use F: \\fs01\Finance /persistent:yes
net use S: \\fs01\Shared /persistent:yes
```

5. Try mapping `H:` → `\\fs01\HR` as `lab.fin`. It should **fail** with access denied — that's the permissions working, and it's the exact error users report on tickets.

**✅ Checkpoint:** As `lab.fin`: F: and S: open and you can create a file in both. `\\fs01\HR` gives *Access is denied*. All three results are correct behaviour.

---

## Step 7 — Set a folder quota

A quota stops one folder from eating the whole volume. There are two honest paths depending on your OS:

### Path A — Windows Server 2022: FSRM (per-folder quotas) ✅ recommended

1. Install the role: Server Manager → Add Roles and Features → **File and Storage Services → File and iSCSI Services → File Server Resource Manager**. (Or PowerShell: `Install-WindowsFeature FS-Resource-Manager -IncludeManagementTools`.)
2. Open **File Server Resource Manager** (`fsrm.msc`) → Quota Management → Quotas → right-click → **Create Quota**.
3. Quota path: `D:\Shares\Finance`. Choose a template or define a custom **hard** limit of **2 GB** for the lab (small on purpose, so you can hit it during testing), with a warning threshold at 85%.
4. FSRM also gives you quota usage reports and can email warnings — in the lab, just watch the console.

### Path B — Windows 10/11 Pro: NTFS disk quotas (per-user, per-volume)

Be honest with yourself here: client Windows has **no per-folder quotas**. NTFS disk quotas limit **each user** on the **whole volume** — a blunt tool, but it's what's available without FSRM.

1. Right-click `D:` → Properties → **Quota** tab → **Enable quota management**.
2. Set a default limit (e.g. 2 GB per user) and a warning level.
3. **Quota Entries** shows per-user usage on the volume.

Pick one path and note in your lab diary which you used and why. Interviewers respect "client Windows can't do per-folder quotas, that's FSRM on Server" far more than bluffing.

**✅ Checkpoint (Path A):** As `lab.fin`, copy a file larger than the remaining quota into `F:` — the copy fails with a "not enough space" style error even though `D:` has free space. That's the quota working. (Path B: fill past the per-user limit and see the same class of error.)

---

## Step 8 — Enable and schedule Volume Shadow Copies

This is the step that pays for the whole lab on a real service desk.

Shadow copies ("Previous Versions") are point-in-time snapshots of the volume. They are **not a backup** — they live on the same disk — but they are the fastest fix for accidental deletes and overwrites.

1. Make sure the service is running: `Get-Service VSS` → set to **Manual** (its normal state; Windows starts it on demand) and confirm **Volume Shadow Copy** isn't Disabled. Also check `Get-Service swprv` (Microsoft Software Shadow Copy Provider).
2. Right-click `D:` in File Explorer → Properties → **Shadow Copies** tab → select `D:` → **Enable**.
   - Or run the script: `scripts\Enable-ShadowCopies.ps1 -Volume D: -MaxSizeMB 2048`
   - Accept the default storage location (on `D:` itself for the lab) and set a size limit — e.g. **2048 MB** — so snapshots can't consume the volume.
3. Click **Settings** → **Schedule** and set snapshots for **7:00 AM** and **12:00 PM** on weekdays. Twice a day is the classic office pattern: one before work, one at lunch.
   - Note: `vssadmin` can create and resize shadow storage but cannot set a recurring schedule — on Server the schedule above is what configures it; on client Windows the schedule is a Task Scheduler task calling `vssadmin Create Shadow`. The script's comments explain this.

**✅ Checkpoint:** Shadow Copies tab for `D:` shows "Next Run Time" populated, and running `vssadmin List Shadows` after the first scheduled time (or a manual snapshot, next step) shows a shadow copy exists.

---

## Step 9 — The restore drill (the whole point)

Do this exactly once by hand. It's the demo from the reel, and it's the ticket you'll fix monthly in a real job.

1. As `lab.fin`, in the mapped `F:` drive (Finance), create a spreadsheet named **`budget.xlsx`** (Excel, LibreOffice, or even a renamed text file for the lab — a real `.xlsx` is better). Put a number in it, e.g. `1200` in cell A1. Save and close it.
2. Take a snapshot **now** so you don't have to wait for the schedule: right-click `D:` → Properties → Shadow Copies → **Create Now**. (Or `vssadmin Create Shadow /For=D:`.)
3. Delete `budget.xlsx` from the Finance share. Empty it from the client's Recycle Bin too if it landed there — network deletes usually bypass the Recycle Bin, which is exactly why users panic.
4. **Restore it:** on the client, right-click the **Finance folder** (or its parent in the share) → Properties → **Previous Versions** tab → pick the snapshot from a few minutes ago → **Open** → you should see `budget.xlsx` sitting there.
5. Drag/copy `budget.xlsx` back into the live Finance folder (copy-back is safer than clicking **Restore** on the whole folder, which would roll back *everything* in it — say this out loud; it's the detail that separates a careful tech from a cowboy).
6. Open the restored `budget.xlsx` and confirm cell A1 still says `1200`.

**✅ Checkpoint:** The file is back, opens, and contains the right value. Also try the variant: *modify* the file (change A1 to `9999`), snapshot/delete not needed — Previous Versions on the file itself offers the older copy. Overwrite-recovery is the second half of the same skill.

---

## Step 10 — Volume usage monitoring

1. Run the report script as administrator on the server:

```powershell
.\scripts\Get-ShareUsageReport.ps1 -ThresholdPercent 80
```

It lists each SMB share with its path, size used, file count, and the free/used state of the underlying volume, flagging anything over the threshold.

2. Also learn the built-ins: `Get-SmbShare`, `Get-Volume`, and (Path A) FSRM's quota view. In a real job this is the "the S: drive is full" ticket: check usage → find the big folder → check quota → talk to the owner before deleting anything.

**✅ Checkpoint:** The report runs without errors and the Finance row roughly matches what you copied into the share during Step 7.

---

## You're done when…

- [ ] `\\fs01\HR`, `\\fs01\Finance`, `\\fs01\Shared` all appear in `Get-SmbShare`
- [ ] `lab.fin` can modify Finance and Shared but gets *Access denied* on HR
- [ ] Effective Access in the NTFS Advanced dialog agrees with the test above
- [ ] The quota stops an oversized copy with an error
- [ ] `vssadmin List Shadows` shows snapshots on the schedule you set
- [ ] You deleted `budget.xlsx` and restored it from Previous Versions, contents verified
- [ ] `Get-ShareUsageReport.ps1` runs and flags an over-threshold volume correctly

Now break things on purpose and fix them with **TROUBLESHOOTING.md**. That's where the service-desk learning actually happens.
