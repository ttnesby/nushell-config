# dir for download of cost CSV
export def dir [
    --periode_name(-p): string  # YYYYmm, e.g. 202403
] {
    let cacheDir = ($'~/.azcost/($periode_name)' | path expand)
    if (not ($cacheDir | path exists)) { mkdir $cacheDir }
    $cacheDir
}

# cost CSV file
export def file [
    --subscription (-s): string # subscription id
    --periode_name (-p): string # YYYYmm, e.g. 202403
] {
    dir -p $periode_name | path join $'($periode_name)_($subscription)_(date now | format date "%Y%m%d").csv'
}