use std assert
use ./ipv4

#[test]
def test_from_bits [] {
  assert equal ('01101110001010001111000000010000' | ipv4 from bits) '110.40.240.16'
  assert equal (['01101110001010001111000000010000' '01101110001010001111000000010001'] | ipv4 from bits) [
    110.40.240.16,
    110.40.240.17
  ]

  # too short
  assert error {'011011100010100011110000000100' | ipv4 from bits}
  assert error {['01101110001010001111000000010000' '011011100010100011110000000101'] | ipv4 from bits}
  # invalid char
  assert error {'011011100010100011110000000a0000' | ipv4 from bits}
  assert error {['0110111000b010001111000000010000' '01101110001010001111000000010001'] | ipv4 from bits}
}

#[test]
def test_from_int [] {
  assert equal (0 | ipv4 from int) '0.0.0.0'
  assert equal (4294967295 | ipv4 from int) '255.255.255.255'
  assert equal (1848176656 | ipv4 from int) '110.40.240.16'
  assert equal ([0 4294967295 1848176656] | ipv4 from int) [
    0.0.0.0,
    255.255.255.255
    110.40.240.16
  ]

  # outside range
  assert error {-1 | ipv4 from int}
  assert error {4294967296 | ipv4 from int}
  assert error {[0 4294967296 1848176656] | ipv4 from int}
}

#[test]
def test_into_int [] {
  assert equal ('110.40.240.16' | ipv4 into int) 1848176656
  assert equal ([110.40.240.16 14.12.72.8 10.98.1.64] | ipv4 into int) [1848176656 235685896 174195008]

  # wrong pattern
  assert error {'110,40.240' | ipv4 into int}
  # invalid component
  assert error {'110.40.256.16' | ipv4 into int}
  assert error {[110.40.240.16 14.12.72.256 10.98.1.64] | ipv4 into int}
}

#[test]
def test_into_bits [] {
  assert equal ('110.40.240.16' | ipv4 into bits) '01101110001010001111000000010000'
  assert equal ([110.40.240.16 14.12.72.8 10.98.1.64] | ipv4 into bits) [
    '01101110001010001111000000010000',
    '00001110000011000100100000001000',
    '00001010011000100000000101000000'
  ]

  # wrong pattern
  assert error {'110,40.240' | ipv4 into bits}
  # invalid component
  assert error {'110.40.256.16' | ipv4 into bits}
  assert error {[110.40.240.16 14.12.72.8 10.98.256.64] | ipv4 into bits}
}
