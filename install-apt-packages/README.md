# install-apt-packages

Installs Ubuntu system packages with `apt-get`, capped and retried, and caches
the downloaded `.deb` files between runs. A no-op off Linux.

Downloads from the Ubuntu mirror on GitHub-hosted runners sometimes crawl at
40-100 kB/s; one job spent 40 minutes in three apt rounds. With the cache, a
repeat run installs from local files and downloads nothing.

```yaml
- uses: PredictiveEcology/actions/install-apt-packages@main
  with:
    packages: libgdal-dev libudunits2-dev
```

| input | default | notes |
| --- | --- | --- |
| `packages` | required | whitespace-separated |
| `cache` | `true` | set `false` to always download |

| output | notes |
| --- | --- |
| `cache-hit` | `true` when the `.deb` files came from the cache |

The cache key is the runner OS, architecture, Ubuntu version, runner `ImageVersion`
and a hash of the sorted package list. The apt lists are saved with the `.deb`
files, so a hit needs no `apt-get update`. A cache restore or save problem never
fails the job; apt then downloads as before. If installing from the cache fails,
the action runs `apt-get update` and installs normally.

Used by `install-spatial-deps` and `setup-r-deps`.
