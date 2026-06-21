use std/assert
use std/testing *
use ../mod.nu *

# ---------- valid forms ----------

@test
def "decode core only" [] {
    let r = '1.2.3' | decode
    assert equal $r { major: 1, minor: 2, patch: 3, prerelease: [], build: [] }
}

@test
def "decode all-zero version" [] {
    let r = '0.0.0' | decode
    assert equal $r { major: 0, minor: 0, patch: 0, prerelease: [], build: [] }
}

@test
def "decode multi-digit components" [] {
    let r = '10.20.30' | decode
    assert equal $r.major 10
    assert equal $r.minor 20
    assert equal $r.patch 30
}

@test
def "decode huge numeric components" [] {
    # Spec rule 2: no explicit upper bound on numeric identifiers.
    let r = '99999999999999999999.1.0' | decode
    assert equal ($r.major | describe) 'int'
}

@test
def "decode prerelease only" [] {
    let r = '1.2.3-rc.1' | decode
    assert equal $r.prerelease ['rc' '1']
    assert equal $r.build []
}

@test
def "decode build only" [] {
    let r = '1.2.3+exp.5114' | decode
    assert equal $r.prerelease []
    assert equal $r.build ['exp' '5114']
}

@test
def "decode prerelease and build" [] {
    let r = '1.2.3-rc.1+exp.5114' | decode
    assert equal $r { major: 1, minor: 2, patch: 3, prerelease: ['rc' '1'], build: ['exp' '5114'] }
}

@test
def "decode single-zero prerelease identifier is valid" [] {
    # Spec: `0` alone is a valid numeric identifier; only multi-digit leading-zero is rejected.
    let r = '1.0.0-0' | decode
    assert equal $r.prerelease ['0']
}

@test
def "decode alphanumeric identifier starting with digit" [] {
    # Spec canonical example: 1.0.0-0A.is.legal
    let r = '1.0.0-0A.is.legal' | decode
    assert equal $r.prerelease ['0A' 'is' 'legal']
}

@test
def "decode hyphen-prefixed identifier" [] {
    let r = '1.0.0--rc.1' | decode
    assert equal $r.prerelease ['-rc' '1']
}

@test
def "decode build allows leading zero" [] {
    # Spec rule 10: build identifiers permit leading zeros.
    let r = '1.2.3+01.02' | decode
    assert equal $r.build ['01' '02']
}

@test
def "decode complex spec-canonical version" [] {
    let r = '1.0.0+0.build.1-rc.10000aaa-kk-0.1' | decode
    assert equal $r.major 1
    assert equal $r.build ['0' 'build' '1-rc' '10000aaa-kk-0' '1']
}

# ---------- non-conforming forms ----------
#
# Any input rejected by the spec regex raises an error rather than
# decoding to a record.

@test
def "decode errors on leading zero in major" [] {
    assert error {|| '01.2.3' | decode }
}

@test
def "decode errors on leading zero in minor" [] {
    assert error {|| '1.02.3' | decode }
}

@test
def "decode errors on leading zero in patch" [] {
    assert error {|| '1.2.03' | decode }
}

@test
def "decode errors on leading zero in numeric prerelease" [] {
    assert error {|| '1.2.3-01' | decode }
}

@test
def "decode errors on empty prerelease section" [] {
    assert error {|| '1.2.3-' | decode }
}

@test
def "decode errors on empty prerelease identifier" [] {
    assert error {|| '1.2.3-rc..1' | decode }
}

@test
def "decode errors on empty build section" [] {
    assert error {|| '1.2.3+' | decode }
}

@test
def "decode errors on underscore in prerelease" [] {
    assert error {|| '1.2.3-rc_1' | decode }
}

@test
def "decode errors on missing patch" [] {
    assert error {|| '1.2' | decode }
}

@test
def "decode errors on missing minor and patch" [] {
    assert error {|| '1' | decode }
}

@test
def "decode errors on empty string" [] {
    assert error {|| '' | decode }
}

@test
def "decode errors on negative major" [] {
    assert error {|| '-1.0.0' | decode }
}

@test
def "decode errors on v-prefixed tag" [] {
    assert error {|| 'v1.2.3' | decode }
}

@test
def "decode errors on non-numeric junk" [] {
    assert error {|| 'not-a-version' | decode }
}

# ---------- list broadcasting ----------

@test
def "decode broadcasts over list" [] {
    let r = ['1.2.3' '2.0.0-rc.1'] | decode
    assert equal ($r | length) 2
    assert equal ($r | get 0 | get major) 1
    assert equal ($r | get 1 | get prerelease) ['rc' '1']
}

@test
def "decode on empty list returns empty list" [] {
    let r = [] | decode
    assert equal $r []
}

@test
def "decode errors on invalid item in list" [] {
    assert error {|| ['1.2.3' 'not-a-version'] | decode }
}
