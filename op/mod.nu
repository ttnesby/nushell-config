# prerequiste - 1Password op client
use ./helpers/read.nu 
use ../fzf
use ../cidr

# module op - set environments from a list given by env_var documents in vault
export def --env 'set env' [
    --vault (-v): string = Development  # which vault to find documents
    --tag (-t): string = env_var        # which tag must exist in documents
] {
    read titles --vault $vault --tag $tag
    | par-each --keep-order {|d| read recordAll --vault $vault --title $d.title }
    | par-each --keep-order {|l| 
        {
            hint: ($l | where label == Hint | get 0.value)
            env_vars: (
                $l 
                | where label != Hint
                | window 2 --stride 2
                | each {|l| {($l | first | $in.value):($l | last | $in.value)}} 
                | reduce -f {} {|e, acc| $acc | merge $e }
            ) 
        }
    }
    | sort-by hint
    | match $in {
        [] => { return null }
        $list => {
            $list
            | select hint
            | fzf select
            | match $in {
                null => { return null }
                $aHint => {
                    $list
                    | where hint == $aHint.hint
                    | get 0.env_vars
                }
            }
        }
    }
    | reduce -f {} {|e, acc| $acc | merge $e }    
    | load-env
}

# module op - select service principal by service_principal documents in vault
export def 'select service principal' [
    --vault (-v): string = Development      # which vault to find env var. documents
    --tag (-t): string = service_principal  # which tag must exist in service principal documents
    --query (-q): string = ''               # fuzzy query
] {
    let fields = ['name' 'tenant_id' 'client_id' 'client_secret']
    let empty = {}

    read titles --vault $vault --tag $tag
    | par-each {|d| read recordFields --vault $vault --title $d.title --fields $fields }
    | sort-by name
    | match $in {
        [] => {return null}
        $list => {
            $list
            | select name
            | fzf select $query
            | match $in {
                null => { return null }
                $aName => { 
                    $list 
                    | where name == $aName.name 
                    | get 0 
                    | {
                        tenant_id: $in.tenant_id, 
                        client_id: (op read $in.client_id), 
                        client_secret: (op read $in.client_secret)
                    }
                }
            }
        }
    }
}

# module op - return a CIDR master, list of known network CIDR's for ip planning
export def 'cidr master' [] {
    read recordAll --vault Development --title IP-Ranges  
    | par-each {|r| {name: $r.label, cidr: $r.value } | merge ($r.value | cidr) }
    | sort-by end name
}

# module op - return a list of az login users
export def 'select user' [
    --query (-q): string = ''
] {
    read recordAll --vault Development --title AZ-Login-Users
    | par-each {|r| {name: $r.label, space: $r.value } }
    | sort-by name
    | fzf select $query
    | match $in {
        null => { return null }
        $user => { $user }
    }
}