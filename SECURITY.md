# Security

## Reporting a vulnerability

Please do not open a public issue for a suspected security vulnerability. Send
the details through the contact channel at [at0mflow.com](https://at0mflow.com/)
and include `At0mFlow-ScriptAudit security` in the subject or message.

## Audit bundle handling

Generated bundles can contain executable source code and infrastructure
metadata. Store them in an access-controlled location, review them for secrets
before placing them in Git, and use a private repository when version control is
approved.

The collector does not request, store or transmit passwords. A supplied
`PSCredential` is passed only to PowerShell remoting for the current run. It is
not written to the bundle.

The project has no telemetry, hosted service or At0mFlow API client. Git is
disabled by default. `-GitSync` works only inside an existing working tree,
uses the operator's existing non-interactive Git configuration and scopes its
commit to the bundle's `scripts/`, `manifests/` and `README.txt` paths. It never
initialises a repository, creates a remote or stores credentials.

Task outcome evidence comes only from the previous hour of the local Windows
Task Scheduler Operational event log. The collector does not run discovered
scripts and does not interpret missing logs as success or failure.
