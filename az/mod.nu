

# util - raw subscription list to names and id's
def sub-name-id [] { $in | from json | select name id | sort-by name }

# module az - set subscription from list
def sub [
    query: string = ''  # initial fuzzy search
] {
    az account list --only-show-errors --output json
    | sub-name-id
    | match $in {
        [] => { login --subList | sub-name-id }
        $l => {$l}
    }
    | fzf-sel $query
    | match $in {
        null => { null }
        {name: _, id: $id} => { az account set --subscription $id }
    }
}

export module login.nu
export module logout.nu