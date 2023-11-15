# module logout - logout
export def main [] {
    az account list --output json --only-show-errors
    | from json
    | match $in {
        [] => { null }
        _ => { az logout }
    }
}