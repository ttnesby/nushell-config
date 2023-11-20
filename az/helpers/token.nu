use ../../op
use ./status.nu

# returns string '<token_type> <access_token>'
export def principal [
    --vault: string = Development
    --service_principal: string = az-cost
    --scope: string = 'https://management.azure.com/.default'
    --grant_type: string = client_credentials
] {
    ['tenant_id' 'client_id' 'client_secret']
    | op record --vault $vault --title $service_principal --relevantFields $in
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

# returns string '<token_type> <access_token>' for current user
export def main [
    --scope: string = 'https://management.azure.com/.default'
] {
    if (status).logged_in {  
        az account get-access-token --scope $scope | from json | $'($in.tokenType) ($in.accessToken)'
    } else { 
        '' 
    }
}