### gen ################################################################################

# gen - custom commands overview
def cco [] {
    let withType = {|data| $data | select name | merge ($data | get usage | split column ' - ' type usage)}
    let cmd = scope commands | where is_custom == true and usage != '' and name not-in ['pwd'] | select name usage
    let ali = scope aliases | where usage != '' | select name usage

    do $withType $cmd | append (do $withType $ali) | group-by type | sort
}

# gen - clear
alias cls = clear

# gen - dir content as grid, used in pwd hook
def lsg [] = { ls -as | sort-by type name -i | grid -c }

# gen - config files to vs code
alias cfg = code [
    ($nu.config-path),
    ($nu.env-path),
    ([($env.HOME),'.zshrc'] | path join),
]

# gen - overlay list
alias ol = overlay list

# gen - overlay new
alias on = overlay new

# gen - overlay use
alias ou = overlay use

# gen - overlay hide
alias oh = overlay hide

### app ################################################################################

# app - ngrok as 1password plugin
alias ngrok = op plugin run -- ngrok

# app - terraform
alias tf = terraform

# app - goland editor
alias gol = ~/goland


### cd ################################################################################

# util - list of git repos
def git-repos [
    --update
] {
    # https://www.nushell.sh/book/loading_data.html#nuon
    let master = '~/.gitrepos.nuon'
    let gitRepos = { glob /**/.git --depth 6 --no-file | path dirname | wrap git-repos }

    if $update or (not ($master | path exists)) {
        do $gitRepos | save --force $master
    }

    $master | open | get git-repos
}

# cd - to git repo
def-env gd [] { git-repos | input list -f 'search:' | cd $in }

