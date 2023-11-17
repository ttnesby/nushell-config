use ./helpers/cost-cache.nu
use ./helpers/token.nu 

# wait for something (202), until completion (200) or another status code
def wait [
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