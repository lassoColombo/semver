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
      2. [Gate a production deploy to stable releases only](#gate-a-production-deploy-to-stable-releases-only)
      3. [Block a release that does not supersede the published one](#block-a-release-that-does-not-supersede-the-published-one)
      4. [Reject a malformed version before tagging](#reject-a-malformed-version-before-tagging)
      5. [Derive the next version from conventional commits](#derive-the-next-version-from-conventional-commits)
      6. [Maintain a per-major support matrix](#maintain-a-per-major-support-matrix)

## Why?

Sorting versions as strings goes wrong fast:
```nu
['1.10.0' '1.2.0' '1.2.0-rc.1'] | sort # => ['1.10.0' '1.2.0' '1.2.0-rc.1']
```

If you deal with semversions a lot you end up composing the same fragile regex over and over again. Reimplementing this is tedious.  
It wuould be nice if we could simply treat them as structured data. Something like this:

```nu
{
  major:      int
  minor:      int
  patch:      int
  prerelease: list<string>   # dot-separated identifiers; [] when none
  build:      list<string>   # dot-separated identifiers; [] when none
}
```

Then we could have some utility functions for sorting, comparison, and bumping
```nu
'1.2.3-rc.1+build' 
| semver decode # => {major: 1, minor: 2, patch: 3, prerelease: [rc, "1"], build: [build]}
| semver bump major # => {major: 2, minor: 0, patch: 0, prerelease: [], build: []}
| semver encode # => '2.0.0'

```

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
'01.2.3' | semver is-valid                       # => false (leading zero)
'1.2.3+01' | semver is-valid                     # => true  (build allows it)

# round-trip
'1.2.3-rc.1' | semver decode | semver encode
# => '1.2.3-rc.1'

# compare two versions
let prerelease = ('1.0.0-alpha' | semver decode)
let release = ('1.0.0' | semver decode)
semver compare $prerelease $release
# => -1   (prerelease ranks below release)

# sort a list
['1.10.0' '1.2.0' '1.2.0-rc.1']
| each { semver decode }
| semver sort
| each { semver encode }
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

`'<x>' | semver decode | semver encode` is a fixed point for any spec-valid input.

## Commands

| Command | Signature | Description |
|---------|-----------|-------------|
| `semver decode` | `string -> record` / `list<string> -> list<record>` | Parse a semver string. Raises an error on non-conforming input. Broadcasts over lists. |
| `semver is-valid` | `string -> bool` | True when the string conforms to the spec BNF. Header-only check that allocates no record. |
| `semver encode` | `record -> string` / `list<record> -> list<string>` | Render a record back to canonical string form. Inverse of `decode`. |
| `semver compare` | `record record -> int` | Returns `-1`, `0`, or `1` per spec rule 11. Build metadata is ignored (rule 10). |
| `semver sort` | `list<record> -> list<record>` | Sort by precedence. Pass `--reverse` for descending. |
| `semver bump major` | `record -> record` | Increment major; reset minor/patch to `0`; clear prerelease and build. |
| `semver bump minor` | `record -> record` | Increment minor; reset patch to `0`; clear prerelease and build. |
| `semver bump patch` | `record -> record` | Increment patch; clear prerelease and build. |

## Spec compliance

Parsing uses the official [SemVer 2.0.0 BNF regex](https://semver.org/spec/v2.0.0.html).

### Non-conforming input

`semver decode` is strict: a string that doesn't conform to the spec raises an error rather than producing a record. When decoding a list, a single bad item fails the whole pipeline.

```nu
'v1.2.3' | semver decode
# => Error: not a valid semver string: 'v1.2.3'
```

When the input is untrusted (git tags, manifest fields, user input), either guard with `semver is-valid` before decoding or guard against the error:
```nu
['1.4.0' 'v2' '2.0.0-rc.1' 'latest']
| each { try {$in | semver decode} catch {null} }
| compact
| semver sort
| each { semver encode }
# => ['1.4.0' '2.0.0-rc.1']
```

## CI/CD recipes

These compose `semver` with `git` to cover the version-management chores a release pipeline runs into. They're written as plain functions you can drop into a Nushell script step.

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

### Derive the next version from conventional commits

Pair `semver` with [`ccommit`](https://github.com/lassoColombo/conventional-commit) to compute the next tag from the commits since the last release: a breaking change bumps major, a `feat` bumps minor, a `fix`/`perf`/`refactor` bumps patch.

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

Collapse a tag list to the highest release on each major line - the set of versions a project still supports / publishes docs for.

```nu
def support-matrix []: nothing -> table {
    ^git tag
    | lines
    | each {|t| $t | str replace --regex '^v' '' }
    | where { semver is-valid }
    | each { semver decode }
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
