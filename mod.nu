# Semantic Versioning utilities.
#
# Implements https://semver.org/spec/v2.0.0.html. A semver string is
# decoded into a record:
#
#   {
#     major:        int
#     minor:        int
#     patch:        int
#     prerelease:   list<string>   # dot-separated identifiers; [] when none
#     build:        list<string>   # dot-separated identifiers; [] when none
#     conventional: bool           # true when input conforms to the SemVer 2.0.0 BNF
#   }
#

# Official spec regex (named-captures form) from semver.org. 
const SEMVER_REGEX = '^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)(?:-(?P<prerelease>(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+(?P<build>[0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$'

# ---------- comparison primitives (private) ----------

# C-style comparison of integers
def cmp-int [a: int, b: int]: nothing -> int {
  if $a < $b { -1 } else if $a > $b { 1 } else { 0 }
}

# Compare two pre-release identifiers
def cmp-pre-id [a: string, b: string]: nothing -> int {
  let a_num = ($a =~ '^[0-9]+$')
  let b_num = ($b =~ '^[0-9]+$')
  if $a_num and $b_num {
    cmp-int ($a | into int) ($b | into int)
  } else if $a_num {
    -1
  } else if $b_num {
    1
  } else {
    if $a < $b { -1 } else if $a > $b { 1 } else { 0 }
  }
}

# Compare two pre-release identifier lists
def cmp-pre-list [a: list<string>, b: list<string>]: nothing -> int {
  let ae = ($a | is-empty)
  let be = ($b | is-empty)
  if $ae and $be { return 0 }
  if $ae { return 1 }
  if $be { return (-1) }
  let la = $a | length
  let lb = $b | length
  let n = [$la $lb] | math min
  let first_diff = 0..<$n
    | each {|i| cmp-pre-id ($a | get $i) ($b | get $i)}
    | where {|c| $c != 0}
    | get 0?
    | default 0
  if $first_diff != 0 { return $first_diff }
  cmp-int $la $lb
}

# ---------- single-item helpers (private) ----------

# Decode one semver string into a record. On spec-conforming input the
# record has `conventional: true`; false otherwise.
def decode-one []: string -> record {
  let v = $in
  let m = $v | parse --regex $SEMVER_REGEX
  if ($m | is-empty) {
    return { major: 0, minor: 0, patch: 0, prerelease: [], build: [], conventional: false }
  }
  let r = $m | first
  let pre = $r.prerelease? | default ''
  let bld = $r.build? | default ''
  {
    major: ($r.major | into int)
    minor: ($r.minor | into int)
    patch: ($r.patch | into int)
    prerelease: (if ($pre | is-empty) { [] } else { $pre | split row '.' })
    build: (if ($bld | is-empty) { [] } else { $bld | split row '.' })
    conventional: true
  }
}

# Render one semver record back to its canonical string form.
def encode-one []: record -> string {
  let v = $in
  let pre = if ($v.prerelease | is-empty) { '' } else { '-' + ($v.prerelease | str join '.') }
  let bld = if ($v.build | is-empty) { '' } else { '+' + ($v.build | str join '.') }
  $"($v.major).($v.minor).($v.patch)($pre)($bld)"
}

# ---------- public ----------

# Decode a semver string into a record, or a list of strings into a list of records.
@search-terms semver decode parse version
@example "core only" { '1.2.3' | semver decode } --result { major: 1, minor: 2, patch: 3, prerelease: [], build: [], conventional: true }
@example "prerelease and build" { '1.2.3-rc.1+exp.5114' | semver decode } --result { major: 1, minor: 2, patch: 3, prerelease: [rc 1], build: [exp 5114], conventional: true }
@example "list broadcasting" { ['1.2.3' '2.0.0-rc.1'] | semver decode | length } --result 2
@example "non-conventional input" { 'v1.2.3' | semver decode } --result { major: 0, minor: 0, patch: 0, prerelease: [], build: [], conventional: false }
export def decode []: [string -> record, list<string> -> list<record>] {
  let v = $in
  if (($v | describe) == 'string') {
    $v | decode-one
  } else {
    $v | each { $in | decode-one }
  }
}

