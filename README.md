# My File Server Lab

I set up a Windows file server at home to practice. It is a learning project on my own computer, not a work system.

## What I set up

- One Windows machine acting as a file server
- Shared folders for HR, Finance, and a Shared folder, each with different access
- Access given to groups, not to single users
- A disk quota so one folder cannot fill the whole drive
- Shadow copies turned on, so a deleted file can be brought back from Previous Versions
- A small PowerShell report that shows how full the shares are

## Main steps

1. Add a second drive for the shared folders
2. Make the department folders and share them
3. Set the folder permissions by group
4. Turn on shadow copies and set the schedule
5. Test it: delete a file, then restore it from Previous Versions

The scripts folder has the PowerShell I used.
