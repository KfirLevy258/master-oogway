# mo-brew

Homebrew helpers. Arch-aware — works against `/opt/homebrew` on Apple Silicon
and `/usr/local` on Intel without configuration.

| Command | Description |
|---------|-------------|
| `bup` | `brew update` + `upgrade` + `cleanup` in one, with a pass/fail summary |
| `bi [term]` | fuzzy-pick formulae **and** casks to install (TAB for multi-select) |
| `bun` | fuzzy-pick installed packages to uninstall (TAB for multi-select) |
| `bs <term>` | search formulae and casks; shows full `brew info` for your pick |
| `bl` | browse `brew leaves` with a dependency-tree and reverse-dependency preview |
| `bout` | list outdated packages and refresh the cached count |

## The cached outdated count

`_mo_brew_outdated_count` prints how many packages are outdated, cheaply enough
to call from a prompt. The dragon theme does not use it today — it exists so a
prompt segment can be added later without also having to solve the latency.

`brew outdated` takes seconds, so calling it on every prompt render would make
the shell unusable. Instead the count is cached and refreshed by a detached
background job at most once an hour. A cold cache reports `0` rather than
blocking or guessing, so a fresh shell is never slower than a warm one.

`bup` and `bout` clear the cache so the next call reflects reality instead of
showing a stale count until the TTL lapses.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `MO_BREW_CACHE_FILE` | `~/.config/master-oogway/brew-outdated.count` | Where the count is cached. |
| `MO_BREW_CACHE_TTL` | `3600` | Seconds before a background refresh is triggered. |

**Dependencies:** `brew` — required, plugin does not load without it.
`fzf` for `bi`, `bun`, `bs` and `bl` — checked at call time.

## On Linux

This plugin does not load on Linux — silently, since a warning on every shell
start would be noise for something that simply does not apply there. Add it to
`plugins=(…)` unconditionally; it costs nothing off-platform.
