# Homelab File Server & Storage Lab

A hands-on Windows file server project: one box acting as a departmental file server with SMB shared folders, NTFS permissions, folder quotas, Volume Shadow Copies for "Previous Versions" restores, and basic volume usage monitoring.

> **Honest note:** This is a self-directed homelab project built for learning and portfolio purposes. It is not production work and was not deployed at an employer. Everything here runs on a home virtual machine or spare PC.

---

## What this is

A single Windows machine (hostname `fs01.lab.local`) set up the way a small business or a branch office would run its file shares:

- A dedicated data volume for shared folders (separate from the Windows `C:` drive).
- Department-style folders — `HR`, `Finance`, `Shared` — each with different access.
- SMB shares served on port 445 so client PCs can map a drive letter to them.
- NTFS permissions with inheritance, controlled through groups (least privilege), instead of granting access to individual users.
- A folder quota so one department can't fill the whole disk.
- **Volume Shadow Copy (VSS) enabled and scheduled**, so a file a user "accidentally deleted" can be brought back from a snapshot using the *Previous Versions* tab — the lab's restore drill deletes `budget.xlsx` from the Finance share and restores it.
- A small PowerShell report that shows how full each share/volume is, and flags anything over a threshold.

## Why it matters for helpdesk / service-desk work

Three of the most common tickets a service desk analyst sees every week are storage tickets:

1. **"I can't get into the folder"** — access requests and access-denied errors. This lab teaches the difference between *share permissions* and *NTFS permissions*, and how to check a user's effective access instead of guessing.
2. **"I deleted a file / someone deleted the folder"** — with shadow copies enabled, the fix is a 2-minute Previous Versions restore instead of a "sorry, it's gone" or a full backup restore. Knowing when Previous Versions will and won't save you is a real interview answer.
3. **"The drive is full"** — quotas and usage monitoring. This lab shows how to see what's filling a volume and how quotas stop one team from taking the whole disk down.

If you can explain these three scenarios calmly — and you've actually done the restore drill with your own hands — you sound like someone who has worked a service desk, not someone who only read about one.

## Design (in words)

```
                        ┌──────────────────────────────┐
   Client PC            │  fs01.lab.local              │
   (Windows 10/11)      │  Windows Server 2022 (eval)  │
                        │  or Windows 10/11 Pro        │
   Map drive S: ───────►│                              │
   to \\fs01\Shared     │  Data volume (e.g. D:)       │
   Map drive F: ───────►│   └─ Shares\                 │
   to \\fs01\Finance    │       ├─ HR\                 │
                        │       ├─ Finance\            │
   SMB over TCP 445     │       └─ Shared\             │
                        │                              │
                        │  VSS shadow copies of D:     │
                        │  scheduled twice daily       │
                        └──────────────────────────────┘
```

- **One server, one data volume.** The OS stays on `C:`; all shared data lives on a second disk or partition (e.g. `D:`). This makes quotas, shadow copies, and backups behave like they do in a real office.
- **Groups, not people.** Access is granted to local groups such as `FS-HR-Read` and `FS-HR-Modify`. To give someone access you add them to a group — you never edit folder ACLs for one person.
- **Different folders, different rules.**
  - `Shared` — everyone in the lab can read; a modify group can add/edit files.
  - `Finance` — only Finance groups can even see inside; inheritance stays on within the folder but the folder itself breaks from the parent so `Shared` users can't wander in.
  - `HR` — the most restricted; only HR groups, no broad read access.
- **Share permissions are simple, NTFS does the real work.** The SMB share grants the groups access, and NTFS enforces the detail. (The troubleshooting guide explains what happens when these two disagree — the most restrictive result wins.)
- **Shadow copies are the safety net.** VSS snapshots of the data volume run on a schedule (e.g. 7:00 AM and 12:00 PM). Users can self-serve a restore from the Previous Versions tab, and IT can restore on their behalf.
- **Quotas keep the disk honest.** A quota on the Finance folder (FSRM on Windows Server, or NTFS disk quotas on client editions of Windows) generates a warning before the volume fills.

## Skills demonstrated

- Windows file services: SMB shares (TCP 445), share vs NTFS permissions
- NTFS ACLs, permission inheritance, least-privilege group design
- Local users and groups management
- Folder quotas (FSRM) and NTFS disk quotas
- Volume Shadow Copy Service (VSS): enabling, scheduling, storage limits
- File recovery with Previous Versions (the restore drill)
- Drive mapping from a client PC (`net use` / File Explorer)
- PowerShell automation and reporting (folder/share creation, usage report)
- Ticket-style troubleshooting and documentation

## What you need

| Item | Options |
|---|---|
| File server machine | A spare PC, or a VM (VirtualBox / Hyper-V / VMware) with ~2 vCPU, 4 GB RAM |
| Server OS | **Windows Server 2022 Evaluation** (free 180-day eval from Microsoft) — recommended, because it includes FSRM. **Or Windows 10/11 Pro** — everything except FSRM works; use NTFS disk quotas instead (the guide explains both paths honestly). |
| Data volume | A second virtual disk or partition for the data volume (10–20 GB is plenty). A second disk is strongly recommended — shadow copies and quotas behave differently on the system drive. |
| Client machine | Any Windows 10/11 PC or a second VM on the same (virtual) network |
| Time | About 2–3 hours including the restore drill |

No paid software is required. The Windows Server evaluation is fully functional for this lab.

## Repo structure

```
homelab-file-server/
├─ README.md                    ← you are here
├─ BUILD-GUIDE.md               ← step-by-step build, with verification checkpoints
├─ TROUBLESHOOTING.md           ← service-desk playbook for the classic tickets
└─ scripts/
   ├─ New-LabFileShare.ps1      ← creates a folder, sets NTFS ACLs, publishes the SMB share
   ├─ Get-ShareUsageReport.ps1  ← report-only: share sizes, file counts, over-threshold flags
   └─ Enable-ShadowCopies.ps1   ← enables/configures VSS shadow copies for a volume (vssadmin)
```

## How to use this repo

1. Follow **BUILD-GUIDE.md** from top to bottom on your lab machine.
2. Use the scripts in `scripts/` to automate the repetitive parts once you've done them by hand once (doing it by hand first is how you learn what the script is doing).
3. Run the **restore drill** in the guide: create `budget.xlsx`, take a snapshot, delete the file, restore the previous version, verify the contents.
4. Keep **TROUBLESHOOTING.md** open while you practise — break things on purpose (wrong group, quota too small, shadow copy service stopped) and fix them using the playbook.

## Talking about this project in an interview

- "I built a Windows file server lab with department shares, group-based NTFS permissions, and quotas."
- "I enabled Volume Shadow Copies and practised restoring a deleted spreadsheet from Previous Versions — the same fix you'd use on a real 'I deleted a file' ticket."
- "I learned that share permissions and NTFS permissions combine, and the most restrictive one wins — I check Effective Access instead of guessing."
- "I wrote PowerShell scripts to create shares consistently and to report on volume usage before a disk fills up."
