use ./helpers/status.nu
use ../op
use ../fzf
use ../arcbrowser

# module az - logout
export def logout [] { if (status).logged_in {az logout} }

# module az - login via browser
export def 'login browser' [
    --scope (-s): string = 'https://graph.microsoft.com/.default'   # login scope
    --arc_space: string = '@ra'                                     # which Arc browser space for navno user
    --subList                                                       # flag for returning subscription list for current user
] {
    let login = { az login --scope $scope --only-show-errors --output json }
    let currentSpace = (arcbrowser space get | lines | get 0) # careful with os feedback, hidden LF

    arcbrowser space set --name $arc_space

    logout
    if $subList {
        do $login
    } else {
        do $login | from json | print $"Available subscriptions: ($in | length)"
    }

    arcbrowser space set --name $currentSpace
}

# module az - login with selected 1Password service principals
export def 'login principal' [
    --vault (-v): string = Development                              # which vault to find env var. documents
    --tag (-t): string = service_principal                          # which tag must exist in service principal documents
    --scope (-s): string = 'https://graph.microsoft.com/.default'   # login scope for service principal
    --query (-q): string = ''                                       # fuzzy query
] {
    let relevantFields = ['name' 'tenant_id' 'client_id' 'client_secret']

    op titles --vault $vault --tag $tag
    | par-each --keep-order {|d| op record --vault $vault --title $d.title --relevantFields $relevantFields }
    # only present name, rest is not required
    | match $in {
        [] => {return null}
        _ => {
            let pList = $in
            $pList
            # must present a table of records, get name is not possible due to fzf select being record oriented 
            | select name
            | fzf select $query
            | match $in {
                null => { return null }
                $aName => {
                    let r = $pList | where name == $aName.name | get 0
                    logout
                    az login --service-principal --scope $scope --tenant $r.tenant_id --username (op read $r.client_id) --password (op read $r.client_secret) --only-show-errors --output json
                }
            }
            | from json
            | print $"Available subscriptions: ($in | length)"
        }
    }
}
