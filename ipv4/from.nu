# module from - convert string of 32 bits to ipv4
export def bits [] {
  let bits = ($in | split chars)
  let span = (metadata $bits).span

  match ($bits) {
    $l if ($l | length) != 32 => {err -s $span -m 'invalid string' -t $'incorrect length ($l | length), should be 32' } 
    $l if not ($l | all {|c| $c in ['0','1']}) => {err -s $span -m 'invalid string' -t 'contains invalid char, not 0 or 1' } 
    _ => {}
  }

  [0..7, 8..15, 16..23, 24..31]
  | par-each --keep-order {|r| $bits | range $r | str join | into int -r 2 | into string }
  | str join '.'
}

