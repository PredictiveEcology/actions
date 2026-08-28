# stage-gdrive-auth

Decodes a `GOOGLEDRIVE_AUTH` secret onto the runner and reports which credential
type arrived, as typed step outputs. Does nothing and never fails when the
secret is absent — the normal case on fork PRs, where GitHub withholds secrets.

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
    GOOGLEDRIVE_AUTH: ${{ steps.gdrive-auth.outputs.sa-path }}
    GDRIVE_OAUTH_TOKEN: ${{ steps.gdrive-auth.outputs.token-path }}
```

Exactly one of the two outputs is non-empty. Both empty means the R side sees
unset vars and skips, exactly as it does locally.

## Storing the secret

Base64-encode it. A multi-line raw value arrives **empty** on Windows runners —
PowerShell cannot set env vars containing newlines. Raw service-account JSON is
also accepted (detected by a leading `{`), but a serialized R token must be
base64 because it is binary.

Prefer a user OAuth token over a service account: a service account has no Drive
quota on user-owned folders, so it authenticates but cannot complete an upload
round-trip, which silently leaves those tests uncovered.

`present` is passed separately because a single-line boolean always survives the
env boundary. It is what separates "no secret configured" (quiet) from "secret
configured but dropped in transit" (warned).
