# unpin-remotes

Removes one package from the `Remotes:` field of a `DESCRIPTION`, in place. Only
the `Remotes` field is rewritten: every other byte is kept, and the step fails
if any other field's parsed value differs afterwards. The field is removed
altogether when nothing is left in it. Needs `Rscript` on the path.

The end of `Remotes` is found by DCF's own rule: a field starts on any non-empty
line that does not begin with a space or tab. So a following field such as
`Config/roxygen2/version:` is left alone.

## Usage

```yaml
- uses: PredictiveEcology/actions/unpin-remotes@main
  with:
    description: _downstream/DESCRIPTION
    package: reproducible
```

Used by `test-downstream.yaml`, which installs the package under test from the
checkout and must not let the downstream's `Remotes` pin replace it.
