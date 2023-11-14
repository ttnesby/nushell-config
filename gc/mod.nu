# module gc - login
export def in [
] {
    out
    do {gcloud auth login --quiet --format=json} | complete | null
}

# module gc - gcloud auth revoke
export def out [] {
    gcloud auth list --format=json
    | from json
    | match $in {
        [] => { null }
        _ => { do { gcloud auth revoke --format=json } | complete | null }
    }
}