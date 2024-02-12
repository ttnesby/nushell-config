def dir [] {
    let cacheDir = ('~/.azprice' | path expand)
    if (not ($cacheDir | path exists)) { mkdir $cacheDir }
    $cacheDir
}

def name [] {$'price-(date now | format date "%Y%m%d-%H%M")'}

# price files
export def sqlite [] { dir | path join $'(name).sqlite'}
export def json [] { dir | path join $'(name).json'}
export def parquet [] { dir | path join $'(name).parquet'}