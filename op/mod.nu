# prerequiste - 1Password op client

# module op - return table of document titles in vault with tag
export def titles [
    --vault (-v): string    # which vault to find documents
    --tag (-t): string      # which tag must exist in documents
] {
    op item list --vault $vault --tags $tag --format json | from json | select title
}

# module op - return record of fields based on relevantFields, title and vault
export def record [
    --vault (-v): string                # which vault hosting document
    --title: string                     # document title
    --relevantFields (-f): list<string> # fields to extract
] {
    let valOrRef = {|i| if $i.type == 'CONCEALED' {$i.reference} else {$i.value}}

    op item get $title --vault $vault --format json
    | from json
    | get fields
    | where label in $relevantFields
    | reduce -f {} {|it, acc| $acc | merge {$it.label: (do $valOrRef $it)} }
    # only documents with all relevant fields
    | do {|r| if ($r | columns ) == $relevantFields {$r} } $in
}

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