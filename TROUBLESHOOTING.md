# Troubleshooting Playbook — File Server Tickets

The five tickets a file server generates over and over, written the way a service desk should work them: **symptom → likely cause → fix → verify**. Each one maps to something you built in `BUILD-GUIDE.md`, so you can reproduce every fault in the lab on purpose and practise the fix.

General rule before any of them: **don't delete or "fix permissions" blindly.** Read the error, check the effective permissions, check the services, and verify with the actual user account. Most file-server tickets are one of the five below wearing a disguise.

---

## 1. "I deleted a file" / "Who deleted the folder?"

**Symptom:** User reports a file or folder missing from the share. Sometimes it's "someone deleted it," sometimes they admit it was them. The file is **not** in the Recycle Bin — deletes over a network share normally bypass the Recycle Bin entirely, which is why the user is panicking.

**Likely cause:** Accidental delete or overwrite by a user with Modify rights, or a file dragged into a neighbouring folder (check that first — search the share for the filename before assuming deletion).

**Fix (restore from shadow copy / Previous Versions):**

1. On the client (or server), browse to the **folder that contained** the file — you restore from the parent folder's snapshots, even if the file itself is gone.
2. Right-click the folder → **Properties → Previous Versions**.
3. Pick a snapshot from **before** the deletion (check the timestamps; the twice-daily schedule from the build guide means the newest copy is at most a few hours old).
4. Click **Open** — not Restore — and locate the file inside the snapshot.
5. **Copy** the file out and paste it back into the live folder. Copying a single file out is always safer than **Restore**, which rolls the *entire folder* back and would undo everyone else's work since the snapshot.
6. If a whole folder was deleted, open the Previous Version of its **parent** folder and copy the missing folder out the same way.
7. If the file was *overwritten* with bad data rather than deleted: right-click the file itself → Previous Versions → copy out the older version under a new name, and let the user confirm it's the right one before replacing the live copy.

> "Who deleted it?" — be honest on the ticket: without file-access auditing enabled in advance, Windows cannot tell you who deleted a file after the fact. Previous Versions gets the file back; it does not name a culprit. (Enabling Audit Object Access + SACLs is how you'd answer it *next* time — a good thing to mention, a bad thing to bluff about.)

**Verify:** The restored file opens, and the user confirms the contents are correct (open it, check a value they recognise). Note on the ticket which snapshot time you restored from and that anything changed *after* that snapshot isn't in the restored copy.

**If Previous Versions is empty:** jump to ticket #5 — shadow copies aren't running.

---

## 2. "Access is denied" opening a share or folder

**Symptom:** User gets *Access is denied* (or repeated credential prompts) opening `\\fs01\Finance` or a folder inside it. Often right after they were "given access."

**Likely cause (check in this order):**

1. **Share permission vs NTFS permission mismatch.** Two locks, both must open. The user needs access at the SMB share **and** in the folder's NTFS ACL — the **more restrictive** of the two is what they actually get. Classic case: share says Change, NTFS says nothing (or Deny) → denied.
2. **Group membership hasn't taken effect.** You added them to `FS-Finance-Modify` 2 minutes ago, but group membership is picked up at **sign-in**. Their current session still has yesterday's token.
3. **They're in the wrong group** — Read group when they need Modify (they can open but can't save), or simply never added.
4. **An explicit Deny** somewhere on the folder or a parent — Deny beats Allow, always.
5. **Inheritance is off** on a subfolder, so the permissions you set at the top never flowed down to where the file actually lives.

**Fix:**

1. On the server: folder → Properties → Security → **Advanced → Effective Access** tab → select the user → view what they *actually* have and which layer (share/NTFS) is limiting it. This tab ends all guesswork — use it every time.
2. Compare against the share permissions: `Get-SmbShareAccess -Name Finance`.
3. Correct the wrong layer (almost always: add the user to the correct **group** — not a one-off ACL entry for their name).
4. Have the user **sign out and back in** (or reboot) so the new group membership applies, then retest.

**Verify:** The user opens the folder and performs the exact action that failed — open *and* save a test file if they need Modify. Don't close the ticket on "looks right from the server."

---

## 3. Mapped drive is missing / won't reconnect

**Symptom:** "My F: drive is gone," or the drive shows with a red X and errors when clicked, usually first thing in the morning.

**Likely cause:**

1. **The Server service (`LanmanServer`) on fs01 is stopped** — then *nobody* can connect, not just this user. Check the blast radius first.
2. **The client workstation service / network wasn't ready at sign-in**, so the persistent mapping failed and Windows didn't retry.
3. **Stored credentials are wrong or expired** — user changed their password; the saved credential for `\\fs01` is stale, so reconnect fails silently or prompts repeatedly.
4. **The mapping was never persistent**, or (in domain environments) the **GPO / login script** that maps it failed to apply.
5. Name resolution: the PC can't resolve `fs01` (DNS/vlans asleep) — test with the IP address to separate name problems from share problems.

**Fix:**

