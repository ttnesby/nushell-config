use std repeat
use err

def validateBits [] {
    let bits = ($in | split chars)
    let span = (metadata $bits).span

    match ($bits) {
        $l if ($l | length) != 32 => {err -s $span -m 'invalid string' -t $'incorrect length ($l | length), should be 32' }
        $l if not ($l | all {|c| $c in ['0','1']}) => {err -s $span -m 'invalid string' -t 'contains invalid char, not 0 or 1' }
        _ => {$bits}
    }
}

def validateInt [] {
    let theInt  = $in
    let span = (metadata $theInt).span

    if ($theInt < 0 or $theInt > 4294967295) {
        err -s $span -m 'invalid int' -t $'($theInt) must be in range [0, 4294967295]'
    } else {
        $theInt
    }
}

# module ipv4/from - convert string of 32 bits to ipv4
export def bits [] {
    $in | par-each --keep-order {|s|
        [0..7, 8..15, 16..23, 24..31]
        | par-each --keep-order {|r| $s | validateBits | range $r | str join | into int -r 2 | into string }
        | str join '.'
    }
}

# module ipv4/from - convert int to ipv4
export def int [] {
    $in | par-each --keep-order {|it|
        $it
        | validateInt
        | into binary
        | split row (char space)
        | reverse
        | str join
        | match $in {
        $s if ($s | str length) < 32 => {
            ('0' | repeat (32 - ($s | str length)) | str join) + $s
        }
        $s if ($s | str length) > 32 => {
            $s | str reverse | str substring 0..31
        }
        _ => $in
        }
        | bits
    }
}
