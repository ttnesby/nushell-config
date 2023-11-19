# prerequiste - 1Password op client
use ./helpers/read.nu *
use ../fzf

# module op - set environments from a list given by env_var documents in vault
export def-env 'set env' [
    --vault (-v): string = Development  # which vault to find documents
    --tag (-t): string = env_var        # which tag must exist in documents
] {
    let relevantFields = ['name' 'value']

    titles --vault $vault --tag $tag
    | par-each {|d| record --vault $vault --title $d.title --relevantFields $relevantFields}
    | input list -m
    | match $in {
        '' => { return null }
        $d => { $d }
    }
    | each {|r| {$r.name:$"(op read $r.value)"} }
    | reduce -f {} {|e, acc| $acc | merge $e }
    | load-env
}

# module op - select service principal by service_principal documents in vault
export def 'select service principal' [
    --vault (-v): string = Development      # which vault to find env var. documents
    --tag (-t): string = service_principal  # which tag must exist in service principal documents
    --query (-q): string = ''               # fuzzy query
] {
    let relevantFields = ['name' 'tenant_id' 'client_id' 'client_secret']
    let empty = {}

    titles --vault $vault --tag $tag
    | par-each {|d| record --vault $vault --title $d.title --relevantFields $relevantFields }
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