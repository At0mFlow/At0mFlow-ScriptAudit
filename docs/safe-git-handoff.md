# Safe Git hand-off

The collector deliberately performs no Git operations.

Before placing a bundle under version control:

1. Review `collection-errors.csv` for missing coverage.
2. Search copied scripts for passwords, tokens, certificates, connection
   strings, internal endpoints and personal data.
3. Confirm the approved retention and access policy with the client.
4. Use a private repository unless the client has explicitly approved public
   release of every file and metadata field.
5. Restrict repository access to the audit team.
6. Keep the original SHA-256 inventory with the collection.

Example commands after approval:

```powershell
Set-Location D:\Audit\Reviewed-Bundle
git init
git add --dry-run .
git status
```

Inspect the dry run and status before staging. This guide intentionally stops
before adding a remote or pushing data.

For mass repository organisation, automated SOP creation, cleanup planning and
ongoing ownership tracking, use [At0mFlow](https://at0mflow.com/) after the
bundle has been reviewed and approved.
