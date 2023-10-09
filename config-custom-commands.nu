### util ################################################################################

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

# util - convert json arrary with subscriptions (az login or az account list) to fzf selectable text
def subscription-fzf [] {
    $in | from json | where state == 'Enabled' | select name id | sort-by name | fzf-concat name id
}


### gen ################################################################################

# gen - custom commands overview
def cco [] {
    let withType = {|data| $data | select name | merge ($data | get usage | split column ' - ' type usage)}
    let cmd = scope commands | where is_custom == true and usage != '' and name not-in ['pwd'] | select name usage
    let ali = scope aliases | where usage != '' | select name usage

    do $withType $cmd | append (do $withType $ali) | group-by type | sort
}

# gen - clear
alias cls = clear

# gen - dir content as grid, used in pwd hook
def lsg [] = { ls | sort-by type name -i | grid -c }

# gen - config files to vs code
alias cfg = code [
    ($nu.config-path),
    ($nu.env-path),
    ([($env.HOME),'.zshrc'] | path join),
]

# gen - overlay list
alias ol = overlay list

# gen - overlay new
alias on = overlay new

# gen - overlay use
alias ou = overlay use

# gen - overlay hide
alias oh = overlay hide

### app ################################################################################

# app - ngrok as 1password plugin
alias ngrok = op plugin run -- ngrok

# app - terraform
alias tf = terraform

# app - goland editor
alias gol = ~/goland


### cd ################################################################################

# cd - to git repo
def-env gd [q: string = ''] { git-repos | fzf -q $q -1 | cd $in }

# cd - to terraform solution within a repo
def-env td [] {
    glob **/*.tf --depth 7 --not [**/modules/**]
    | path dirname
    | uniq
    | to text
    | fzf
    | cd $in
}


### az ################################################################################

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

### op ################################################################################

# op - set environment variables in current scope based on 1Password secrets selection
def-env env-op [
    --vault (-v): string = Development  # which vault to find env var. documents
    --tag (-t): string = env_var        # which tag must exist in env. var. documents
] {
    let docs = op item list --vault $vault --format json
        | from json
        | where {|d| try { $d | get tags | $tag in $in } catch { false } }
        | select title

    if ($docs | is-empty) {
        print $"no documents found in ($vault) with tag ($tag)"
    } else {
        let relevantFields = ['name' 'value']
        let valOrRef = {|i| if $i.type == 'CONCEALED' {$i.reference} else {$i.value}}

        let fields = {|t|
            op item get $t --vault $vault --format json
            | from json
            | get fields
            | where label in $relevantFields
            | reduce -f {} {|it, acc| $acc | merge {$it.label: (do $valOrRef $it)} }
        }

        let envVars = $docs | par-each {|d| do $fields $d.title} | sort-by name

        if ($envVars | is-empty) {
            print $"no documents in ($vault) complies with ($relevantFields)"
        } else {
            let selection = $envVars | fzf --multi --ansi --header-lines=2 --cycle | to text | split row (char newline) | filter {|r| $r != ''}

            if ($selection | is-empty) {} else {

                let str2NameValue = {|s|
                    $s
                    | split row ' '
                    | filter {|r| $r != ''}
                    | collect {|l| {$l.1:$"(op read $l.2)"}}
                }

                $selection
                | par-each {|s| do $str2NameValue $s}
                | reduce -f {} {|e, acc| $acc | merge $e }
                | load-env
            }
        }
    }
}

def-env srv-op [
    --vault (-v): string = Development          # which vault to find env var. documents
    --tag (-t): string = service_principal      # which tag must exist in service principal documents
] {
    let docs = op item list --vault $vault --format json
        | from json
        | where {|d| try { $d | get tags | $tag in $in } catch { false } }
        | select title

    if ($docs | is-empty) {
        print $"no documents found in ($vault) with tag ($tag)"
    } else {
        let relevantFields = ['name' 'tenant_id' 'client_id' 'client_secret']
        let valOrRef = {|i| if $i.type == 'CONCEALED' {$i.reference} else {$i.value}}

        let fields = {|t|
            op item get $t --vault $vault --format json
            | from json
            | get fields
            | where label in $relevantFields
            | reduce -f {} {|it, acc| $acc | merge {$it.label: (do $valOrRef $it)} }
        }

        let servicePrincipals = $docs | par-each {|d| do $fields $d.title} | sort-by name

        if ($servicePrincipals | is-empty) {
            print $"no documents in ($vault) complies with ($relevantFields)"
        } else {
            let selection = $servicePrincipals | fzf --ansi --header-lines=2 --cycle | to text | split row (char newline) | filter {|r| $r != ''}

            if ($selection | is-empty) {} else {

                let str2NameValue = {|s|
                    $s
                    | split row ' '
                    | filter {|r| $r != ''}
                    | collect {|l| {tenant_id:$l.2, client_id:$"(op read $l.3)", client_secret:$"(op read $l.4)"}}
                }

                $selection | par-each {|s| do $str2NameValue $s}
            }
        }
    }
}