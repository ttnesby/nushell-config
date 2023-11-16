export def status [] {
    az account list --output json --only-show-errors
    | from json
    | match $in {
        [] => { {logged_in: false, subscriptions: [] } }
        _ => { {logged_in: true, subscriptions: $in} }
    }    
}

