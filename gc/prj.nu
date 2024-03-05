use ./helpers/status.nu
use ../fzf

# module gc/prj - set project from list of available for current user
export def set [
    query: string = ''  # initial fuzzy search
] {
    status
    | match $in {
        {logged_in: false, projects: _} => {return null}
        {logged_in: true, projects: $prj} => {
            $prj
            | where lifecycleState == ACTIVE
            | select name projectId 
            | sort-by name
            | fzf select $query
            | match $in {
                null => { null }
                {name: _, projectId: $id} => { gcloud config set project $id } 
            }        
        }
    }
}

# module gc/prj - get current project
export def main [] {
    gcloud info --format=json | from json | $in.config | select account project
}