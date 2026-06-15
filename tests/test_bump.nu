use std/assert
use std/testing *
use ../mod.nu *

@test
def "bumps major" [] {
    let r = '1.2.3-rc.1+build' | decode | bump major | encode
    assert equal $r '2.0.0'
}

@test
def "bumps minor" [] {
    let r = '1.2.3-rc.1' | decode | bump minor | encode
    assert equal $r '1.3.0'
}

@test
def "bumps patch" [] {
    let r = '1.2.3' | decode | bump patch | encode
    assert equal $r '1.2.4'
}

@test
def "bumps major from zero" [] {
    # Going 0.x.y → 1.0.0 is the canonical "release 1.0" semver moment.
    let r = '0.9.5-rc.3' | decode | bump major | encode
    assert equal $r '1.0.0'
}

@test
def "bumps patch from zero" [] {
    let r = '0.0.0' | decode | bump patch | encode
    assert equal $r '0.0.1'
}

@test
def "bumps minor resets only patch" [] {
    let r = '1.2.3' | decode | bump minor
    assert equal $r.major 1
    assert equal $r.minor 3
    assert equal $r.patch 0
}

@test
def "bumps patch preserves major and minor" [] {
    let r = '7.8.9' | decode | bump patch
    assert equal $r.major 7
    assert equal $r.minor 8
    assert equal $r.patch 10
}

@test
def "bumps major clears prerelease and build" [] {
    let r = '1.2.3-rc.1+build' | decode | bump major
    assert equal $r.prerelease []
    assert equal $r.build []
}

@test
def "bumps minor clears prerelease and build" [] {
    let r = '1.2.3-rc.1+build' | decode | bump minor
    assert equal $r.prerelease []
    assert equal $r.build []
}

@test
def "bumps patch clears prerelease and build" [] {
    let r = '1.2.3-rc.1+build' | decode | bump patch
    assert equal $r.prerelease []
    assert equal $r.build []
}
