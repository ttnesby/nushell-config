use ./fzf
use ./op
use ./az
use ./err
use ./batch

### gen ################################################################################

# gen - custom commands overview
def cco [] {
    let withType = {|data| $data | select name | merge ($data | get usage | split column ' - ' type usage)}
    let cmd = scope commands | where type == custom and usage != '' and name not-in ['pwd'] | select name usage
    let ali = scope aliases | where usage != '' | select name usage

    do $withType $cmd | append (do $withType $ali) | sort-by type name #group-by type | sort
}

# gen - dir content as grid, used in pwd hook
def lsg [] = { ls -as | sort-by type name -i | grid -c }

# gen - config files to vs code
alias cfg = code -n ...[
    $nu.config-path,
    $nu.env-path,
    ([($env.HOME),'.zshrc'] | path join),
    ([($env.HOME),'.config','starship.toml'] | path join),
    ([($env.HOME),'.config','atuin','config.toml'] | path join),
    ([($env.HOME),'.local','share','atuin','init2.nu'] | path join),
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

# app - check for Mac OS updates
alias osu = softwareupdate -l

# app - ngrok as 1password plugin
alias ngrok = op plugin run -- ngrok

# app - terraform
alias tf = terraform

# app - goland editor
alias gol = ~/goland

# app - neovim editor
alias e = /opt/homebrew/bin/nvim

# app - do daily brew
def br [] {
    batch sub -c $'(which brew | $in.path | first)' -s ['doctor', 'update', 'upgrade', 'cleanup']
}

# app - op select service principal -q $query | az login principal
def sp [
    query: string = ''
] {
    op select service principal -q $query | az login principal
}

# app - az login browser with an selected op users
def us [
    query: string = ''
] {
    op select user -q $query | az login browser
}

### cd ################################################################################

# cd/util - list of git repos used with gd command
def git-repos [
    --update
] {
    # https://www.nushell.sh/book/loading_data.html#nuon
    let master = '~/.gitrepos.nuon'
    let gitRepos = { glob /**/.git --depth 6 --no-file | path dirname | wrap git-repo }

    if $update or (not ($master | path exists)) {
        do $gitRepos | save --force $master
    }

    $master | open
}

# cd - to repo root from arbitrary sub folder
def --env rr [] {
    use std repeat

    pwd                                         # current path
    | path relative-to ('~' | path expand)      # the path `below` home
    | path split                                # into a list
    | reverse                                   # reversed, current folder (deepest) is 1st elem
    | enumerate                                 # introduce index
    | each {|it|                                # check if dot-git exists somewhere upwards to home
        let dots = ('.' | repeat ($it.index + 1) | str join)
        {dots: $dots, rr: ($dots | path join '.git' | path exists)}
    }
    | where $it.rr                              # filter rr and eventually do cd with enough dots
    | match $in {
        [] => { return null }
        $l => { $l | get 0.dots | cd $in }
    }
}

# cd - to git repo
def --env gd [
    query: string = ''
] {
    git-repos | fzf select $query | if $in != null {cd $in.git-repo}
}

# cd - to terraform solution within a repo
def --env td [
    query: string = ''
] {
    rr # as starting point for the glob
    glob **/*.tf --depth 10 | path dirname | uniq | wrap 'terraform-folder' | fzf select $query | if $in != null {cd $in.terraform-folder}
}

### git ###############################################################################

# git - gently try to delete merged branches, excluding the checked out one
def gbd [branch: string = main] {
    git checkout $branch
    git pull
    git branch --merged
    | lines
    | where $it !~ '\*'
    | str trim
    | where $it != 'master' and $it != 'main'
    | each { |it| git branch -d $it }}

# # git - switch branch
def gb [
    query: string = ''
] {
    git branch
    | lines
    | enumerate
    | where not ($it.item | str starts-with '*')
    | match $in {
        [] => {
            print 'Current branch is the only one'
            return null
        }
        _ => $in
    }
    | par-each --keep-order {|r| {item: ($r.item | str trim)}}
    | fzf select $query
    | if $in != null {git checkout $in.item}
}
