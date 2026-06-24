# Semantic Versioning utilities.
#
# Implements https://semver.org/spec/v2.0.0.html. A semver string is
# decoded into a record:
# - `major`: `int`
# - `minor`: `int`
# - `patch`: `int`
# - `prerelease`: `list<string>` — dot-separated identifiers; `[]` when none
# - `build`: `list<string>` — dot-separated identifiers; `[]` when none
#
# Decoding a string that does not conform to the spec raises an error. The
# record-consuming commands (encode, compare, bump) likewise raise a
# descriptive error — showing the expected shape — when handed anything that
# is not a well-formed semver record: a non-record, a missing required field,
# or a field of the wrong type (major/minor/patch must be non-negative ints;
# prerelease/build must be lists of strings). `encode` is stricter still — it
# rejects a record whose identifiers would not render to a spec-conforming
# string, so it stays a true inverse of `decode`.


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

# Decode one semver string into a record. Raises an error when the input
# does not conform to the SemVer 2.0.0 spec.
def decode-one []: string -> record {
  let v = $in
  let m = $v | parse --regex $SEMVER_REGEX
  if ($m | is-empty) {
    error make { msg: $"not a valid semver string: '($v)'" }
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
  }
}

# A fully-populated example semver record exercising every field. Built via
# the decoder so it is guaranteed to match the real decoded shape, and reused
# to show the expected format in error messages.
def example-record []: nothing -> record {
  '1.2.3-rc.1+build.5' | decode-one
}

# Validate that the piped value is a semver record carrying every required
# field with the right type, returning it unchanged. Raises a descriptive
# error — showing a complete example record — when the shape is wrong. This is
# structural/type validation only (so compare and bump never trip over a raw
# `into int` failure); encode-one additionally enforces the spec's identifier
# rules on the rendered string.
def check-record []: any -> record {
  let v = $in
  let example = example-record

  if (($v | describe) | str starts-with 'record') == false {
    error make {
      msg: $"expected a semver record, got a ($v | describe).\nexpected shape, e.g.: ($example | to nuon)"
    }
  }

  $example | columns | where {|c| $c not-in ($v | columns)}
  | if ($in | is-not-empty) {
    error make {
      msg: $"semver record is missing required field\(s\) '($in | str join "', '")'.\nexpected shape, e.g.: ($example | to nuon)"
    }
  }
  # major/minor/patch must be non-negative integers
  [major minor patch] | where {|f|
    let x = $v | get $f
    (($x | describe) != 'int') or ($x < 0)
  } | if ($in | is-not-empty) {
    error make {
      msg: $"semver record field\(s\) '($in | str join "', '")' must be a non-negative int.\nexpected shape, e.g.: ($example | to nuon)"
    }
  }
  # prerelease/build must be lists of strings
  [prerelease build] | where {|f|
    let x = $v | get $f
    (not ($x | describe | str starts-with 'list')) or (not ($x | all {|e| ($e | describe) == 'string'}))
  } | if ($in | is-not-empty) {
    error make {
      msg: $"semver record field\(s\) '($in | str join "', '")' must be a list of strings.\nexpected shape, e.g.: ($example | to nuon)"
    }
  }
  $v
}

# Render one semver record back to its canonical string form. The rendered
# string is validated against the official spec regex, so encode is a strict
# inverse of decode: a record whose identifiers violate the spec (empty,
# non-alphanumeric, or a leading-zero numeric pre-release identifier) is
# rejected rather than silently rendered into a non-conforming string.
def encode-one []: record -> string {
  let v = $in | check-record
  let pre = if ($v.prerelease | is-empty) { '' } else { '-' + ($v.prerelease | str join '.') }
  let bld = if ($v.build | is-empty) { '' } else { '+' + ($v.build | str join '.') }
  let s = $"($v.major).($v.minor).($v.patch)($pre)($bld)"
  if ($s !~ $SEMVER_REGEX) {
    error make {
      msg: $"cannot encode record into a valid semver string: would produce '($s)'"
    }
  }
  $s
}

