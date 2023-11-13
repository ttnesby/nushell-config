### gen ################################################################################

# due to fzf-sel custom command and consistency
$env.config.table.mode = 'light'
$env.config.footer_mode = 'never'

# gen - fzf selection
def fzf-sel [
    query: string = '' # inital search
] {
    let cache = $in # NB! Assuming a table due to index, whatever record type
    # do fzf selection with intial search and return if only 1 found, returning null or the selected record
    ($cache | fzf --ansi --header-lines=2 --header-first --query $query --select-1 | lines)
    | match $in {
        [] => { return null }
        _ => {
            # key point, only get the index from the selected string
            let index = ($in | first | str trim | split row (char space) | first | into int)
            $cache | get $index
        }
    }
}

# gen - custom commands overview
def cco [] {
    let withType = {|data| $data | select name | merge ($data | get usage | split column ' - ' type usage)}
    let cmd = scope commands | where is_custom == true and usage != '' and name not-in ['pwd'] | select name usage
    let ali = scope aliases | where usage != '' | select name usage

    do $withType $cmd | append (do $withType $ali) | group-by type | sort
}

# gen - dir content as grid, used in pwd hook
def lsg [] = { ls -as | sort-by type name -i | grid -c }

# gen - config files to vs code
alias cfg = code -n [
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
    let gitRepos = { glob /**/.git --depth 6 --no-file | path dirname | wrap git-repo }

    if $update or (not ($master | path exists)) {
        do $gitRepos | save --force $master
    }

    $master | open
}

# cd - to repo root from arbitrary sub folder
def-env rr [] {
    use std repeat

    pwd                                         # current path
    | path relative-to ('~' | path expand)      # the path `below` home
    | path split                                # into a list
    | reverse                                   # reversed, current folder (deepest) is 1st elem
    | enumerate                                 # introduce index
    | each {|it|                                # check if dot-git exists somewhere upwards to home
        let dots = ('.' | repeat ($it.index + 1) | str join)
        {dots: $dots, rr: ($dots | path join '.git' | path exists)}
    }
    | where $it.rr                              # filter rr and eventually do cd with enough dots
    | match $in {
        [] => { return null }
        $l => { $l | get 0.dots | cd $in }
    }
}

# cd - to git repo
def-env gd [
    query: string = ''
] {
    git-repos | fzf-sel $query | if $in != null {cd $in.git-repo}
}

