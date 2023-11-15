use std assert
use ./cidr

#[test]
def test_cidr [] {
  assert equal ( '110.40.240.16/22' | cidr) {
    subnetMask: 255.255.252.0,
    networkAddress: 110.40.240.0,
    broadcastAddress: 110.40.243.255,
    firstIP: 110.40.240.1,
    lastIP: 110.40.243.254,
    noOfHosts: 1022,
    start: 1848176640,
    end: 1848177663
  }

  assert equal ( '1.0.0.0/1' | cidr) {
    subnetMask: 128.0.0.0,
    networkAddress: 0.0.0.0,
    broadcastAddress: 127.255.255.255,
    firstIP: 0.0.0.1,
    lastIP: 127.255.255.254,
    noOfHosts: 2147483646,
    start: 0,
    end: 2147483647
  }

  assert equal ( '110.40.240.16/32' | cidr) {
    subnetMask: 255.255.255.255,
    networkAddress: n/a,
    broadcastAddress: n/a,
    firstIP: 110.40.240.16,
    lastIP: 110.40.240.16,
    noOfHosts: 1,
    start: 1848176656,
    end: 1848176656
  }
  assert equal ([110.40.240.16/22 14.12.72.8/17] | cidr) [
    {
      subnetMask: 255.255.252.0,
      networkAddress: 110.40.240.0,
      broadcastAddress: 110.40.243.255,
      firstIP: 110.40.240.1,
      lastIP: 110.40.243.254,
      noOfHosts: 1022,
      start: 1848176640,
      end: 1848177663
    },
    {
      subnetMask: 255.255.128.0,
      networkAddress: 14.12.0.0,
      broadcastAddress: 14.12.127.255,
      firstIP: 14.12.0.1,
      lastIP: 14.12.127.254,
      noOfHosts: 32766,
      start: 235667456,
      end: 235700223
    }
  ]

  # subnet out of range, the ip pattern is checked in reuse of module ipv4
  assert error {'110.40.240.16/0' | cidr}
  assert error {'110.40.240.16/33' | cidr}
  assert error {[110.40.240.16/22 14.12.72.8/0] | cidr}
}

#[test]
def test_cidr_from_int [] {
  assert equal (cidr from int -s 1848176641 -e 1848176641) 110.40.240.1/32
  assert equal (cidr from int -s 1848176640 -e 1848176895) 110.40.240.0/24

  # invalid int range, start > end
  assert error {cidr from int -s 10 -e 9}
}