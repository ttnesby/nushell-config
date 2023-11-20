use ../arcbrowser

# module gc - login
export def 'login browser' [
    --arc_space: string = '@me' # which Arc browser space for navno user    
] {
    let currentSpace = (arcbrowser space get | lines | get 0) # careful with system feedback, hidden LF

    arcbrowser space set --name $arc_space
    logout
    do {gcloud auth login --quiet --format=json} | complete | null
    arcbrowser space set --name $currentSpace
}

# module gc - gcloud auth revoke
export def logout [] {
    gcloud auth list --format=json
    | from json
    | match $in {
        [] => { null }
        _ => { do { gcloud auth revoke --format=json } | complete | null }
    }
}