export def main [
    --name: string
    --url: string
] {
    let shebang = '#!/usr/bin/env nu'
    let pathFile = ($env.TMPDIR | path join $name)

    $shebang + (char newline) + "start" + (char space) + $"'($url)'" | save --force $pathFile
    ^chmod +x $pathFile
    $pathFile
}