# cd - to terraform solution within a repo
def-env td [
    query: string = ''
] { 
    rr # as starting point for the glob
    glob **/*.tf --depth 10 | path dirname | uniq | wrap 'terraform-folder' | fzf-sel $query | if $in != null {cd $in.terraform-folder} 
}


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
    --text:string = ''                  # text for subscription and vnetName
] {
    let free = $ref2 - $ref1

    if $free == 0 { return }

    let cidr = ($ref1 | into bits | split row (char space) | reverse | str join | bits32ToIPv4) + $'/(32 - ($free | math log 2 | math floor))'
    let details = $cidr | cidr | first

    {subscription: $text, vnetName: $text, cidr: $cidr} | merge $details  | merge {range: $range}
}


### op ################################################################################

# util - get documents with tag from vault
def docs-op [
    --vault (-v): string    # which vault to find documents
    --tag (-t): string      # which tag must exist in documents
] {
    op item list --vault $vault --tags $tag --format json | from json | select title
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

### az ################################################################################

# util - raw sub. list to names and id's
def sub-name-id [] { $in | from json | select name id | sort-by name }

# az - az account set with selected subscription
def as-az [
    query: string = ''
] {
    az account list --only-show-errors --output json
    | sub-name-id
    | match $in {
        [] => { i-az --subList | sub-name-id }
        $l => {$l}
    }
    | fzf-sel $query
    | match $in {
        null => { null }
        {name: _, id: $id} => { az account set --subscription $id }
    }
}

# az - az account show, get current subscription
def ac-az [] {
    az account list --only-show-errors --output json
    | match $in {
        [] => { '' }
        $l => {
            az account show --only-show-errors --output json
            | from json
            | get id
        }
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

# az - az login with selected service principal
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

# az - get azure navno master ip ranges
def ip-range-az [] {
    op item get IP-Ranges --vault Development --format json
    | from json
    | get fields
    | where label != notesPlain
    | select label value
    | par-each {|r| {name: $r.label, cidr: $r.value } | merge ($r.value | cidr | first) }
    | sort-by end name
}

# util - calculate cidr details and relate to 'known' IP ranges
def vnet-details [] {
    let cidrs = $in
    let ranges = ip-range-az

    $cidrs
    | par-each {|r|
        let details = $r.cidr | cidr | first
        let inRange = $ranges
            | where start <= $details.start and end >= $details.end
            | match $in {
                [] => {'unknown'}
                [$r] => {$r.name}
                $l => { $'error - ($l | reduce -f '' {|r,acc| $acc + (char pipe) + $r.name} )'}
            }

        $r | merge $details | merge {range: $inRange}
    }
    | sort-by -i end subscription vnetName
}

# az - get all cidr's for all vnet's, scoped by authenticated user
def vnet-az [
    --details   # add cidr details for each address prefix and tag with known ip ranges
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
    | if $details { $in | vnet-details } else { $in }
}

def dfr-vnet-az [] {
    let subs = az account management-group entities list
    | from json
    | dfr into-lazy
    | dfr filter-with ((dfr col type) == /subscriptions)
    | dfr select displayName name

    $subs
    | dfr collect
    | dfr into-nu
    | par-each {|s|
        az network vnet list --subscription $s.name | from json
        | each {|vnet|
            {
                subscription: $s.displayName
                vnet: $vnet.name
                enableDdosProtection: $vnet.enableDdosProtection,
                dhcpOptions: (try { $vnet.dhcpOptions.dnsServers } catch {[]})
                virtualNetworkPeerings: ($vnet.virtualNetworkPeerings | each {|p| $p.id | path basename })
                cidr: $vnet.addressSpace.addressPrefixes
            }
        }
    }
    | flatten
    | dfr into-lazy
}

# az - status of master ip ranges, used - and available free sub ranges
#
# NB the last free network is invalid, just a temporary marker before fix
def ip-status-az [
    --only_available
] {
    let ipRanges = ip-range-az
    let cidrDetails = vnet-az --details | group-by range | sort

    $cidrDetails
    | reject unknown
    | items {|k,v|
        let r = $ipRanges | where name == $k | first

        $v
        | select start end
        # see (NB) below, the exceptions are start and end for the ip range itself
        | prepend {start: $r.start, end: ($r.start - 1)}    # prepend the ip range itself, only the start value
        | append {start: $r.end, end: $r.end}               # append the ip range itself, only the end value
        | sort-by end                                       # sort by end value
        | window 2                                          # pair-wise iteration of all start-end
        # NB - adding 1 to 0.end due to 1 in diff. between subnets,
        | where $it.0.end + 1 < $it.1.start                 # only gaps are relevant
        | each {|p| intRangeToCIDRDetails --ref1 ($p.0.end + 1)  --ref2 $p.1.start --range $k}
        | if $only_available { $in } else { $in | append $v | sort-by end}
    }
    | flatten | sort-by end | group-by range | sort
}

# az - get oauth token for a given service principal and scope
def token-sp-az [
    --vault: string = Development
    --service_principal: string = az-cost
    --scope: string = 'https://management.azure.com/.default'
    --grant_type: string = client_credentials
] {
    ['tenant_id' 'client_id' 'client_secret']
    | fields-op --vault $vault --title $service_principal --relevantFields $in
    | do {|sp|
        {
            url: $'https://login.microsoftonline.com/($sp.tenant_id)/oauth2/v2.0/token'
            client_id: (op read $sp.client_id)
            client_secret: (op read $sp.client_secret)
            grant_type: $grant_type
            scope: $scope
        }
    } $in
    | http post --content-type application/x-www-form-urlencoded $in.url ($in | reject url | url build-query)
    | $'($in.token_type) ($in.access_token)'
}

# az - get oauth token for current user, subscription and scope
def token-az [
    --scope: string = 'https://management.azure.com/.default'
] {
    az account get-access-token --scope $scope
    | from json
    | $'($in.tokenType) ($in.accessToken)'
}

# util - wait for something (202), until completion (200) or another status code
def cost-wait [
    --headers: string
] {
    match $in {
        {headers: $h ,body: _ ,status: 202} => {
            let waitUrl = ($h.response | where name == location | get 0.value)
            let retryAfter = ($h.response | where name == retry-after | get 0.value) | into int | into duration --unit sec

            print $'estimated cost complection: ($retryAfter) - waiting'

            mut r = $in
            loop {
                sleep $retryAfter
                $r = (http get --allow-errors --full --headers $headers $waitUrl)
                if $r.status != 202 { break }
            }
            $r
        }
        _ => { $in }
    }
}

# util - cost cache dir for download of cost CSV
def costCacheDir [] {
    let cacheDir = ('~/.azcost' | path expand)
    if (not ($cacheDir | path exists)) {mkdir $cacheDir }
    $cacheDir
}

# util - cost cache file for download of cost CSV file
def costCacheFile [
    --subscription(-s):string
    --periode(-p):string
] {
    costCacheDir | path join $'($subscription)-($periode).csv'
}

# see https://learn.microsoft.com/en-us/rest/api/cost-management/generate-cost-details-report/create-operation?view=rest-cost-management-2023-08-01&tabs=HTTP

# az - download the cost CSV for subscription(s) and given periode
#
# Example:
# download cost for platform subscriptions connectivity, management, identity - for October
# $> [575a53ac-e2a1-4215-b45f-028ec4f6f2a5, 7e260459-3026-4653-b259-0347c0bb5970, 9f66c67b-a3b2-45cb-97ec-dd5017e94d89] | cost-az --periode 202310
def cost-az [
    --token(-t): string = ''            # see token-az | token-sp-az
    --periode(-p): string = ''          # YYYYmm
    --metric(-m): string = ActualCost
] {
    let subs = $in

    let tkn = if $token == '' {token-az} else {$token}

    let currMonth = (date now | format date "%Y%m")
    let prd = if $periode == '' {$currMonth} else {$periode}

    let headers = [Authorization $'($tkn)' ContentType application/json]

    $subs
    | par-each {|s|
        let url = $'https://management.azure.com/subscriptions/($s)/providers/Microsoft.CostManagement/generateDetailedCostReport?api-version=2023-08-01'
        let cacheFile = (costCacheFile -s $s -p $prd)

        if ($cacheFile | path exists) and ($prd < $currMonth) {
            $cacheFile
        } else {
            http post --allow-errors --full --headers $headers $url ({billingPeriod: $prd, metric: $metric} | to json)
            | cost-wait --headers $headers
            | match $in {
                {headers: $h ,body: $b ,status: 200} => {
                    let csv = http get ($b.properties.downloadUrl)
                    $csv | save --force $cacheFile
                    $cacheFile
                }
                {headers: _ ,body: _ ,status:$sc} => { print $sc; return null}
            }
        }
    }
}

# az - download platform cost CSVs (connectivity, management, identity) for current year and months - 1
def platform-cost [] {

    let platformSubs = [575a53ac-e2a1-4215-b45f-028ec4f6f2a5, 7e260459-3026-4653-b259-0347c0bb5970, 9f66c67b-a3b2-45cb-97ec-dd5017e94d89]
    let n = date now | date to-record

    1..($n.month - 1)
    | each {|m| # not doing par-each due to rate limiting (429)
        let p = ($'($n.year)-($m)-1' | into datetime | format date "%Y%m")
        $platformSubs | par-each {|s| if not ((costCacheFile -s $s -p $p) | path exists) {$s | cost-az --periode $p} }
    }
}

def platform-trend [] {
    let platformSubs = [575a53ac-e2a1-4215-b45f-028ec4f6f2a5, 7e260459-3026-4653-b259-0347c0bb5970, 9f66c67b-a3b2-45cb-97ec-dd5017e94d89]
    let n = date now | date to-record

    # get data frames for all subscriptions and months until current month
    let dFrames = 1..($n.month - 1)
    | par-each {|m|
        let p = ($'($n.year)-($m)-1' | into datetime | format date "%Y%m")
        $platformSubs | cost-az --periode $p | par-each {|f| dfr open $f }
    }
    | flatten

    # reduce all data frames into a single frame
    let theFrame = $dFrames | skip 1 | reduce -f ($dFrames | first) {|df, acc| $df | dfr append $acc --col }

    # do some basic calculation (min, max, mean, std, sum) for platform subscriptions
    $theFrame
    | dfr with-column ($theFrame | dfr get BillingPeriodEndDate | dfr as-datetime "%m/%d/%Y" | dfr strftime '%m') --name BillingMonth
    | dfr with-column ($theFrame | dfr get BillingPeriodEndDate | dfr as-datetime "%m/%d/%Y" | dfr strftime '%Y') --name BillingYear
    | dfr group-by SubscriptionName BillingYear BillingMonth
    | dfr agg [
        (dfr col SubscriptionId | dfr first)
        (dfr col CostInBillingCurrency | dfr sum | dfr as Sum)
    ]
    | dfr sort-by SubscriptionName BillingMonth
    | dfr group-by SubscriptionName BillingYear
    | dfr agg [
        (dfr col Sum | dfr min | dfr as MonthlyMin)
        (dfr col Sum | dfr max | dfr as MonthlyMax)
        (dfr col Sum | dfr mean | dfr as MonthlyMean)
        (dfr col Sum | dfr std | dfr as MonthlyStd)
        (dfr col Sum | dfr sum | dfr as SumYear)
    ]
    | dfr sort-by SubscriptionName
}

### gcp ################################################################################

def i-gc [
] {
    o-gc
    do {gcloud auth login --quiet --format=json} | complete | null
}

# az - gcloud auth revoke
def o-gc [] {
    gcloud auth list --format=json
    | from json
    | match $in {
        [] => { null }
        _ => { do { gcloud auth revoke --format=json } | complete | null }
    }
}

## big query load 
## bq load --source_format=CSV --skip_leading_rows=1 --autodetect --format=json delta-sanctum-793:7e260459_3026_4653_b259_0347c0bb5970.cost ~/.azcost/575a53ac-e2a1-4215-b45f-028ec4f6f2a5-202310.csv