# True when the piped string is a valid semver per the spec BNF.
@search-terms semver valid check
@example "valid" { '1.2.3-rc.1' | semver is-valid } --result true
@example "leading zero rejected" { '01.2.3' | semver is-valid } --result false
@example "build allows leading zeros" { '1.2.3+01' | semver is-valid } --result true
export def is-valid []: string -> bool {
  $in =~ $SEMVER_REGEX
}

# Render a semver record back to its canonical string form, or a list
# of records into a list of strings.
@search-terms semver encode format render stringify
@example "roundtrip" { '1.2.3-rc.1+exp.5114' | semver decode | semver encode } --result '1.2.3-rc.1+exp.5114'
@example "list broadcasting" { ['1.2.3' '2.0.0'] | semver decode | semver encode } --result ['1.2.3' '2.0.0']
export def encode []: [record -> string, list<record> -> list<string>] {
  let v = $in
  if (($v | describe) | str starts-with 'record') {
    $v | encode-one
  } else {
    $v | each { $in | encode-one }
  }
}

# Compare two semver records per spec.
@search-terms semver compare cmp precedence ordering
@example "patch ordering" { semver compare ('1.2.3' | semver decode) ('1.2.4' | semver decode) } --result -1
@example "prerelease ranks below release" { semver compare ('1.0.0-alpha' | semver decode) ('1.0.0' | semver decode) } --result -1
@example "build metadata ignored" { semver compare ('1.0.0+abc' | semver decode) ('1.0.0+def' | semver decode) } --result 0
export def compare [a: record, b: record]: nothing -> int {
  let c1 = cmp-int $a.major $b.major
  if $c1 != 0 { return $c1 }
  let c2 = cmp-int $a.minor $b.minor
  if $c2 != 0 { return $c2 }
  let c3 = cmp-int $a.patch $b.patch
  if $c3 != 0 { return $c3 }
  cmp-pre-list $a.prerelease $b.prerelease
}

# Sort a list of semver records by precedence.
@search-terms semver sort order rank
@example "ascending" {
  ['1.10.0' '1.2.0' '1.2.0-rc.1'] | each { semver decode } | semver sort | each { semver encode }
} --result ['1.2.0-rc.1' '1.2.0' '1.10.0']
export def sort [--reverse]: list<record> -> list<record> {
  if $reverse {
    $in | sort-by --custom {|a b| (compare $a $b) < 0} --reverse
  } else {
    $in | sort-by --custom {|a b| (compare $a $b) < 0} 
  }
}

# Increment the major number; reset minor and patch to 0 and clear
# any pre-release and build metadata.
@search-terms semver bump major increment
@example "bump major" { '1.2.3-rc.1+build' | semver decode | semver bump major | semver encode } --result '2.0.0'
export def "bump major" []: record -> record {
  let v = $in
  { major: ($v.major + 1), minor: 0, patch: 0, prerelease: [], build: [], conventional: true }
}

# Increment the minor number; reset patch to 0 and clear any
# pre-release and build metadata.
@search-terms semver bump minor increment
@example "bump minor" { '1.2.3-rc.1' | semver decode | semver bump minor | semver encode } --result '1.3.0'
export def "bump minor" []: record -> record {
  let v = $in
  { major: $v.major, minor: ($v.minor + 1), patch: 0, prerelease: [], build: [], conventional: true }
}

# Increment the patch number; clear any pre-release and build metadata.
@search-terms semver bump patch increment
@example "bump patch" { '1.2.3' | semver decode | semver bump patch | semver encode } --result '1.2.4'
export def "bump patch" []: record -> record {
  let v = $in
  { major: $v.major, minor: $v.minor, patch: ($v.patch + 1), prerelease: [], build: [], conventional: true }
}
