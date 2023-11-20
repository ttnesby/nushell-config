use ./helpers/status.nu
use ../fzf

# module az/sub - set subscription from list of available for current user
export def set [
    query: string = ''  # initial fuzzy search
] {
    status
    | match $in {
        {logged_in: false, subscriptions: _} => {return null}
        {logged_in: true, subscriptions: $subs} => {
            $subs
            | select name id 
            | sort-by name
            | fzf select $query
            | match $in {
                null => { null }
                {name: _, id: $id} => { az account set --subscription $id }
            }        
        }
    }
}

# module az/sub - get current subscription
export def main [] {
    if (status).logged_in { az account show --only-show-errors --output json | from json }
}