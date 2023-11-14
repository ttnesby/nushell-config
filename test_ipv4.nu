use std assert
use ./ipv4

#[test]
def test_from_bits [] {
  assert equal ('01101110001010001111000000010000' | ipv4 from bits) '110.40.240.16'
  # too short
  assert error {'011011100010100011110000000100' | ipv4 from bits}
  # invalid char
  assert error {'011011100010100011110000000a0000' | ipv4 from bits}
}

#[test]
def test_into_int [] {
  assert equal ('110.40.240.16' | ipv4 into int) 1848176656
  # wrong pattern
  assert error {'110,40.240' | ipv4 into int}
  # invalid component
  assert error {'110.40.256.16' | ipv4 into int}  
}
