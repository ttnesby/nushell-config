# module fzf - fuzzy selection from a table, dependency to fzf utility
export def select [
    query: string = '' # inital search
] {
    let cache = $in # NB! Assuming a table due to index, whatever record type
    # do fzf selection with intial search and return if only 1 found, returning null or the selected record
    ($cache | fzf --ansi --header-lines=2 --header-first --query $query --select-1 --height=~75% --layout=reverse | lines)
    | match $in {
        [] => { return null }
        _ => {
            # key point, only get the index from the selected string
            let index = ($in | first | str trim | split row (char space) | first | into int)
            $cache | get $index
        }
    }
}