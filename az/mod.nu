use ./helpers/status.nu
use ../op
use ../fzf

# module az - logout
export def logout [] { if (status).logged_in {az logout} }

# module az - login via browser
export def 'login browser' [
    --scope (-s): string = 'https://graph.microsoft.com/.default'   # login scope
    --arc_space: string = '@ra'                                     # which Arc browser space for navno user
    --subList                                                       # flag for returning subscription list for current user
] {
    let login = { az login --scope $scope --only-show-errors --output json }
    let activeArcSpace = osascript ($env.PCF | path expand | path join getActiveArcSpace.scpt)

    osascript ($env.PCF | path expand | path join activateArcSpace.scpt) $arc_space

    logout
    if $subList {
        do $login
    } else {
        do $login | from json | print $"Available subscriptions: ($in | length)"
    }

    osascript ($env.PCF | path expand | path join activateArcSpace.scpt) $activeArcSpace
}

# module az - login with selected 1Password service principals
export def 'login principal' [
    --vault (-v): string = Development                              # which vault to find env var. documents
    --tag (-t): string = service_principal                          # which tag must exist in service principal documents
    --scope (-s): string = 'https://graph.microsoft.com/.default'   # default scope for service principal
    --query (-q): string = ''                                       # fuzzy query
] {
    let relevantFields = ['name' 'tenant_id' 'client_id' 'client_secret']

    op titles --vault $vault --tag $tag
    | par-each {|d| op record --vault $vault --title $d.title --relevantFields $relevantFields }
    | fzf select $query
    | match $in {
        null => { return null }
        $r => {
            logout
            az login --service-principal --scope $scope --tenant $r.tenant_id --username (op read $r.client_id) --password (op read $r.client_secret) --only-show-errors --output json
        }
    }
    | from json
    | print $"Available subscriptions: ($in | length)"
}
