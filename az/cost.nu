use ./helpers/cost-cache.nu
use ./helpers/token.nu

# convert periode to epoch GMT 
def "periode to epoch" [
    --periode_name(-p): string # YYYYmm, e.g. 202403
] {
    $periode_name | $in + '01' | date to-timezone GMT | into int
}

# wait while http status is 202, until another status code
def wait [
    --headers: list<string>
] {
    match $in {
        {headers: $h ,body: _ ,status: 202} => {
            let waitUrl = ($h.response | where name == location | get 0.value)
            let retryAfter = ($h.response | where name == retry-after | get 0.value) | into int | into duration --unit sec

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

# see https://learn.microsoft.com/en-us/rest/api/cost-management/generate-cost-details-report/create-operation?view=rest-cost-management-2023-08-01&tabs=HTTP

# module az/cost - download cost CSV for subscription(s) and given month periode
#
# Example:
# download cost for platform subscriptions connectivity, management, identity - for October
# $> [575a53ac-e2a1-4215-b45f-028ec4f6f2a5, 7e260459-3026-4653-b259-0347c0bb5970, 9f66c67b-a3b2-45cb-97ec-dd5017e94d89] | az cost --periode 202310
export def main [
    --token(-t): string = ''            # see token-az | token-sp-az
    --periode(-p): string = ''          # YYYYmm
    --metric(-m): string = ActualCost
] {
    let subs = $in

    let tkn = if $token == '' {token} else {$token}

    let currMonth = (date now | format date "%Y%m")
    let prd = if $periode == '' {$currMonth} else {$periode}

    let headers = [Authorization $'($tkn)' ContentType application/json]

    $subs
    | par-each --keep-order {|s|
        let url = $'https://management.azure.com/subscriptions/($s)/providers/Microsoft.CostManagement/generateDetailedCostReport?api-version=2023-08-01'
        let cacheFile = (cost-cache file -s $s -p $prd)

        if ($cacheFile | path exists) and ($prd < $currMonth) {
            {status: 0, message: 'local cache', file: $cacheFile}
        } else {
            http post --allow-errors --full --headers $headers $url ({billingPeriod: $prd, metric: $metric} | to json)
            | wait --headers $headers
            | match $in {
                {headers: $h ,body: $b ,status: 200} => {
                    match ($b.properties.downloadUrl) {
                        null => {
                            {status: 200, message: 'null downloadUrl', file: $cacheFile}
                        }
                        _ => {
                            http get ($b.properties.downloadUrl) | save --force $cacheFile
                            {status: 200, message: ok, file: $cacheFile}
                        }
                    }
                }
                {headers: _ ,body: _ ,status: 204} => {
                    '' | save --force $cacheFile
                    {status: 204, message: 'no content', file: $cacheFile}
                }
                {headers: $h ,body: $b ,status: 422} => {
                    {status: 422, message: $b.error.message, file: $cacheFile}
                }
                {headers: $h ,body: $b ,status: 429} => {
                    {status: 429, message: $b.error.message, file: $cacheFile}
                }
                {headers: $h ,body: $b ,status:$sc} => {
                    {status: $sc, message: 'unknown case', file: $cacheFile}
                }
            }
        }
    }
}

# module az/cost - download cost CSV for subscription(s) and given start - end periode
export def days [
    --token(-t): string = ''            # see token main|token principal
    --periode(-p): record<start: string, end: string> = {}
    --metric(-m): string = ActualCost
] {
    let subs = $in

    let tkn = if $token == '' {token} else {$token}

    let yesterday = {start: ((date now) - 1day | format date "%Y-%m-%d"), end: ((date now) - 1day | format date "%Y-%m-%d")}
    let prd = if $periode == {} {$yesterday} else {$periode}

    let headers = [Authorization $'($tkn)' ContentType application/json]

    $subs
    | par-each --keep-order {|s|
        let url = $'https://management.azure.com/subscriptions/($s)/providers/Microsoft.CostManagement/generateDetailedCostReport?api-version=2023-08-01'
        let cacheFile = (cost-cache file -s $s -p $'($prd.start)-($prd.end)')

        if ($cacheFile | path exists) {
            {status: 0, message: 'local cache', file: $cacheFile}
        } else {
            http post --allow-errors --full --headers $headers $url ({timePeriod: $prd, metric: $metric} | to json)
            | wait --headers $headers
            | match $in {
                {headers: $h ,body: $b ,status: 200} => {
                    match ($b.properties.downloadUrl) {
                        null => {
                            {status: 200, message: 'null downloadUrl', file: $cacheFile}
                        }
                        _ => {
                            http get ($b.properties.downloadUrl) | save --force $cacheFile
                            {status: 200, message: ok, file: $cacheFile}
                        }
                    }
                }
                {headers: _ ,body: _ ,status: 204} => {
                    '' | save --force $cacheFile
                    {status: 204, message: 'no content', file: $cacheFile}
                }
                {headers: $h ,body: $b ,status: 422} => {
                    {status: 422, message: $b.error.message, file: $cacheFile}
                }
                {headers: $h ,body: $b ,status: 429} => {
                    {status: 429, message: $b.error.message, file: $cacheFile}
                }
                {headers: $h ,body: $b ,status:$sc} => {
                    {status: $sc, message: 'unknown case', file: $cacheFile}
                }
            }
        }
    }
}

# module az/cost - get valid billing periods for subscription(s)
# see details - https://learn.microsoft.com/en-us/rest/api/consumption/#getting-list-of-billing-periods
#
# examples:
#
# ex1 - get all subscriptions with at least one valid billing periode
#
# az cost billing periods
# | where status == 200 and ($it.billing_periods | length) > 0
#
# ex2 - get all subscriptions of invalid type (CSP...)
#
# az cost billing periods
# | where status == 400
#
# ex3 - get all NotFound subscriptions (cancelled more than 90 days?)
#
#  az cost billing periods
# | where status == 404
#
export def "billing periods" [
    --token(-t): string = '' # see token main|token principal
] {
    ^az account list --all --only-show-errors --output json 
    | from json
    | par-each --keep-order {|sub|

        let headers = [Authorization $'(if $token == '' {token} else {$token})' ContentType application/json]
        let url = $'https://management.azure.com/subscriptions/($sub.id)/providers/Microsoft.Billing/billingPeriods?api-version=2017-04-24-preview'
        let rec = {|
            status: int,
            id: string,
            bp: list<record<name:string, start:string, end: string>>
            |
            {status: $status, id: $id, billing_periods: $bp}
        }

        http get --allow-errors --full --headers $headers $url
        | match $in {
            {headers: _ , body: _ , status: 404} => (do $rec 404 $sub.id [])
            {headers: _ , body: $b , status: 200} => (
                do $rec 200 $sub.id ($b.value | each {|p| {name: $p.name, start: $p.properties.billingPeriodStartDate, end: $p.properties.billingPeriodEndDate }})
            )
            {headers: _ , body: _ , status: $s} => (do $rec $s $sub.id [])
        }
    }
}

# module az/cost - get subscriptions having given periode as valid billing periode
export def "subscriptions for billing periode" [
    --periode_name(-p): string = ''  # YYYYmm, e.g. 202403
] {
    ^az account list --all --only-show-errors --output json 
    | from json 
    | billing periods 
    | where status == 200
    | par-each {|r| $r.billing_periods | par-each {|bp| {id: $r.id, ...$bp} } }
    | flatten
    | where name == $periode_name
}

# see https://learn.microsoft.com/en-us/rest/api/cost-management/generate-cost-details-report/create-operation?view=rest-cost-management-2023-08-01&tabs=HTTP

# module az/cost - download cost CSV for subscriptions and billing period
#
# Example:
# az cost subbscriptions for billing periode -p 202206
# | az cost details
#
export def details [
    --token(-t): string = ''            # see token-az | token-sp-az
    --metric(-m): string = ActualCost
    --chunk_size(-c): int = 1
] {
    $in
    | window $chunk_size --stride $chunk_size --remainder
    | each {|sub_chunk|
        $sub_chunk
        | par-each {|s| generateDetailedCostReport -s $s.id -p {...($s | reject id)} -t $token -m $metric } 
        | flatten
    }
    | flatten
}

def generateDetailedCostReport [
    --sub_id(-s): string
    --periode(-p): record<name:string, start:string, end: string>
    --token(-t): string
    --metric(-m): string = ActualCost
] {
    let headers = [Authorization $'(if $token == '' {token} else {$token})' ContentType application/json]
    let url = $'https://management.azure.com/subscriptions/($sub_id)/providers/Microsoft.CostManagement/generateDetailedCostReport?api-version=2023-08-01'
    let cacheFile = (cost-cache file -s $sub_id -p $periode.name)
    let rec = {|
        status: int,
        message: string
        file: string
        |
        {id: $sub_id, periode: $periode.name, status: $status, message: $message, file: $file}
    }

    if ($cacheFile | path exists) { return (do $rec 0 'local cache' $cacheFile) }

    http post --allow-errors --full --headers $headers $url ({billingPeriod: $periode.name, metric: $metric} | to json)
    | wait --headers $headers
    | match $in {
        {headers: $h ,body: $b ,status: 200} => {
            match ($b.properties.downloadUrl) {
                null => { do $rec 200 'null downloadUrl' '' }
                _ => {
                    http get ($b.properties.downloadUrl) | save --force $cacheFile
                    do $rec 200 'ok' $cacheFile
                }
            }
        }
        {headers: _ ,body: _ ,status: 204} => { do $rec 204 'no content' '' ''}
        {headers: $h ,body: $b ,status: 422} => { do $rec 422 $b.error.message '' }
        {headers: $h ,body: $b ,status: 429} => { do $rec 429 $b.error.message '' }
        {headers: $h ,body: $b ,status:$sc} => { do $rec $sc 'unknown case' '' }
    }
}