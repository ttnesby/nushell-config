use ./helpers/status.nu
use ../arcbrowser

# module az - logout
export def logout [] { if (status).logged_in {az logout} }

# module az - login via browser
export def 'login browser' [
    --scope (-s): string = 'https://graph.microsoft.com/.default'   # login scope
    --arc_space: string = '@ra'                                     # which Arc browser space for navno user
] {
    let currentSpace = (arcbrowser space get | lines | get 0) # careful with system feedback, hidden LF

    arcbrowser space set --name $arc_space
    logout
    az login --scope $scope --only-show-errors --output json | from json | print $"Available subscriptions: ($in | length)"
    arcbrowser space set --name $currentSpace
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
