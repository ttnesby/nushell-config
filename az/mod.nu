# mod az - logout
export def out [] {
    az account list --output json --only-show-errors
    | from json
    | match $in {
        [] => { null }
        _ => { az logout }
    }
}

# mod az - login via browser
export def in [
    --scope (-s): string = 'https://graph.microsoft.com/.default'
    --subList
] {
    let login = { az login --scope $scope --only-show-errors --output json }

    out
    if $subList {
        do $login
    } else {
        do $login | from json | print $"Available subscriptions: ($in | length)"
    }
}