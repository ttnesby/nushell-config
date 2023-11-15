use std repeat
use ../ipv4

def validate [] {
  let cidr = ($in | parse '{ipv4}/{subnet}')
  let span = (metadata $cidr).span
  let validSubnet = (1..32 | each {|it| $it | into string})

  match $cidr {
    [] => {
      err -s $span -m 'invalid string' -t 'not according to {ipv4}/{subnet} pattern'
    }
    [$r] if not (($r.subnet in $validSubnet) and ($r.ipv4 | ipv4 into bits | describe) == 'string') => {
      err -s $span -m 'invalid string' -t 'in {ipv4}/{subnet}, 1 <= subnet <= 32'
    }
    _ => {$cidr.0}
  }
}

def info [] {
  let rec: record<ipv4: string, subnet: string> = $in

  let subnetSize = $rec.subnet | into int
  let ipAsSubnetSizeBits = $rec.ipv4 | ipv4 into bits | str substring 0..$subnetSize

  let networkBits = '1' | repeat $subnetSize | str join
  let noHostsBits = '0' | repeat (32 - $subnetSize) | str join
  let bCastHostsBits = '1' | repeat (32 - $subnetSize) | str join
  let firstHostBits = if $rec.subnet == '32' {''} else {('0' | repeat (32 - $subnetSize - 1) | str join) + '1'}
  let lastHostBits = if $rec.subnet == '32' {''} else {('1' | repeat (32 - $subnetSize - 1) | str join) + '0'}

  {
      subnetMask: ($networkBits + $noHostsBits | ipv4 from bits)
      networkAddress: (if $rec.subnet == '32' {'n/a'} else {($ipAsSubnetSizeBits  + $noHostsBits | ipv4 from bits)})
      broadcastAddress: (if $rec.subnet == '32' {'n/a'} else {($ipAsSubnetSizeBits + $bCastHostsBits | ipv4 from bits)})
      firstIP: ($ipAsSubnetSizeBits + $firstHostBits | ipv4 from bits)
      lastIP: ($ipAsSubnetSizeBits + $lastHostBits | ipv4 from bits)
      noOfHosts: (if $rec.subnet == '32' {1} else {(2 ** (32 - $subnetSize) - 2)})
      start: ($ipAsSubnetSizeBits  + $noHostsBits | into int -r 2)
      end: ($ipAsSubnetSizeBits + $bCastHostsBits | into int -r 2)
  }
}

# module cidr - return cidr info record
#
# single cidr
# $> '110.40.240.16/22' | cidr
#
#  #    subnetMask     networkAddress   broadcastAddress     firstIP          lastIP       noOfHosts     start         end
#  ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
#  0   255.255.252.0   110.40.240.0     110.40.243.255     110.40.240.1   110.40.243.254        1022   1848176640   1848177663
#
# multiple cidr
# $> [110.40.240.16/22 14.12.72.8/17 10.98.1.64/28] | cidr
#
#  #     subnetMask      networkAddress   broadcastAddress     firstIP          lastIP       noOfHosts     start         end
#  ───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
#  0   255.255.252.0     110.40.240.0     110.40.243.255     110.40.240.1   110.40.243.254        1022   1848176640   1848177663
#  1   255.255.255.240   10.98.1.64       10.98.1.79         10.98.1.65     10.98.1.78              14    174195008    174195023
#  2   255.255.128.0     14.12.0.0        14.12.127.255      14.12.0.1      14.12.127.254        32766    235667456    235700223
#
# https://www.ipconvertertools.com/convert-cidr-manually-binary
export def main [] {
    $in | par-each --keep-order {|it| $it | validate | info }
}