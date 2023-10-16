### util ################################################################################

# util - fzf selection to string
def fzf-str [col: string = column1] {
    $in | fzf | each {|r| if ($r | is-empty) {''} else {$r | split column '|' | get $col | first }} | str join | str trim
}

# util - prepare a stream of two fields for fzf selection
def fzf-concat [
    col1Name: string
    col2Name: string
] {
    let data = $in
    let maxLength = $data | get $col1Name | str length | try { math max } catch { 0 }
    let col1 = $data | get $col1Name | each {|s| $"($s | fill -a l -c ' ' -w ($maxLength + 4))| " }
    let col2 = $data | get $col2Name

    $col1 | zip $col2 | each {|r| $r.0 + $r.1 } | to text
}

# util - list of git repos
def git-repos [
    --update
] {
    let master = '~/.gitrepos.ttn'
    let gitRepos = {glob /**/.git --depth 6 --no-file | path dirname | to text }

    if $update or (not ($master | path exists)) {
        do $gitRepos | save --force $master
    }

    $master | open --raw
}

# util - convert json arrary with subscriptions (az login or az account list) to fzf selectable text
def subscription-fzf [] {
    $in | from json | where state == 'Enabled' | select name id | sort-by name | fzf-concat name id
}

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
    | do {|r| if ($r | columns ) == $relevantFields {$r} } $in
}

# util - select document record(s) from vault
def docs-record-op [
    --vault (-v): string                # which vault to find documents
    --tag (-t): string                  # which tag must exist in documents
    --relevantFields (-f): list<string> # record content
    --multiSelection                    # enable fzf multi selection
] {
    let data = docs-op --vault $vault --tag $tag
    | par-each {|d| fields-op --vault $vault --title $d.title --relevantFields $relevantFields}
    | try { sort-by $relevantFields.0 }

    if ($data | is-empty) {} else {
        let postProcess = {|d| $d | to text | split row (char newline) | filter {|r| $r != ''} }

        if $multiSelection {
            $data | fzf --multi --ansi --header-lines=2 --cycle | do $postProcess $in
        } else {
            $data | fzf --ansi --header-lines=2 --cycle | do $postProcess $in
        }
    }
}

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

# cd - to git repo
def-env gd [q: string = ''] { git-repos | fzf -q $q -1 | cd $in }

