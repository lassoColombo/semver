use std/assert
use std/testing *
use ../mod.nu *

@test
def "encode core only" [] {
    let s = { major: 1, minor: 2, patch: 3, prerelease: [], build: [] } | encode
    assert equal $s '1.2.3'
}

@test
def "encode all-zero version" [] {
    let s = { major: 0, minor: 0, patch: 0, prerelease: [], build: [] } | encode
    assert equal $s '0.0.0'
}

@test
def "encode prerelease only" [] {
    let s = { major: 1, minor: 2, patch: 3, prerelease: ['rc' '1'], build: [] } | encode
    assert equal $s '1.2.3-rc.1'
}

@test
def "encode build only" [] {
    let s = { major: 1, minor: 2, patch: 3, prerelease: [], build: ['exp' '5114'] } | encode
    assert equal $s '1.2.3+exp.5114'
}

@test
def "encode prerelease and build" [] {
    let s = { major: 1, minor: 2, patch: 3, prerelease: ['rc' '1'], build: ['exp' '5114'] } | encode
    assert equal $s '1.2.3-rc.1+exp.5114'
}

@test
def "encode broadcasts over list" [] {
    let s = [
        { major: 1, minor: 0, patch: 0, prerelease: [], build: [] }
        { major: 2, minor: 0, patch: 0, prerelease: ['rc' '1'], build: [] }
    ] | encode
    assert equal $s ['1.0.0' '2.0.0-rc.1']
}

@test
def "encode on empty list returns empty list" [] {
    assert equal ([] | encode) []
}

@test
def "encode is the inverse of decode for a wide range of valid versions" [] {
    let versions = [
        '0.0.0'
        '1.2.3'
        '10.20.30'
        '1.0.0-alpha'
        '1.0.0-alpha.1'
        '1.0.0-0'
        '1.0.0-0A.is.legal'
        '1.0.0--rc.1'
        '1.2.3+build.1'
        '1.2.3+01.02'
        '1.2.3-rc.1+exp.5114'
        '1.0.0+0.build.1-rc.10000aaa-kk-0.1'
    ]
    assert equal ($versions | decode | encode) $versions
}
