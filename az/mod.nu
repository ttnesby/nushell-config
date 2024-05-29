export module ./mgmt.nu
export module ./sub.nu
export module ./platform.nu
export module ./vnet.nu

use ./helpers/status.nu
use ../arcbrowser

# module az - logout
export def logout [] { if (status).logged_in {az logout} }

# module az - login via browser
export def 'login browser' [
    --scope (-s): string = 'https://graph.microsoft.com/.default'   # login scope
] {
    match $in {
        null => { return null }
        $user => {
            let currentSpace = (arcbrowser space get)
            arcbrowser space set --name $user.space
            logout
            az login --scope $scope --only-show-errors --output json | from json | print $"Available subscriptions: ($in | length)"
            arcbrowser space set --name $currentSpace
        }
    }
}

# module az - login with selected 1Password service principals
export def 'login principal' [
    --scope (-s): string = 'https://graph.microsoft.com/.default'   # login scope for service principal
] {
    match $in {
        null => { return null }
        {tenant_id: $tId, client_id: $cId, client_secret: $secret} => {
            logout
            az login --service-principal --scope $scope --tenant $tId --username $cId --password $secret --only-show-errors --output json
            | from json 
            | print $"Available subscriptions: ($in | length)"
        }
    }
}