# cd - to terraform solution within a repo
def-env td [] {
    glob **/*.tf --depth 7 --not [**/modules/**]
    | path dirname
    | uniq
    | to text
    | fzf
    | cd $in
}

### git ###############################################################################

# git - gently try to delete merged branches, excluding the checked out one
def gbd [] {
    git branch --merged
    | lines
    | where $it !~ '\*'
    | str trim
    | where $it != 'master' and $it != 'main'
    | each { |it| git branch -d $it }}

### ipv4 ################################################################################

# ipv4 - extract details from cidr
#
# single cidr:   '110.40.240.16/22' | cidr
# multiple cidr: [110.40.240.16/22 14.12.72.8/17 10.98.1.64/28] | cidr
def cidr [] {
    let input = $in

    use std repeat
    # https://www.ipconvertertools.com/convert-cidr-manually-binary

    let bits32ToIPv4Str = {|bits|
        [0..8, 8..16, 16..24, 24..32]
        | each {|r| $bits | str substring $r | into int -r 2 | into string }
        | str join '.'
    }

    let bits32ToInt = {|bits| $bits | into int -r 2 }

    $input | par-each {|it|
        let asRec = $it | parse '{a}.{b}.{c}.{d}/{subnet}' | first
        let subnetSize = $asRec.subnet | into int
        let ipAsSubnetSizeBits = $asRec
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
            cidr: ($it)
            subnetMask: ($networkBits + $noHostsBits | do $bits32ToIPv4Str $in)
            networkAddress: ($ipAsSubnetSizeBits  + $noHostsBits |  do $bits32ToIPv4Str $in)
            broadcastAddress: ($ipAsSubnetSizeBits + $bCastHostsBits |  do $bits32ToIPv4Str $in)
            firstIP: ($ipAsSubnetSizeBits + $firstHostBits |  do $bits32ToIPv4Str $in)
            lastIP: ($ipAsSubnetSizeBits + $lastHostBits |  do $bits32ToIPv4Str $in)
            noOfHosts: (2 ** (32 - $subnetSize) - 2)
            start: ($ipAsSubnetSizeBits  + $noHostsBits |  do $bits32ToInt $in)
            end: ($ipAsSubnetSizeBits + $bCastHostsBits |  do $bits32ToInt $in)
        }
    }
}


### op ################################################################################

# op - set environment variables in current scope based on 1Password secrets selection
def-env env-op [
    --vault (-v): string = Development  # which vault to find env var. documents
    --tag (-t): string = env_var        # which tag must exist in documents
] {
    let relevantFields = ['name' 'value']
    let envVars = docs-record-op --vault $vault --tag $tag --relevantFields $relevantFields --multiSelection
    let str2Record = {|s| $s | split row ' ' | filter {|r| $r != ''} | collect {|l| {$l.1:$"(op read $l.2)"}} }

    $envVars | par-each {|s| do $str2Record $s} | reduce -f {} {|e, acc| $acc | merge $e } | load-env
}

# op - get azure navno named ip ranges
def rng-op [] {
    op item get IP-Ranges --vault Development --format json
    | from json
    | get fields
    | where label != notesPlain
    | select label value
    | par-each {|r| {name: $r.label } | merge ($r.value | cidr) }
    | sort-by name
}

### az ################################################################################

# az - az account set, fzf selected subscription
def as-az [] {
    let getAccounts = { az account list --only-show-errors --output json | subscription-fzf }
    let accounts = do $getAccounts
    let sel = if ($accounts | is-empty) { (i-az --subList) | fzf-str column2 } else { $accounts | fzf-str column2}

    if $sel != '' {
        az account set --subscription ($sel)
    }
}

# az - az logout
def o-az [] {

    let subscriptions = az account list --output json --only-show-errors | from json
    if ($subscriptions | is-empty) {} else {az logout}
}

# az - az login via web browser
def i-az [
    --scope (-s): string = 'https://graph.microsoft.com/.default'
    --subList
    ] {
        let login = {az login --scope ($scope) --only-show-errors --output json}

        o-az
        if $subList {
            do $login | subscription-fzf
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
    let servicePrincipal = docs-record-op --vault $vault --tag $tag --relevantFields $relevantFields

    let str2Record = {|s|
        $s
        | split row ' '
        | filter {|r| $r != ''}
        | collect {|l| {
            tenant_id:$l.2,
            client_id:$"(op read $l.3)",
            client_secret:$"(op read $l.4)"
            scope: $scope
        }}
    }

    if ($servicePrincipal | is-empty) {} else {
        o-az
        $servicePrincipal
        | do $str2Record $in
        | do {|r| 
            az login --service-principal --scope $r.scope --tenant $r.tenant_id --username $r.client_id --password $r.client_secret --only-show-errors --output json 
        } $in
        | from json | print $"Available subscriptions: ($in | length)"
    }
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
    | where vnetName != []
    | flatten # networks
    | flatten # cidrs' in a network
    | sort-by subscription
}

# az - group all cidr's details by known network ranges, scoped by authenticated user
def cidr-az [] {
    let ranges = rng-op
    const unknown = 'unknown'

    vnet-az
    | par-each {|c| {subscription: $c.subscription, vnetName: $c.vnetName} | merge ($c.cidr | cidr) }
    | par-each {|c|         
        let inRange = $ranges 
            | each {|r| if $c.start >= $r.start and $c.end <= $r.end {$r.name} else {$unknown} }
            | filter {|s| $s != $unknown}
            | collect {|l| 
                if ($l | is-empty) {
                    $unknown
                } else {
                    if ($l | length) > 1 {'error'} else {$l | first}
                } 
            }

        $c | merge {range: $inRange}
    }
    | sort-by start
    | group-by range
    | sort
}