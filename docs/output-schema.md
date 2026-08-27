# Output schema

## `script-inventory.csv`

One row represents one source path on one computer.

| Field | Meaning |
| --- | --- |
| `ComputerName` | Windows computer that owned the source path. |
| `OriginalPath` | Original script path. |
| `CentralRelativePath` | Collision-safe path inside the bundle. |
| `SourcePhysicalPath` | Explicit physical path of the source script. |
| `CollectedCopyPath` | Absolute local path of the copied script. |
| `RepositoryRelativePath` | Stable Git-relative path when the bundle is inside a Git working tree. |
| `DiscoverySources` | `SearchPath`, `ScheduledTask`, or both. |
| `ReferencedByTasks` | Scheduled task paths and names linked to the script. |
| `DeclaredAuthor` | Optional `# Author:` or `# Created by:` header value. |
| `FileOwner` | Windows ACL owner at collection time. |
| `LengthBytes` | Source size. |
| `CreatedUtc` | Source creation time in UTC. |
| `LastWriteUtc` | Source modification time in UTC. |
| `SHA256` | Source content hash. |
| `PreviousCollectedSHA256` | Hash of the prior collected copy when one existed. |
| `CollectedSHA256` | Verified hash of the current collected copy. |
| `CollectionChange` | `Added`, `Modified`, `Unchanged`, `NotCopied`, `Unavailable`, `CopyFailed` or `HashMismatch`. |
| `CopyStatus` | `Copied`, `InventoryOnly`, `Missing`, `TooLarge`, `CopyFailed` or `HashMismatch`. |

`DeclaredAuthor` and `FileOwner` are evidence fields, not proof of authorship.

## `scheduled-tasks.csv`

One row represents one PowerShell-related action on a non-excluded scheduled
task. Multi-action tasks therefore have multiple rows.

It records task identity, state, description, principal, run level, logon type,
action command, arguments, working directory, discovered script references,
excluded references, triggers, conditions, last run, next run and last result.

## `script-run-evidence.csv`

One or more rows represent the available execution evidence for each discovered
script. The time window is always the previous hour from the local
`Microsoft-Windows-TaskScheduler/Operational` event log.

`EvidenceStatus` distinguishes observed events from no scheduled-task
reference, no matching event and an unavailable event log. `Outcome` is
`Succeeded`, `Failed`, `SchedulerStatus` or `Unknown`. `Attribution` states
whether the event matched an exact task action, only the task, or an ambiguous
multi-action task.

Observed rows include the event timestamp, ID, record ID, task, action, exact
result code and a stable `EvidenceKey`. Consumers should deduplicate using that
key and must not create failure events from `Unknown` rows.

## `collection-errors.csv`

Every row includes a computer, collection stage, target and readable message.
Common stages include remote connection, search access, missing task references,
file metadata, size limits, copy and hash verification.

The collector caps detailed discovery errors per computer and records the
suppressed count so a noisy access problem cannot create an unbounded CSV.

## `summary.json`

Contains tool version, timestamps, output and optional Git working-tree
locations, collection mode, counts, error status, one-hour evidence status and
the search roots used on each computer.

## `TREE.txt`

Shows the physical folder tree under `scripts/` for quick audit orientation.
