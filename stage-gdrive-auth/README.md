# stage-gdrive-auth

Decodes a `GOOGLEDRIVE_AUTH` secret holding a **user OAuth token** onto the
runner and reports its path as a step output. Does nothing and never fails when
the secret is absent — the normal case on fork PRs, where GitHub withholds
secrets.

Service-account keys are **rejected**, and that rejection fails the step. See
[Why not a service account](#why-not-a-service-account).

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
```

`GDRIVE_OAUTH_TOKEN` is the env var the R side reads; it is a path to a
serialized token, handed to `googledrive::drive_auth(token = readRDS(f))`.
Empty means the R side sees an unset var and skips, exactly as it does locally.

`GOOGLEDRIVE_AUTH` is deliberately not exported to the check step: that was the
service-account path.

## Storing the secret

Mint a token and store it base64-encoded:

```r
saveRDS(googledrive::drive_token(), "gdrive-token.rds")
```

```sh
base64 -w0 gdrive-token.rds   # paste the output as the GOOGLEDRIVE_AUTH secret
```

Base64 is required, not preferred. The token is binary, and a multi-line raw
value arrives **empty** on Windows runners because PowerShell cannot set env
vars containing newlines.

`present` is passed separately because a single-line boolean always survives the
env boundary. It is what separates "no secret configured" (quiet) from "secret
configured but dropped in transit" (warned).

## Why not a service account

A service account has no Drive quota on user-owned folders. It authenticates
cleanly and then cannot complete an upload round-trip, so upload-backed tests
report zero coverage while the job stays green. That failure went undiagnosed
for months, and under `covr` it is worse — covr neither fails the build on a
test failure nor prints a skip summary, so even a test written to fail loudly is
silent.

Rejecting the credential outright, with a failed step, is the only signal that
cannot be mistaken for "no credential configured".

## License

The scripts and documentation in this project are released under the [MIT License](LICENSE)

## Contributions

Contributions are welcome!
