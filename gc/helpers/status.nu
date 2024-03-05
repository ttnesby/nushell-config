# retuns record for logged in status and list of available projects
export def main [] {
    do {gcloud projects list --format=json} | complete
    | match $in {
        {stdout: $prj, stderr: _, exit_code: 0} => { {logged_in: true, projects: ($prj | from json) } }
        _ => { {logged_in: false, projects: []} }
    }    
}
