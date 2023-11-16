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

# cost cache dir for download of cost CSV
def cacheDir [] {
  let cacheDir = ('~/.azcost' | path expand)
  if (not ($cacheDir | path exists)) { mkdir $cacheDir }
  $cacheDir
}

# cost cache file for download of cost CSV file
def cacheFile [
  --subscription (-s): string
  --periode (-p): string
] {
  cacheDir | path join $'($subscription)-($periode).csv'
}

# see https://learn.microsoft.com/en-us/rest/api/cost-management/generate-cost-details-report/create-operation?view=rest-cost-management-2023-08-01&tabs=HTTP

# az - download the cost CSV for subscription(s) and given periode
#
# Example:
# download cost for platform subscriptions connectivity, management, identity - for October
# $> [575a53ac-e2a1-4215-b45f-028ec4f6f2a5, 7e260459-3026-4653-b259-0347c0bb5970, 9f66c67b-a3b2-45cb-97ec-dd5017e94d89] | cost-az --periode 202310
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
    | par-each {|s|
        let url = $'https://management.azure.com/subscriptions/($s)/providers/Microsoft.CostManagement/generateDetailedCostReport?api-version=2023-08-01'
        let cacheFile = (cacheFile -s $s -p $prd)

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