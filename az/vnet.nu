use ../cidr

# add cidr info and master name for a list of azure vnets
def details [
  --master: table<name: string, cidr: string, subnetMask: string, networkAddress: string, broadcastAddress: string, firstIP: string, lastIP: string, noOfHosts: int, start: int, end: int>
] {
  let vnets = $in

  $vnets
  | par-each {|r|
      let details = $r.cidr | cidr
      let inMaster = $master
          | where start <= $details.start and end >= $details.end
          | match $in {
              [] => {'unknown'}
              [$r] => {$r.name}
              $l => { $'error - ($l | reduce -f '' {|r,acc| $acc + (char pipe) + $r.name} )'}
          }
          
      $r | merge $details | merge {master: $inMaster}
  }
  | sort-by -i end subscription vnetName
}

# module az/vnet - returns a list of vnets, scoped by authenticated user
export def list [
    --master: table<name: string, cidr: string, subnetMask: string, networkAddress: string, broadcastAddress: string, firstIP: string, lastIP: string, noOfHosts: int, start: int, end: int> = []   # cidr master, adding details to vnets
] {
  # list of subscriptions
  az account management-group entities list
  | from json
  | where type == /subscriptions
  | select displayName id name
  | par-each {|s|
      # list of networks in a subscription
      az network vnet list --subscription $s.name
      | from json
      # list of cidr's for a network
      | select name addressSpace
      | each {|v| {subscription: $s.displayName, vnetName:$v.name, cidr: $v.addressSpace.addressPrefixes} }
  }
  | flatten # networks
  | flatten # cidrs' in a network
  | sort-by subscription vnetName
  | if $master != [] { $in | details --master $master } else { $in }
}

# module az/vnet - returns a list of all vnets with used|free addresses, scoped by authenticated user
# NB the last free network is invalid, just a temporary marker
export def status [
    --master: table<name: string, cidr: string, subnetMask: string, networkAddress: string, broadcastAddress: string, firstIP: string, lastIP: string, noOfHosts: int, start: int, end: int> = []   # cidr master, adding details to vnets
    --only_available
] {
  let vnets = list --master $master | group-by master | sort

  $vnets
  | reject unknown
  | items {|k,v|
      let m = $master | where name == $k | first

      $v
      | select start end
      # see (NB) below, the exceptions are start and end for the ip range itself
      | prepend {start: $m.start, end: ($m.start - 1)}    # prepend the ip range itself, only the start value
      | append {start: $m.end, end: $m.end}               # append the ip range itself, only the end value
      | sort-by end                                       # sort by end value
      | window 2                                          # pair-wise iteration of all start-end
      | where $it.0.end + 1 < $it.1.start                 # only gaps are relevant
      | each {|p| 
        let cidr = cidr from int --start ($p.0.end + 1) --end $p.1.start
        let details = $cidr | cidr
        {subscription: '', vnetName: '', cidr: $cidr} | merge $details | merge {master: $k}
      }
      | if $only_available { $in } else { $in | append $v | sort-by end}
  }
  | flatten | sort-by end | group-by master | sort
}

## to be investgated later - ddos, peering, ...
# def dfr-vnet-az [] {
#     let subs = az account management-group entities list
#     | from json
#     | dfr into-lazy
#     | dfr filter-with ((dfr col type) == /subscriptions)
#     | dfr select displayName name

#     $subs
#     | dfr collect
#     | dfr into-nu
#     | par-each {|s|
#         az network vnet list --subscription $s.name | from json
#         | each {|vnet|
#             {
#                 subscription: $s.displayName
#                 vnet: $vnet.name
#                 enableDdosProtection: $vnet.enableDdosProtection,
#                 dhcpOptions: (try { $vnet.dhcpOptions.dnsServers } catch {[]})
#                 virtualNetworkPeerings: ($vnet.virtualNetworkPeerings | each {|p| $p.id | path basename })
#                 cidr: $vnet.addressSpace.addressPrefixes
#             }
#         }
#     }
#     | flatten
#     | dfr into-lazy
# }