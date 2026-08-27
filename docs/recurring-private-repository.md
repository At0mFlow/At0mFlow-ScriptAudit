# Recurring private repository refresh

Use this mode only after the collected material has been approved for a private
Git repository.

The collector can refresh the same stable folder tree on a schedule. Existing
scripts are overwritten only when their SHA-256 content changes. The inventory
records the physical source path, absolute collected-copy path, portable
repository-relative path, previous hash, current hash and whether the copy was
added, modified or unchanged.

## Prepare the working tree

Before using `-GitSync`, configure and test these items under the Windows
identity that will run the scheduled task:

1. An existing private Git working tree.
2. An existing remote and upstream branch.
3. Repository-local Git author name and email.
4. Non-interactive authentication suitable for that private remote.
5. Write permission to the collector output path.
6. Read permission to the source paths and local Task Scheduler Operational
   event log.

The collector does not create, store or repair any of these settings.

Task Scheduler history must already be enabled on each collected server. An
administrator can enable it through Task Scheduler's **Enable All Tasks
History** action or, after reviewing the change, with:

```powershell
wevtutil.exe sl Microsoft-Windows-TaskScheduler/Operational /e:true
```

Grant the scheduled identity only the local event-log access it needs, commonly
through the built-in **Event Log Readers** group. The collector does not change
event-log settings or local group membership.

## Run once interactively

```powershell
./src/Invoke-At0mFlowScriptAudit.ps1 `
    -SearchPath C:\Scripts, D:\Automation `
    -OutputPath D:\PrivateGit\PowerShell-Estate `
    -Force `
    -GitSync
```

Review the resulting commit and confirm that the expected private remote
received it before scheduling the command.

## Schedule hourly

Create a Windows Scheduled Task that runs the same command every hour. Use an
approved service identity or managed execution identity that already has the
required file, event-log and Git permissions. Add `-Quiet` for non-interactive
output and `-FailOnCollectionError` when collection gaps should fail the task.

Task Scheduler Operational evidence is always limited to the previous hour.
This makes an hourly schedule a natural fit without turning the public tool into
a resident agent.

## Safety boundaries

- The source scripts are read only. The collector never modifies or executes
  them.
- Git must already exist and be configured by the operator.
- Credentials are never accepted or stored by the collector.
- Git prompts are disabled so unattended runs fail clearly instead of hanging.
- Only the selected output's `scripts/`, `manifests/` and `README.txt` are
  committed.
- Other files and staged changes are not included in the collector commit.
- The one-hour event evidence comes only from Windows Event Viewer on each
  collected computer. No At0mFlow service is contacted.

For a reusable, repository-agnostic scheduled commit tool, use
[At0mFlow RepoSync](https://github.com/At0mFlow/At0mFlow-RepoSync). A clear
separation of responsibilities is often easier to operate: Script Audit
refreshes the approved `scripts/` and `manifests/` folders, then RepoSync
previews, commits and optionally pushes only those paths.
