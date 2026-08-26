# Requirements

At0mFlow Script Audit has no third-party runtime dependencies.

## Supported environment

- Windows PowerShell 5.1 or PowerShell 7.4 or newer on Windows.
- The built-in ScheduledTasks module when scheduled-task discovery is enabled.
- Read access to the paths and scheduled tasks being audited.
- PowerShell remoting and WinRM access for server-to-server collection.
- Write access to the selected local or UNC output path.

Local administrator access is recommended for a complete server audit, but the
tool records access failures instead of silently claiming a complete result.

PSScriptAnalyzer 1.25.0 is used by contributors and CI. It is not required to
run the collector.

No At0mFlow account, API key, Git remote or paid dependency is required.