1. On the server: `Get-Service LanmanServer` — start it if stopped, and check it isn't set to Disabled. Also confirm SMB is listening: `Test-NetConnection fs01 -Port 445` from the client.
2. On the client, remove the broken mapping and recreate it:
   ```
   net use F: /delete
   net use F: \\fs01\Finance /persistent:yes
   ```
3. If credentials are the issue: open **Credential Manager → Windows Credentials**, remove the stale `fs01` entry, then reconnect and sign in fresh (with `fs01\username` so the account is looked up on the server).
4. Domain environment: run `gpupdate /force`, sign out/in, and check the login script/GPO drive-map preference actually targets this user/group.

**Verify:** Reboot (or sign out/in) and confirm the drive appears on its own and opens without prompts — a mapping that only works until the next reboot isn't fixed.

---

## 4. "The drive is full" / quota exceeded

**Symptom:** User can't save — "There is not enough space on the disk" — even though the server's drive visibly has free space. Or: the whole share genuinely is full and everyone is affected.

**Likely cause:**

1. **The folder quota is hit (FSRM)**, or the user's **NTFS disk quota** is hit on client-OS setups. The volume has space; *their allowance* doesn't. This is the quota working as designed.
2. **The volume really is full** — one folder grew (old exports, video files, shadow copies with no size limit quietly eating the disk).
3. **Shadow copy storage** is consuming the volume because no maximum size was set (the build guide sets one for exactly this reason).

**Fix:**

1. Work out which case it is: run `scripts\Get-ShareUsageReport.ps1` on the server, and check the quota console — FSRM → Quotas (Server) or `D:` → Properties → Quota → Quota Entries (client OS).
2. Identify the largest consumers before touching anything: biggest folders/files, and who owns them.
3. **Talk to the data owner.** Archive or delete *with their agreement*, or raise the quota through the proper approval — never silently raise a quota or delete someone else's files to make a ticket go away; that trades one ticket for a worse one.
4. If shadow storage is the culprit, cap it (`vssadmin Resize ShadowStorage /For=D: /On=D: /MaxSize=2048MB`) rather than deleting snapshots — users may still need them for ticket #1.

**Verify:** The user saves the exact file that failed, and the report/quota console shows the volume back under the threshold.

---

## 5. Previous Versions is empty / "shadow copy not available"

**Symptom:** During a ticket-#1 restore, the Previous Versions tab shows "There are no previous versions available," or the tab doesn't exist at all.

**Likely cause:**

1. **Shadow copies were never enabled** on that volume, or enabled but **no snapshot has been taken yet** (schedule is set for 7 AM and it's 6:30 AM on day one).
2. **The Volume Shadow Copy service is stopped/disabled**, or the snapshot schedule was never actually configured (remember: `vssadmin` alone doesn't create a schedule — it needs the Shadow Copies settings page or Task Scheduler).
3. **Storage ran out:** the shadow storage limit was hit and VSS quietly deleted the oldest snapshots — or the volume filled and snapshots were purged.
4. You're looking at the **wrong object**: Previous Versions lives on the *folder/share* — checking the deleted file's old shortcut or the wrong parent folder shows nothing.

**Fix:**

1. On the server: `vssadmin List Shadows` and `vssadmin List ShadowStorage` — do any snapshots exist, and is there storage assigned?
2. Check services: `Get-Service VSS, swprv` — neither should be Disabled; VSS is normally **Manual** (starts on demand), which is fine.
3. Open `D:` → Properties → **Shadow Copies**: confirm the volume is enabled, a storage limit is set, and **Settings → Schedule** actually shows your times. If scheduling was meant to be Task Scheduler, open `taskschd.msc` and check the snapshot task's history.
4. Take a manual snapshot now to prove the machinery works: `vssadmin Create Shadow /For=D:` (or the repo's `scripts\Enable-ShadowCopies.ps1`, which also reports the state).
5. Accept the limit honestly with the user: if no snapshot exists from before the deletion, Previous Versions **cannot** recover the file — the fallback is the real backup system, if there is one. Say so plainly, restore what you can, and fix the schedule so it doesn't happen again.

**Verify:** Create a throwaway file in the share, take a snapshot, delete the file, and restore it from Previous Versions end-to-end. Only then is this ticket closed.

---

## Quick command reference

| Task | Command |
|---|---|
| List shares | `Get-SmbShare` |
| Who has share access | `Get-SmbShareAccess -Name Finance` |
| Check the SMB service | `Get-Service LanmanServer` |
| Test SMB from a client | `Test-NetConnection fs01 -Port 445` |
| User's real permissions | Folder → Advanced Security → **Effective Access** |
| List snapshots | `vssadmin List Shadows` |
| List snapshot storage | `vssadmin List ShadowStorage` |
| Take a snapshot now | `vssadmin Create Shadow /For=D:` |
| Map a drive | `net use F: \\fs01\Finance /persistent:yes` |
| Share usage report | `.\scripts\Get-ShareUsageReport.ps1` |
