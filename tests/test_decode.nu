use std/assert
use std/testing *
use ../mod.nu *

# ---------- valid forms ----------

@test
def "decode core only" [] {
    let r = '1.2.3' | decode
    assert equal $r { major: 1, minor: 2, patch: 3, prerelease: [], build: [], conventional: true }
}

@test
def "decode all-zero version" [] {
    let r = '0.0.0' | decode
    assert equal $r { major: 0, minor: 0, patch: 0, prerelease: [], build: [], conventional: true }
}

@test
def "decode multi-digit components" [] {
    let r = '10.20.30' | decode
    assert equal $r.major 10
    assert equal $r.minor 20
    assert equal $r.patch 30
    assert equal $r.conventional true
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
    assert equal $r.conventional true
}

@test
def "decode build only" [] {
    let r = '1.2.3+exp.5114' | decode
    assert equal $r.prerelease []
    assert equal $r.build ['exp' '5114']
    assert equal $r.conventional true
}

@test
def "decode prerelease and build" [] {
    let r = '1.2.3-rc.1+exp.5114' | decode
    assert equal $r { major: 1, minor: 2, patch: 3, prerelease: ['rc' '1'], build: ['exp' '5114'], conventional: true }
}

@test
def "decode single-zero prerelease identifier is valid" [] {
    # Spec: `0` alone is a valid numeric identifier; only multi-digit leading-zero is rejected.
    let r = '1.0.0-0' | decode
    assert equal $r.prerelease ['0']
    assert equal $r.conventional true
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
    assert equal $r.conventional true
}

# ---------- non-conventional forms ----------
#
# Any input rejected by the spec regex decodes to the same placeholder
# record. The string itself is not preserved; callers that care about
# the original should keep it separately.

const PLACEHOLDER = { major: 0, minor: 0, patch: 0, prerelease: [], build: [], conventional: false }

@test
def "decode flags leading zero in major as non-conventional" [] {
    assert equal ('01.2.3' | decode) $PLACEHOLDER
}

@test
def "decode flags leading zero in minor as non-conventional" [] {
    assert equal ('1.02.3' | decode) $PLACEHOLDER
}

@test
def "decode flags leading zero in patch as non-conventional" [] {
    assert equal ('1.2.03' | decode) $PLACEHOLDER
}

@test
def "decode flags leading zero in numeric prerelease as non-conventional" [] {
    assert equal ('1.2.3-01' | decode) $PLACEHOLDER
}

@test
def "decode flags empty prerelease section as non-conventional" [] {
    assert equal ('1.2.3-' | decode) $PLACEHOLDER
}

@test
def "decode flags empty prerelease identifier as non-conventional" [] {
    assert equal ('1.2.3-rc..1' | decode) $PLACEHOLDER
}

@test
def "decode flags empty build section as non-conventional" [] {
    assert equal ('1.2.3+' | decode) $PLACEHOLDER
}

@test
def "decode flags underscore in prerelease as non-conventional" [] {
    assert equal ('1.2.3-rc_1' | decode) $PLACEHOLDER
}

@test
def "decode flags missing patch as non-conventional" [] {
    assert equal ('1.2' | decode) $PLACEHOLDER
}

@test
def "decode flags missing minor and patch as non-conventional" [] {
    assert equal ('1' | decode) $PLACEHOLDER
}

@test
def "decode flags empty string as non-conventional" [] {
    assert equal ('' | decode) $PLACEHOLDER
}

@test
def "decode flags negative major as non-conventional" [] {
    assert equal ('-1.0.0' | decode) $PLACEHOLDER
}

@test
def "decode flags v-prefixed tag as non-conventional" [] {
    assert equal ('v1.2.3' | decode) $PLACEHOLDER
}

@test
def "decode flags non-numeric junk as non-conventional" [] {
    assert equal ('not-a-version' | decode) $PLACEHOLDER
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
def "decode tolerates invalid item in list" [] {
    let r = ['1.2.3' 'not-a-version'] | decode
    assert equal ($r | length) 2
    assert equal ($r | get 0 | get conventional) true
    assert equal ($r | get 1 | get conventional) false
}
