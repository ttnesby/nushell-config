# util - fzf selection to string
def fzf-str [col: string = column1] {
    $in | fzf | each {|r| if ($r | is-empty) {''} else {$r | split column '|' | get $col | first }} | str join | str trim
}

# util - prepare a stream of two fields for fzf selection
def fzf-concat [
    col1Name: string
    col2Name: string
] {
    let data = $in
    let maxLength = $data | get $col1Name | str length | try { math max } catch { 0 }
    let col1 = $data | get $col1Name | each {|s| $"($s | fill -a l -c ' ' -w ($maxLength + 4))| " }
    let col2 = $data | get $col2Name

    $col1 | zip $col2 | each {|r| $r.0 + $r.1 } | to text
}

# gen - custom commands overview
def cco [] {
    let withType = {|data| $data | select name | merge ($data | get usage | split column ' - ' type usage)}    
    let cmd = scope commands | where is_custom == true and usage != '' and name not-in ['pwd'] | select name usage
    let ali = scope aliases | where usage != '' | select name usage
    
    do $withType $cmd | append (do $withType $ali) | group-by type | sort
}

# gen - clear
alias cls = clear

# app - ngrok as 1password plugin
alias ngrok = op plugin run -- ngrok

# app - terraform
alias tf = terraform

# util - list of git repos
def git-repos [
    --update
] {
    let master = '~/.gitrepos.ttn'
    let gitRepos = {glob /**/.git --depth 6 --no-file | path dirname | to text }

    if $update or (not ($master | path exists)) {
        do $gitRepos | save --force $master
    }    

    $master | open --raw
}

# cd - to git repo
alias gd = cd (
    git-repos 
    | fzf
    )

# cd - to terraform solution within a repo
alias td = cd (
        glob **/*.tf --depth 7 --not [**/modules/**]
        | path dirname
        | uniq
        | to text
        | fzf
        )

# gen - config files to vs code
alias cfg = code [
    ([($env.HOME),'.zshrc'] | path join),
    ($nu.env-path),
    ($nu.config-path),
]

# app - goland editor
alias gol = ~/goland

# util - convert json arrary with subscriptions (az login or az account list) to fzf selectable text
def subscription-fzf [] {
    $in | from json | where state == 'Enabled' | select name id | sort-by name | fzf-concat name id
}

# az - account set, choosing subscription with fzf
def as-az [] {
    let getAccounts = { az account list --only-show-errors --output json | subscription-fzf }
    let accounts = do $getAccounts
    let sel = if ($accounts | is-empty) { (i-az --subList) | fzf-str column2 } else { $accounts | fzf-str column2}

    if $sel != '' {
        az account set --subscription ($sel)
    }
}

# az - login
def i-az [
    scope: string = 'https://graph.microsoft.com/.default'
    --subList
    ] {
        let login = {az login --scope ($scope) --only-show-errors --output json}
        if $subList {
            do $login | subscription-fzf
        } else {
            do $login | from json | print $"Available subscriptions: ($in | length)"
        }
}

# az - logout
alias o-az = az logout