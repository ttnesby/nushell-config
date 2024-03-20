export def dir [] {
    let cacheDir = ('~/.azprice' | path expand)
    if (not ($cacheDir | path exists)) { mkdir $cacheDir }
    $cacheDir
}

const file_name = 'price_list'

# price files
export def json [] { dir | path join $'($file_name).json' | path expand}
export def parquet [] { dir | path join $'($file_name).parquet' | path expand}