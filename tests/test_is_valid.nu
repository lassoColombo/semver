use std/assert
use std/testing *
use ../mod.nu *

@test
def "is-valid accepts canonical forms" [] {
    assert ('0.0.0' | is-valid)
    assert ('1.2.3' | is-valid)
    assert ('1.2.3-rc.1' | is-valid)
    assert ('1.2.3+exp.5114' | is-valid)
    assert ('1.2.3-rc.1+exp.5114' | is-valid)
}

@test
def "is-valid build allows leading zeros per rule 10" [] {
    assert ('1.2.3+01' | is-valid)
}

@test
def "is-valid rejects leading zero in numeric identifiers per rules 2 and 9" [] {
    assert not ('01.2.3' | is-valid)
    assert not ('1.02.3' | is-valid)
    assert not ('1.2.03' | is-valid)
    assert not ('1.2.3-01' | is-valid)
}

@test
def "is-valid rejects malformed strings" [] {
    assert not ('' | is-valid)
    assert not ('1' | is-valid)
    assert not ('1.2' | is-valid)
    assert not ('alpha' | is-valid)
    assert not ('1.2.3-' | is-valid)
    assert not ('1.2.3+' | is-valid)
    assert not ('1.2.3-rc_1' | is-valid)
}
