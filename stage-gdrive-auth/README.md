# stage-gdrive-auth

Decodes a `GOOGLEDRIVE_AUTH` secret onto the runner and reports its path as a
step output. The secret can be a **user OAuth token** or a **service-account
key**; each gets its own output. Does nothing and never fails when the secret
is absent — the normal case on fork PRs, where GitHub withholds secrets.

## Usage

Stage it as late as possible in the job: every dependency-install step runs
third-party code and none of it needs this credential. Never put the secret in a
job-level `env:`.

```yaml
- name: Stage Google Drive credentials
  id: gdrive-auth
  uses: PredictiveEcology/actions/stage-gdrive-auth@main
  with:
    credential: ${{ secrets.GOOGLEDRIVE_AUTH }}
    present: ${{ secrets.GOOGLEDRIVE_AUTH != '' }}

- uses: r-lib/actions/check-r-package@v2
  env:
    GDRIVE_OAUTH_TOKEN: ${{ steps.gdrive-auth.outputs.token-path }}
    GOOGLEDRIVE_AUTH: ${{ steps.gdrive-auth.outputs.sa-path }}
```

At most one output is non-empty:

| Secret holds | Output | Env var for R | R call |
|---|---|---|---|
| user OAuth token | `token-path` | `GDRIVE_OAUTH_TOKEN` | `drive_auth(token = readRDS(f))` |
| service-account key | `sa-path` | `GOOGLEDRIVE_AUTH` | `drive_auth(path = f)` |

Both are paths to a file, never the secret itself. Both empty means the R side
sees unset vars and skips, exactly as it does locally. Before using a token, set
`tok$cache_path <- NULL`, or `drive_auth()` tries to write the refreshed token
to the folder it was minted in, fails on the runner, and reports that as no
credential.

## Storing the secret

A user OAuth token is binary, so it must be base64-encoded:

```r
saveRDS(googledrive::drive_token(), "gdrive-token.rds")
```

```sh
base64 -w0 gdrive-token.rds   # paste the output as the GOOGLEDRIVE_AUTH secret
```

A service-account key can be stored as base64 or as the raw JSON. Raw JSON is
multi-line, and a multi-line value arrives **empty** on Windows runners because
PowerShell cannot set env vars containing newlines, so use base64 for any
workflow that runs on Windows.

`present` is passed separately because a single-line boolean always survives the
env boundary. It is what separates "no secret configured" (quiet) from "secret
configured but dropped in transit" (warned).

## Which credential to use

A service account can read files shared with it, and can upload to a Shared
Drive. It cannot upload into a folder in a person's My Drive: the new file would
belong to the service account, which has no storage quota, and Drive answers
`403 storageQuotaExceeded`. So tests that upload into a personal folder need a
user OAuth token. Tests that only download, or that upload to a Shared Drive,
can use either.
