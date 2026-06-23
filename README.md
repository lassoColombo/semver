# semver

[Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) for Nushell - parse, validate, compare, sort, and bump versions as structured data.

1. [semver](#semver)
   1. [Why?](#why?)
   2. [Installation](#installation)
   3. [Quick start](#quick-start)
   4. [Record shape](#record-shape)
   5. [Commands](#commands)
   6. [Spec compliance](#spec-compliance)
      1. [Non-conforming input](#non-conforming-input)
   7. [CI/CD recipes](#ci/cd-recipes)
      1. [Resolve the latest released version from git tags](#resolve-the-latest-released-version-from-git-tags)
      2. [Build a pre-release tag for a non-master branch](#build-a-pre-release-tag-for-a-non-master-branch)
      3. [Derive the next version from conventional commits](#derive-the-next-version-from-conventional-commits)
      4. [Maintain a per-major support matrix](#maintain-a-per-major-support-matrix)

## Why?

If you deal with semversions a lot you end up composing the same fragile regex over and over again. Reimplementing it is tedious and prone to error.  

It wuould be nice if we could simply treat semversions as structured data. Something like this:
```nu
{
  major:      int
  minor:      int
  patch:      int
  prerelease: list<string>   # dot-separated identifiers; [] when none
  build:      list<string>   # dot-separated identifiers; [] when none
}
```

Then we could have some utility functions for sorting, comparing, and bumping
```nu
'1.2.3-rc.1+build' 
| semver decode # => {major: 1, minor: 2, patch: 3, prerelease: [rc, "1"], build: [build]}
| semver bump major # => {major: 2, minor: 0, patch: 0, prerelease: [], build: []}
| semver encode # => '2.0.0'
```

Yeah this wuould be nice.

## Installation

```nu
# clone into one of your NU_LIB_DIRS
let dest = [($env.NU_LIB_DIRS | first) semver] | path join
git clone git@github.com:lassoColombo/semver.git $dest

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

# round-trip
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

## Record shape

`semver decode` produces, and `semver encode` consumes, the following shape:

```nu
{
  major:      int
  minor:      int
  patch:      int
  prerelease: list<string>   # dot-separated identifiers; [] when none
  build:      list<string>   # dot-separated identifiers; [] when none
}
```

## Commands

| Command | Signature | Description |
|---------|-----------|-------------|
| `semver decode` | `string -> record` / `list<string> -> list<record>` | Parse a semver string. Raises an error on non-conforming input. Broadcasts over lists. |
| `semver is-valid` | `string -> bool` / `list<string> -> list<bool>` | True when the string conforms to the spec BNF. Allocates no record. Broadcasts over lists. |
| `semver encode` | `record -> string` / `list<record> -> list<string>` | Render a record back to canonical string form. Inverse of `decode`. Broadcasts over lists. |
| `semver compare` | `record -> int` | Compares the piped record against the `other` argument. Returns `-1`, `0`, or `1` per spec rule 11. Build metadata is ignored (rule 10). |
| `semver sort` | `list<record> -> list<record>` | Sort by precedence. Pass `--reverse` for descending. |
| `semver bump major` | `record -> record` | Increment major; reset minor/patch to `0`; clear prerelease and build. |
| `semver bump minor` | `record -> record` | Increment minor; reset patch to `0`; clear prerelease and build. |
| `semver bump patch` | `record -> record` | Increment patch; clear prerelease and build. |

`decode`, `encode`, and `is-valid` broadcast: each accepts either a single value or a list and acts element-wise, so you rarely need `each`. `compare` and `bump` operate on a single record — map them with `each` (or reach for `semver sort`) when working over a collection.

## Spec compliance

Parsing uses the official [SemVer 2.0.0 BNF regex](https://semver.org/spec/v2.0.0.html).

### Non-conforming input

`semver decode` is strict: a string that doesn't conform to the spec raises an error rather than producing a record. When decoding a list, a single bad item fails the whole pipeline.  
When the input is untrusted (git tags, manifest fields, user input), either guard with `semver is-valid` before decoding or against the error:
```nu
['1.4.0' 'v2' '2.0.0-rc.1' 'latest']
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
