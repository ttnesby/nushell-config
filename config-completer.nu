let fish_completer = {|spans|
    fish --command $'complete "--do-complete=($spans | str join " ")"'
    | $"value(char tab)description(char newline)" + $in
    | from tsv --flexible --no-infer
}

let carapace_completer = {|spans: list<string>|
    carapace $spans.0 nushell $spans
    | from json
    | if ($in | default [] | where value =~ '^-.*ERR$' | is-empty) { $in } else { null }
}

# This completer will use carapace by default
let external_completer = {|spans|
    let expanded_alias = (scope aliases | where name == $spans.0 | get -i 0 | get -i expansion)

    let spans = if $expanded_alias != null {
        $spans
        | skip 1
        | prepend ($expanded_alias | split row ' ')
    } else {
        $spans
    }

    match $spans.0 {
        nu => $fish_completer
        git => $fish_completer
        asdf => $fish_completer
        _ => $carapace_completer
    } | do $in $spans
}