# cd - to terraform solution within a repo
def-env td [] { glob **/*.tf --depth 7 --not [**/modules/**] | path dirname | uniq | input list -f 'search:' | cd $in }


### git ###############################################################################

# git - gently try to delete merged branches, excluding the checked out one
def gbd [branch: string = main] {
    git checkout $branch
    git pull 
    git branch --merged
    | lines
    | where $it !~ '\*'
    | str trim
    | where $it != 'master' and $it != 'main'
    | each { |it| git branch -d $it }}

### ipv4 ################################################################################

# util - generate IPV4 string from 32 bits
def bits32ToIPv4 [] {
    let bits = $in

    [0..8, 8..16, 16..24, 24..32]
    | each {|r| $bits | str substring $r | into int -r 2 | into string }
    | str join '.'
}

# ipv4 - extract details from cidr
#
# single cidr:   '110.40.240.16/22' | cidr
# multiple cidr: [110.40.240.16/22 14.12.72.8/17 10.98.1.64/28] | cidr
def cidr [] {
    let input = $in

    use std repeat
    # https://www.ipconvertertools.com/convert-cidr-manually-binary

    let bits32ToInt = {|bits| $bits | into int -r 2 }

    $input
    | parse '{a}.{b}.{c}.{d}/{subnet}'
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
        let firstHostBits = ('0' | repeat (32 - $subnetSize - 1) | str join) + '1'
        let lastHostBits = ('1' | repeat (32 - $subnetSize - 1) | str join) + '0'

        {
            cidr: (($ipAsSubnetSizeBits  + $noHostsBits |  bits32ToIPv4) + $'/($subnetSize)')
            subnetMask: ($networkBits + $noHostsBits | bits32ToIPv4)
            networkAddress: ($ipAsSubnetSizeBits  + $noHostsBits |  bits32ToIPv4)
            broadcastAddress: ($ipAsSubnetSizeBits + $bCastHostsBits |  bits32ToIPv4)
            firstIP: ($ipAsSubnetSizeBits + $firstHostBits |  bits32ToIPv4)
            lastIP: ($ipAsSubnetSizeBits + $lastHostBits |  bits32ToIPv4)
            noOfHosts: (2 ** (32 - $subnetSize) - 2)
            start: ($ipAsSubnetSizeBits  + $noHostsBits |  do $bits32ToInt $in)
            end: ($ipAsSubnetSizeBits + $bCastHostsBits |  do $bits32ToInt $in)
        }
    }
}

# util - generate CIDR details from int range, with additional sub/vnet/range context
def intRangeToCIDRDetails [
    --ref1:int                          # start int
    --ref2:int                          # end int
    --range:string                      # which known range to be used
    --text:string = '      <available>' # shown as available
] {
    let free = $ref2 - $ref1
    if $free > 0 {
        ($ref1 | into bits | split row (char space) | reverse | str join | bits32ToIPv4) + $'/(32 - ($free | math log 2 | math floor))'
        | cidr
        | first
        | do {|c| {subscription: $text, vnetName: $text} | merge $c } $in
        | do {|c| $c | merge {range: $range}} $in
    }
}


### op ################################################################################

# util - get documents with tag from vault
def docs-op [
    --vault (-v): string    # which vault to find documents
    --tag (-t): string      # which tag must exist in documents
] {
    op item list --vault $vault --format json
    | from json
    | where {|d| try { $d | get tags | $tag in $in } catch { false } }
    | select title
}

# util - extract relevant fields record from document in vault
def fields-op [
    --vault (-v): string                # which vault hosting document
    --title: string                     # document title
    --relevantFields (-f): list<string> # fields to extract
] {
    let valOrRef = {|i| if $i.type == 'CONCEALED' {$i.reference} else {$i.value}}

    op item get $title --vault $vault --format json
    | from json
    | get fields
    | where label in $relevantFields
    | reduce -f {} {|it, acc| $acc | merge {$it.label: (do $valOrRef $it)} }
    # only documents with all relevant fields
    | do {|r| if ($r | columns ) == $relevantFields {$r} } $in
}

# op - set environment variables in current scope based on 1Password secrets selection
def-env env-op [
    --vault (-v): string = Development  # which vault to find env var. documents
    --tag (-t): string = env_var        # which tag must exist in documents
] {
    let relevantFields = ['name' 'value']

    docs-op --vault $vault --tag $tag
    | par-each {|d| fields-op --vault $vault --title $d.title --relevantFields $relevantFields}
    | input list -m
    | match $in {
        '' => { return null }
        $d => { $d }
    }
    | each {|r| {$r.name:$"(op read $r.value)"} }
    | reduce -f {} {|e, acc| $acc | merge $e }
    | load-env
}

# op - get azure navno named ip ranges
def rng-op [] {
    op item get IP-Ranges --vault Development --format json
    | from json
    | get fields
    | where label != notesPlain
    | select label value
    | par-each {|r| {name: $r.label } | merge ($r.value | cidr | first) }
    | sort-by start
}

### az ################################################################################

# util - raw sub. list to names and id's
def sub-name-id [] { $in | from json | select name id | sort-by name }

# az - az account set with fzf selected subscription
def as-az [] {
    az account list --only-show-errors --output json
    | sub-name-id
    | match $in {
        [] => { i-az --subList | sub-name-id }
        $l => {$l}
    }
    | input list -f 'search:'
    | match $in {
        '' => {}
        $l => { az account set --subscription ($l).id }
    }
}

# az - az logout
def o-az [] {
    az account list --output json --only-show-errors
    | from json
    | match $in {
        [] => { null }
        _ => { az logout }
    }
}

# az - az login via web browser
def i-az [
    --scope (-s): string = 'https://graph.microsoft.com/.default'
    --subList
] {
    let login = { az login --scope $scope --only-show-errors --output json }

    o-az
    if $subList {
        do $login
    } else {
        do $login | from json | print $"Available subscriptions: ($in | length)"
    }
}

# az - az login with fzf selected service principal
def i-srv-az [
    --vault (-v): string = Development                              # which vault to find env var. documents
    --tag (-t): string = service_principal                          # which tag must exist in service principal documents
    --scope (-s): string = 'https://graph.microsoft.com/.default'   # default scope for service principal
] {
    let relevantFields = ['name' 'tenant_id' 'client_id' 'client_secret']

    docs-op --vault $vault --tag $tag
    | par-each {|d| fields-op --vault $vault --title $d.title --relevantFields $relevantFields }
    | input list -f 'search:'
    | match $in {
        '' => { return null }
        $r => {
            o-az
            az login --service-principal --scope $scope --tenant $r.tenant_id --username (op read $r.client_id) --password (op read $r.client_secret) --only-show-errors --output json
        }
    }
    | from json
    | print $"Available subscriptions: ($in | length)"
}

# az - get all cidr's, scoped by authenticated user
def vnet-az [] {
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
    | sort-by subscription
}

# az - group all cidr's details by known network ranges, scoped by authenticated user
def cidr-az [
    --group
] {
    let ranges = rng-op

    vnet-az
    | par-each {|c|
        let cidrDetails = $c.cidr | cidr | first
        let inRange = $ranges 
            | where start <= $cidrDetails.start and end >= $cidrDetails.end
            | match $in {
                [] => {'unknown'}
                [$r] => {$r.name}
                $l => { $'error - ($l | reduce -f '' {|r,acc| $acc + (char pipe) + $r.name} )'}
            }

        {subscription: $c.subscription, vnetName: $c.vnetName} 
        | merge $cidrDetails
        | merge {range: $inRange}
    }
    | sort-by -i end subscription vnetName
    | if $group { $in | group-by range | sort } else {$in}
}

# az - list all predefined network ranges with available and occupied ranges
#
# NB the last free network is invalid, just a temporary marker before fix
def r-status-az [] {
    let ranges = rng-op
    let vnetInRanges = cidr-az --group

    $vnetInRanges
    | reject unknown
    | items {|k,v|
        let range = $ranges | where name == $k | first

        $v
        | sort-by -i end subscription vnetName
        | enumerate
        | each {|r|
            if $r.index == 0 {
                intRangeToCIDRDetails --ref1 $range.start --ref2 $r.item.start --range $k
            } else {
                intRangeToCIDRDetails --ref1 (($v | (get ($r.index - 1)).end) + 1) --ref2 $r.item.start --range $k
            }
        }
        | collect {|l| intRangeToCIDRDetails --ref1 (($v | last).end + 1) --ref2 $range.end --range $k | append $l }
        | append $v | sort-by end
    }
    | flatten
    | sort-by end
    | group-by range
    | sort
}