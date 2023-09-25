# gen - custom commands overview
def cco [] {
    help commands | where category == default and command_type in [custom alias] and usage != ''
    | select name usage 
    | sort-by usage 
    | each {|e| $"(($e.name)| fill -a l -c ' ' -w 30)@($e.usage)"}
    | to text 
    | fzf | each {|r| if ($r | is-empty) {''} else {$r | split column '@' | get column1 | first }} | str join | str trim
}

# gen - clear
alias cls = clear

# app - ngrok as 1password plugin
alias ngrok = op plugin run -- ngrok

# app - terraform
alias tf = terraform

# folder - select a repo
alias gd = cd (
    glob /**/.git --depth 6 --no-file
    | path dirname
    | to text
    | fzf
)

# folder - select terraform solution within a repo
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

# az - convert json arrary with subscriptions (az login or az account list) to fzf selectable text
def subfzf_az [] {
    $in | from json | where state == 'Enabled' | select name id | each {|e| $'($e.name)@($e.id)'} | to text
}

# az - select subscription from a list of name@id
def selectSubfzf [] {
    $in | fzf | each {|r| if ($r | is-empty) {''} else {$r | split column '@' | get column2 | first }} | str join | str trim
}

# az - account set, choosing sub. with fzf
def as-az [] {
    let getAccounts = { az account list --only-show-errors --output json | subfzf_az }
    let accounts = do $getAccounts
    let sel = if ($accounts | is-empty) { (i-az --subList) | selectSubfzf } else { $accounts | selectSubfzf}

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
            do $login | subfzf_az
        } else {
            do $login | from json | print $"Available subscriptions: ($in | length)"
        }
}

# az - logout
alias o-az = az logout