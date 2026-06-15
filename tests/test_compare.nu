use std/assert
use std/testing *
use ../mod.nu *

@test
def "compare patch ordering" [] {
    assert equal (compare ('1.2.3' | decode) ('1.2.4' | decode)) (-1)
    assert equal (compare ('1.2.4' | decode) ('1.2.3' | decode)) 1
    assert equal (compare ('1.2.3' | decode) ('1.2.3' | decode)) 0
}

@test
def "compare minor outranks patch" [] {
    assert equal (compare ('1.10.0' | decode) ('1.2.99' | decode)) 1
}

@test
def "compare major outranks minor" [] {
    assert equal (compare ('2.0.0' | decode) ('1.99.99' | decode)) 1
}

@test
def "compare prerelease ranks below release per rule 11.3" [] {
    assert equal (compare ('1.0.0-alpha' | decode) ('1.0.0' | decode)) (-1)
    assert equal (compare ('1.0.0' | decode) ('1.0.0-alpha' | decode)) 1
}

@test
def "compare two non-prerelease versions are equal at prerelease step" [] {
    assert equal (compare ('1.0.0' | decode) ('1.0.0' | decode)) 0
}

@test
def "compare alphanumeric identifiers use lexical order per rule 11.4.2" [] {
    assert equal (compare ('1.0.0-alpha' | decode) ('1.0.0-beta' | decode)) (-1)
}

@test
def "compare numeric identifiers use numeric order per rule 11.4.1" [] {
    # NOT lexical: '11' > '2' numerically, not lexically
    assert equal (compare ('1.0.0-2' | decode) ('1.0.0-11' | decode)) (-1)
}

@test
def "compare numeric ranks below alphanumeric per rule 11.4.3" [] {
    assert equal (compare ('1.0.0-1' | decode) ('1.0.0-alpha' | decode)) (-1)
}

@test
def "compare longer prerelease outranks shorter when prefix equal per rule 11.4.4" [] {
    assert equal (compare ('1.0.0-alpha' | decode) ('1.0.0-alpha.1' | decode)) (-1)
}

@test
def "compare ignores build metadata per rule 10" [] {
    assert equal (compare ('1.0.0+abc' | decode) ('1.0.0+def' | decode)) 0
    assert equal (compare ('1.0.0-rc.1+abc' | decode) ('1.0.0-rc.1+xyz' | decode)) 0
}

@test
def "compare follows spec rule 11 example chain" [] {
    # https://semver.org/#spec-item-11
    # 1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.beta < 1.0.0-beta
    #   < 1.0.0-beta.2 < 1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0
    let chain = [
        '1.0.0-alpha'
        '1.0.0-alpha.1'
        '1.0.0-alpha.beta'
        '1.0.0-beta'
        '1.0.0-beta.2'
        '1.0.0-beta.11'
        '1.0.0-rc.1'
        '1.0.0'
    ]
    let pairs = 0..(($chain | length) - 2) | each {|i|
        compare ($chain | get $i | decode) ($chain | get ($i + 1) | decode)
    }
    assert equal $pairs (1..(($chain | length) - 1) | each { -1 })
}
