# Output schema

## `script-inventory.csv`

One row represents one source path on one computer.

| Field | Meaning |
| --- | --- |
| `ComputerName` | Windows computer that owned the source path. |
| `OriginalPath` | Original script path. |
| `CentralRelativePath` | Collision-safe path inside the bundle. |
| `DiscoverySources` | `SearchPath`, `ScheduledTask`, or both. |
| `ReferencedByTasks` | Scheduled task paths and names linked to the script. |
| `DeclaredAuthor` | Optional `# Author:` or `# Created by:` header value. |
| `FileOwner` | Windows ACL owner at collection time. |
| `LengthBytes` | Source size. |
| `CreatedUtc` | Source creation time in UTC. |
| `LastWriteUtc` | Source modification time in UTC. |
| `SHA256` | Source content hash. |
| `CopyStatus` | `Copied`, `InventoryOnly`, `Missing`, `TooLarge`, `CopyFailed` or `HashMismatch`. |

`DeclaredAuthor` and `FileOwner` are evidence fields, not proof of authorship.

## `scheduled-tasks.csv`

One row represents one PowerShell-related action on a non-excluded scheduled
task. Multi-action tasks therefore have multiple rows.

It records task identity, state, description, principal, run level, logon type,
action command, arguments, working directory, discovered script references,
excluded references, triggers, conditions, last run, next run and last result.

## `collection-errors.csv`

Every row includes a computer, collection stage, target and readable message.
Common stages include remote connection, search access, missing task references,
file metadata, size limits, copy and hash verification.

The collector caps detailed discovery errors per computer and records the
suppressed count so a noisy access problem cannot create an unbounded CSV.

## `summary.json`

Contains tool version, timestamps, output location, collection mode, counts,
error status and the search roots used on each computer.

## `TREE.txt`

Shows the physical folder tree under `scripts/` for quick audit orientation.
