use ../ipv4

# module from - returns cidr representation of the int range
export def int [
    --start(-s):int   # start int
    --end(-e):int     # end int
] {

  # free range should be from network address int to next network address int
  # By adding +1 when calculating subnet, the range is more natural, netw. address to broadcast

  # NB! math floor is lazy approach, rounding down to whole math log 2 - good enough

  let free = $end - $start
  let span = (metadata $free).span

  match {free: $free, ipv4: ($start | ipv4 from int)} {
    {free: $f, ipv4: _} if $f < 0 => { err -s $span -m 'invalid range' -t $'($start) > ($end)' }
    {free: 0, ipv4: $ipv4} => {$ipv4 + '/32'}
    {free: $f, ipv4: $ipv4} => {$ipv4 + $'/(32 - (($f + 1) | math log 2 | math floor))'}
  }
}