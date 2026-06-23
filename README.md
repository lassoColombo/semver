# semantic-versioning (semver)

[Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) for Nushell 

parse, validate, compare, sort, and bump versions as structured data.

---

- [Why?](#why?)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Commands](#commands)
- [Spec conformance - what is conventional anyway?](#spec-conformance---what-is-conventional-anyway?)
    - [Strict in both directions](#strict-in-both-directions)
    - [No `bump prerelease`](#no-`bump-prerelease`)
    - [Untrusted input](#untrusted-input)
- [CI/CD recipes](#ci/cd-recipes)
  - [Resolve the latest released version from git tags](#resolve-the-latest-released-version-from-git-tags)
  - [Build a pre-release tag for a non-master branch](#build-a-pre-release-tag-for-a-non-master-branch)
  - [Derive the next version from conventional commits](#derive-the-next-version-from-conventional-commits)
  - [Maintain a per-major support matrix](#maintain-a-per-major-support-matrix)
  - [Pre-release strategies](#pre-release-strategies)
    - [Bump the counter (npm `prerelease`)](#bump-the-counter-(npm-`prerelease`))
    - [Promote to the next stage](#promote-to-the-next-stage)
    - [Finalize a release](#finalize-a-release)

## Why?

Because answering questions like these is more fiddly than it should be:
- `which of these git tags is the latest release, ignoring pre-releases?`
- `does 1.0.0-rc.11 come after 1.0.0-rc.2?` (it does — but the actual sorting logic is non-trivial)
- `what's the next version, given the type of change I'm shipping?`

This module parses a version into predictable, structured data, according to the official specification, so you can answer those questions with ease and precision:

```nu
# the latest stable release
^git tag | lines
| each { str replace --regex '^v' '' }
| each {try {$in | semver decode} catch {null}}
| compact
| where {$in.prerelease | is-empty}
| semver sort | last | semver encode
# => '1.10.0'
```

---

Most of those questions get asked *inside a CI/CD pipeline*, and nushell is the right tool to answer: it has the ease of use of a shell, but also the precision of any general-purpose programming language. See the [CI/CD recipes](#cicd-recipes) for ready-to-adapt examples of use.

## Installation

```nu
# clone into one of your NU_LIB_DIRS
let dest = [($env.NU_LIB_DIRS | first) semver] | path join
git clone git@github.com:lassoColombo/semantic-versioning.git $dest

# use the module
use semver
semver decode --help
```

## Quick start

```nu
use semver

# parse → record
'1.2.3-rc.1+exp.5114' | semver decode
# => { major: 1, minor: 2, patch: 3, prerelease: [rc 1], build: [exp 5114] }

# validate without throwing
'01.2.3' | semver is-valid # => false (leading zero)

# round-trip — decode and encode are exact inverses
'1.2.3-rc.1' | semver decode | semver encode # => '1.2.3-rc.1'

# compare two versions
let prerelease = ('1.0.0-alpha' | semver decode)
let release = ('1.0.0' | semver decode)
$prerelease | semver compare $release
# => -1   (prerelease ranks below release)

# sort a list — decode/encode broadcast over lists, so no `each` is needed
['1.10.0' '1.2.0' '1.2.0-rc.1']
| semver decode
| semver sort
| semver encode
# => ['1.2.0-rc.1' '1.2.0' '1.10.0']

# bump
'1.2.3-rc.1+build' | semver decode | semver bump major | semver encode
# => '2.0.0'
```

## Commands

| Command | Signature | Description |
|---------|-----------|-------------|
| `semver decode` | `string -> record` / `list<string> -> list<record>` | Parse a string into a validated record. Strict: rejects any string the spec rejects. Broadcasts over lists. |
| `semver is-valid` | `string -> bool` / `list<string> -> list<bool>` | True when the string conforms to the spec BNF. Allocates no record. Broadcasts over lists. |
| `semver encode` | `record -> string` / `list<record> -> list<string>` | Render a record back to its canonical string — the exact inverse of `decode`. Strict: rejects any record that wouldn't be a spec-valid version. Broadcasts over lists. |
| `semver compare` | `record -> int` | Compares the piped record against the `other` argument. Returns `-1`, `0`, or `1` per spec rule 11. Build metadata is ignored (rule 10). |
| `semver sort` | `list<record> -> list<record>` | Sort by precedence. Pass `--reverse` for descending. |
| `semver bump major` | `record -> record` | Increment major; reset minor/patch to `0`; clear prerelease and build. |
| `semver bump minor` | `record -> record` | Increment minor; reset patch to `0`; clear prerelease and build. |
| `semver bump patch` | `record -> record` | Increment patch; clear prerelease and build. |

`decode`, `encode`, and `is-valid` broadcast: each accepts either a single value or a list and acts element-wise, so you rarely need `each`. `compare` and `bump` operate on a single record — map them with `each` (or reach for `semver sort`) when working over a collection.

## Spec conformance - what is conventional anyway?

This module adheres to [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).

#### Strict in both directions

`decode` will not accept a string the spec rejects, and `encode` will not emit one — the two are exact inverses. `$version | semver decode | semver encode` gives back the original string.

#### No `bump prerelease`

Pre-release has no conventional sape and no bump strategy: the spec fixes pre-release *format* and *ordering* but defines no progression.

If you do want a convention, [Pre-release strategies](#pre-release-strategies) collects the common ones (npm-style counter, stage promotion, finalize) as ready-to-copy recipes.

#### Untrusted input

A single non-conforming item aborts the whole pipeline, so either filter with `semver is-valid` before decoding, or catch per item:
```nu
['1.4.0' 'v1.0.0' '2.0.0-rc.1' 'latest']
| each { try {$in | semver decode} catch {null} }   # per-item try/catch: decode is strict, so guard each element
| compact
| semver sort
| semver encode
# => ['1.4.0' '2.0.0-rc.1']
```


## CI/CD recipes

### Resolve the latest released version from git tags

Read the repo's tags, keep the ones that are valid semver (stripping a leading `v`), drop pre-releases, and take the highest. This is the "what's currently in production" lookup most pipelines start from. `git tag` output that isn't a version (`nightly`, `latest`, …) is filtered out by `is-valid`, so the list can be noisy.

```nu
def latest-release []: nothing -> string {
    ^git tag
    | lines
    | each { try {$in | semver decode} catch {null} }
    | compact
    | where { $in.prerelease | is-empty }
    | semver sort
    | first
}
```

To include pre-releases (e.g. to resolve the latest release-candidate), drop the `where` command.

### Build a pre-release tag for a non-master branch

CI builds off a feature branch should not claim a clean release number. Take the latest release, bump the patch to point at the line the branch targets, then stamp the branch name into the pre-release identifiers and the short commit SHA into the build metadata.

```nu
def branch-tag [base: string, branch: string, sha: string]: nothing -> string {
    $base
    | semver decode
    | semver bump patch                          # the release line this branch is heading toward
    | merge { 
        prerelease: [($branch | str downcase | str replace --all --regex '[^0-9a-z-]+' '-')]
        build: [$sha] 
    }
    | semver encode
}

# on branch `feature/login-form`, with `1.4.2` the latest release:
branch-tag '1.4.2'
# => '1.4.3-feature-login-form+abc1234'

# the pre-release ranks below the eventual stable release, as intended
('1.4.3-feature-login-form+abc1234' | semver decode) | semver compare ('1.4.3' | semver decode)
# => -1
```

### Derive the next version from conventional commits

Pair `semver` with [`ccommit`](https://github.com/lassoColombo/conventional-commit) to compute the next tag from the commits since the last release: in this example a breaking change bumps major, a `feat` bumps minor, a `fix`/`perf`/`refactor` bumps patch.

```nu
use semver
use ccommit

# Returns the next version string, always strictly greater than `last`.
# Returns null when no release-worthy commit has landed since `last`.
def next-version [last?: string]: nothing -> any {
    let current = $last | default '0.0.0'
    let commits = (
        if ($last | is-empty) { ccommit list } else { ccommit list $last HEAD }
    ) | where conventional

    if ($commits | any {$in.breaking}) {
        $current | semver decode | semver bump major
    } else if ($commits | any {$in.type == 'feat'}) {
        $current | semver decode | semver bump minor
    } else if ($commits | any {$in.type in [fix perf refactor]}) {
        $current | semver decode | semver bump patch
    } else {
        return null   # no release-worthy change
    }
    | semver encode
}
```

### Maintain a per-major support matrix

Collapse a tag list to the highest release on each major line

```nu
def support-matrix []: nothing -> table {
    ^git tag
    | lines
    | each {|t| $t | str replace --regex '^v' '' }
    | where { semver is-valid }
    | semver decode
    | where (($in.prerelease) | is-empty)
    | group-by major
    | items {|major rows| {
        major: ($major | into int)
        latest: ($rows | semver sort --reverse | first | semver encode)
      } }
    | sort-by major
}

# => ╭───┬───────┬────────╮
#    │ # │ major │ latest │
#    ├───┼───────┼────────┤
#    │ 0 │     1 │ 1.4.3  │
#    │ 1 │     2 │ 2.1.0  │
#    ╰───┴───────┴────────╯
```

### Pre-release strategies

#### Bump the counter (npm `prerelease`)

A faithful port of `npm version prerelease [--preid <id>]`.  Increment the right-most numeric identifier; on a clean release, bump the patch and open a new series; with `--preid`, keep counting under that identifier or switch to a fresh `<id>.0`.

```nu
use semver

def bump-prerelease [--preid: string]: string -> string {
    let v = $in | semver decode
    # No pre-release yet → bump patch and open a new series. Otherwise keep the
    # core and the existing identifiers (npm drops build metadata either way).
    let base = if ($v.prerelease | is-empty) {
        $v | semver bump patch
    } else {
        $v | merge { build: [] }
    }
    # Increment the right-most numeric identifier; if there is none, append `0`.
    let pre = $base.prerelease
    let nidx = $pre | enumerate | where {|e| $e.item =~ '^[0-9]+$' } | get index
    let counted = if ($pre | is-empty) {
        ['0']
    } else if ($nidx | is-empty) {
        $pre | append '0'
    } else {
        let i = $nidx | last
        $pre | update $i (($pre | get $i | into int) + 1 | into string)
    }
    # With --preid: keep counting when the leading identifier already matches and
    # carries a number; otherwise switch to `<preid>.0`.
    let final = if ($preid | is-empty) {
        $counted
    } else if (($counted | first) == $preid) and (($counted | get 1? | default '') =~ '^[0-9]+$') {
        $counted
    } else {
        [$preid '0']
    }
    $base | merge { prerelease: $final } | semver encode
}
```

#### Promote to the next stage

Walk a maturity ladder — `alpha → beta → rc → stable` by default — resetting the counter at each step. Promoting the last stage finalizes (drops the pre-release); pass `--ladder` for your own stages.

```nu
def promote-stage [--ladder: list<string> = [alpha beta rc]]: string -> string {
    let v = $in | semver decode
    let stage = $v.prerelease | get 0? | default null
    let i = $ladder | enumerate | where item == $stage | get index | get 0?
    if ($i == null) {
        error make { msg: $"not on a known pre-release stage \(($ladder | str join ', ')); pre-release is '($v.prerelease | str join '.')'" }
    }
    if ($i == (($ladder | length) - 1)) {
        $v | merge { prerelease: [], build: [] } | semver encode   # last stage → finalize
    } else {
        $v | merge { prerelease: [($ladder | get ($i + 1)) '0'], build: [] } | semver encode
    }
}
```

#### Finalize a release

Drop the pre-release (and build metadata) to ship the stable version — the counterpart to opening one. Like npm's `release`, but idempotent: finalizing an already-stable version returns it unchanged instead of erroring.

```nu
def finalize []: string -> string {
    $in | semver decode | merge { prerelease: [], build: [] } | semver encode
}
```
