def bits32ToIPv4 [] {
  let bits = $in

  [0..8, 8..16, 16..24, 24..32]
  | each {|r| $bits | str substring $r | into int -r 2 | into string }
  | str join '.'
}

export module cidr.nu