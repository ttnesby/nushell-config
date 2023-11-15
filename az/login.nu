use ../az logout

# module login - login via browser
export def browser [
    --scope (-s): string = 'https://graph.microsoft.com/.default'
    --subList
] {
    let login = { az login --scope $scope --only-show-errors --output json }

    logout
    if $subList {
        do $login
    } else {
        do $login | from json | print $"Available subscriptions: ($in | length)"
    }
}

# module login - login with selected 1Password service principals
export def principal [
    --vault (-v): string = Development                              # which vault to find env var. documents
    --tag (-t): string = service_principal                          # which tag must exist in service principal documents
    --scope (-s): string = 'https://graph.microsoft.com/.default'   # default scope for service principal
] {
    let relevantFields = ['name' 'tenant_id' 'client_id' 'client_secret']

    op titles --vault $vault --tag $tag
    | par-each {|d| op record --vault $vault --title $d.title --relevantFields $relevantFields }
    | input list -f 'search:'
    | match $in {
        '' => { return null }
        $r => {
            logout
            az login --service-principal --scope $scope --tenant $r.tenant_id --username (op read $r.client_id) --password (op read $r.client_secret) --only-show-errors --output json
        }
    }
    | from json
    | print $"Available subscriptions: ($in | length)"
}