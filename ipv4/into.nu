use err

def validate [] {
    let ipv4 = ($in | parse '{a}.{b}.{c}.{d}')
    let span = (metadata $ipv4).span

    let validComponent = (0..255 | each {|it| $it | into string})

    match $ipv4 {
        [] => {
        err -s $span -m 'invalid string' -t 'not according to {a}.{b}.{c}.{d} pattern'
        }
        [$r] if not ($r | values | all {|it| $it in $validComponent}) => {
        err -s $span -m 'invalid string' -t 'in {a}.{b}.{c}.{d}, 0 <= a|b|c|d <= 255'
        }
        _ => {$ipv4.0}
    }
}

# module ipv4/into - convert ipv4 address to int
export def int [] {
    $in | par-each --keep-order {|it|
        $it
        | validate
        | values
        | into int
        | do {|l| $l.0 * 256 ** 3 + $l.1 * 256 ** 2 + $l.2 * 256 + $l.3} $in
    }
}

# module ipv4/into - convert ipv4 address into string of 32 bits
export def bits [] {
    $in | par-each --keep-order {|it|
        $it
        | validate
        | values
        | each {|s| $s | into int | into binary | str substring 0..7}
        | str join
    }
}
