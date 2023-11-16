# retuns record for logged in status and list of available subscriptions
export def main [] {
    az account list --output json --only-show-errors
    | from json
    | match $in {
        [] => { {logged_in: false, subscriptions: [] } }
        _ => { {logged_in: true, subscriptions: $in} }
    }    
}