# Apply `op` to a lone item, or broadcast it element-wise over a list or
# table. The one place the broadcasting trio (decode, is-valid, encode)
# decides "single value or many?", so the three can never drift apart.
# `describe --detailed` reports both lists and tables as 'list', so the
# table that `decode` yields is dispatched the same as a plain list.
def broadcast [op: closure]: any -> any {
  let v = $in
  if (($v | describe --detailed).type == 'list') {
    $v | each { $in | do $op }
  } else {
    $v | do $op
  }
}

# ---------- public ----------

# Decode a semver string into a record, or a list of strings into a list of
# records. Raises an error on input that does not conform to the spec.
@search-terms semver decode parse version
@example "core only" { '1.2.3' | semver decode } --result { major: 1, minor: 2, patch: 3, prerelease: [], build: [] }
@example "prerelease and build" { '1.2.3-rc.1+exp.5114' | semver decode } --result { major: 1, minor: 2, patch: 3, prerelease: [rc 1], build: [exp 5114] }
export def decode []: [string -> record, list<string> -> list<record>] {
  $in | broadcast { $in | decode-one }
}

# True when the piped string is a valid semver per the spec BNF. Broadcasts
# over a list of strings, returning one bool per element.
@search-terms semver valid check
@example "valid" { '1.2.3-rc.1' | semver is-valid } --result true
@example "leading zero rejected" { '01.2.3' | semver is-valid } --result false
@example "build allows leading zeros" { '1.2.3+01' | semver is-valid } --result true
export def is-valid []: [string -> bool, list<string> -> list<bool>] {
  $in | broadcast { $in =~ $SEMVER_REGEX }
}

# Render a semver record back to its canonical string form, or a list
# of records into a list of strings.
@search-terms semver encode format render stringify
@example "roundtrip" { '1.2.3-rc.1+exp.5114' | semver decode | semver encode } --result '1.2.3-rc.1+exp.5114'
export def encode []: [record -> string, list<record> -> list<string>] {
  $in | broadcast { $in | encode-one }
}

# Compare the piped semver record against another per spec. Returns -1 when
# the piped record sorts before `other`, 1 when after, 0 when equal.
@search-terms semver compare cmp precedence ordering
@example "patch ordering" { ('1.2.3' | semver decode) | semver compare ('1.2.4' | semver decode) } --result -1
@example "prerelease ranks below release" { ('1.0.0-alpha' | semver decode) | semver compare ('1.0.0' | semver decode) } --result -1
@example "build metadata ignored" { ('1.0.0+abc' | semver decode) | semver compare ('1.0.0+def' | semver decode) } --result 0
export def compare [
  other: record  # the semver record to compare the piped one against
]: record -> int {
  let a = $in | check-record
  let b = $other | check-record
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
export def sort [
  --reverse  # sort by descending precedence (highest first) instead of ascending
]: list<record> -> list<record> {
  if $reverse {
    $in | sort-by --custom {|a b| ($a | compare $b) < 0} --reverse
  } else {
    $in | sort-by --custom {|a b| ($a | compare $b) < 0}
  }
}

# Increment the major number; reset minor and patch to 0 and clear
# any pre-release and build metadata.
@search-terms semver bump major increment
@example "bump major" { '1.2.3-rc.1+build' | semver decode | semver bump major | semver encode } --result '2.0.0'
export def "bump major" []: record -> record {
  let v = $in | check-record
  { major: ($v.major + 1), minor: 0, patch: 0, prerelease: [], build: [] }
}

# Increment the minor number; reset patch to 0 and clear any
# pre-release and build metadata.
@search-terms semver bump minor increment
@example "bump minor" { '1.2.3-rc.1' | semver decode | semver bump minor | semver encode } --result '1.3.0'
export def "bump minor" []: record -> record {
  let v = $in | check-record
  { major: $v.major, minor: ($v.minor + 1), patch: 0, prerelease: [], build: [] }
}

# Increment the patch number; clear any pre-release and build metadata.
@search-terms semver bump patch increment
@example "bump patch" { '1.2.3' | semver decode | semver bump patch | semver encode } --result '1.2.4'
export def "bump patch" []: record -> record {
  let v = $in | check-record
  { major: $v.major, minor: $v.minor, patch: ($v.patch + 1), prerelease: [], build: [] }
}
