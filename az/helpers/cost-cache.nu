# dir for download of cost CSV
export def dir [] {
    let cacheDir = ('~/.azcost' | path expand)
    if (not ($cacheDir | path exists)) { mkdir $cacheDir }
    $cacheDir
}

# cost CSV file
export def file [
    --subscription (-s): string
    --periode (-p): string
] {
    dir | path join $'($subscription)-($periode)-(date now | format date "%Y%m%d-%H%M").csv'
}