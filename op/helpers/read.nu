# return table of document titles in vault with tag
export def titles [
    --vault (-v): string    # which vault to find documents
    --tag (-t): string      # which tag must exist in documents
] {
    op item list --vault $vault --tags $tag --format json | from json | select title
}

# return record of fields based on relevantFields, title and vault
export def recordFields [
    --vault (-v): string                # which vault hosting document
    --title: string                     # document title
    --fields (-f): list<string> # fields to extract
] {
    let valOrRef = {|i| if $i.type == 'CONCEALED' {$i.reference} else {$i.value}}

    op item get $title --vault $vault --format json
    | from json
    | get fields
    | where label in $fields
    | reduce -f {} {|it, acc| $acc | merge {$it.label: (do $valOrRef $it)} }
    # only documents with all relevant fields
    | do {|r| if ($r | columns ) == $fields {$r} } $in
}

export def recordAll [
    --vault (-v): string                # which vault hosting document
    --title: string                     # document title
] {
    op item get $title --vault $vault --format json
    | from json
    | get fields
    | where label != notesPlain
    | select label value
}