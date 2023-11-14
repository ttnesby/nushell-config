# module cidr - return classic details
#
# single cidr
# $> '110.40.240.16/22' | ipv4 cidr info
#
#  #    subnetMask     networkAddress   broadcastAddress     firstIP          lastIP       noOfHosts     start         end
#  ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
#  0   255.255.252.0   110.40.240.0     110.40.243.255     110.40.240.1   110.40.243.254        1022   1848176640   1848177663
#
# multiple cidr
# $> [110.40.240.16/22 14.12.72.8/17 10.98.1.64/28] | ipv4 cidr info
#
#  #     subnetMask      networkAddress   broadcastAddress     firstIP          lastIP       noOfHosts     start         end
#  ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
#  0   255.255.252.0     110.40.240.0     110.40.243.255     110.40.240.1   110.40.243.254        1022   1848176640   1848177663
#  1   255.255.255.240   10.98.1.64       10.98.1.79         10.98.1.65     10.98.1.78              14    174195008    174195023
#  2   255.255.128.0     14.12.0.0        14.12.127.255      14.12.0.1      14.12.127.254        32766    235667456    235700223
#
export def info [] {
    let input = $in

    use std repeat
    # https://www.ipconvertertools.com/convert-cidr-manually-binary

    let bits32ToInt = {|bits| $bits | into int -r 2 }
    let validSubnets = (1..32 | each {|it| $it | into string})
    let validComponent = (0..255 | each {|it| $it | into string})

    $input
    | parse '{a}.{b}.{c}.{d}/{subnet}'
    | where ($it.a in $validComponent and $it.b in $validComponent and $it.c in $validComponent and $it.d in $validComponent) and subnet in $validSubnets
    | par-each {|rec|
        let subnetSize = $rec.subnet | into int
        let ipAsSubnetSizeBits = $rec
            | values
            | drop
            | each {|s| $s | into int | into bits | str substring 0..8}
            | str join
            | str substring 0..$subnetSize

        let networkBits = '1' | repeat $subnetSize | str join
        let noHostsBits = '0' | repeat (32 - $subnetSize) | str join
        let bCastHostsBits = '1' | repeat (32 - $subnetSize) | str join
        let firstHostBits = if $rec.subnet == '32' {''} else {('0' | repeat (32 - $subnetSize - 1) | str join) + '1'}
        let lastHostBits = if $rec.subnet == '32' {''} else {('1' | repeat (32 - $subnetSize - 1) | str join) + '0'}

        {
            subnetMask: ($networkBits + $noHostsBits | bits32ToIPv4)
            networkAddress: (if $rec.subnet == '32' {'n/a'} else {($ipAsSubnetSizeBits  + $noHostsBits |  bits32ToIPv4)})
            broadcastAddress: (if $rec.subnet == '32' {'n/a'} else {($ipAsSubnetSizeBits + $bCastHostsBits |  bits32ToIPv4)})
            firstIP: ($ipAsSubnetSizeBits + $firstHostBits |  bits32ToIPv4)
            lastIP: ($ipAsSubnetSizeBits + $lastHostBits |  bits32ToIPv4)
            noOfHosts: (if $rec.subnet == '32' {1} else {(2 ** (32 - $subnetSize) - 2)})
            start: ($ipAsSubnetSizeBits  + $noHostsBits |  do $bits32ToInt $in)
            end: ($ipAsSubnetSizeBits + $bCastHostsBits |  do $bits32ToInt $in)
        }
    }
}