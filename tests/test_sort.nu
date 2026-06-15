use std/assert
use std/testing *
use ../mod.nu *

@test
def "sort ascending" [] {
    let sorted = ['1.10.0' '1.2.0' '1.2.0-rc.1'] | decode | sort | encode
    assert equal $sorted ['1.2.0-rc.1' '1.2.0' '1.10.0']
}

@test
def "sort reverse" [] {
    let sorted = ['1.10.0' '1.2.0' '1.2.0-rc.1'] | decode | sort --reverse | encode
    assert equal $sorted ['1.10.0' '1.2.0' '1.2.0-rc.1']
}

@test
def "sort empty list" [] {
    assert equal ([] | sort) []
}

@test
def "sort single element" [] {
    let sorted = ['1.2.3'] | decode | sort | encode
    assert equal $sorted ['1.2.3']
}

@test
def "sort already-sorted is a fixed point" [] {
    let input = ['1.0.0' '1.1.0' '2.0.0']
    assert equal ($input | decode | sort | encode) $input
}

@test
def "sort handles duplicates" [] {
    let sorted = ['1.2.3' '1.2.3' '1.2.3'] | decode | sort | encode
    assert equal $sorted ['1.2.3' '1.2.3' '1.2.3']
}

@test
def "sort the spec rule 11 canonical chain" [] {
    let chain = [
        '1.0.0'
        '1.0.0-rc.1'
        '1.0.0-beta.11'
        '1.0.0-beta.2'
        '1.0.0-beta'
        '1.0.0-alpha.beta'
        '1.0.0-alpha.1'
        '1.0.0-alpha'
    ]
    let expected = [
        '1.0.0-alpha'
        '1.0.0-alpha.1'
        '1.0.0-alpha.beta'
        '1.0.0-beta'
        '1.0.0-beta.2'
        '1.0.0-beta.11'
        '1.0.0-rc.1'
        '1.0.0'
    ]
    assert equal ($chain | decode | sort | encode) $expected
}
