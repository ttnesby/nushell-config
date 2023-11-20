use ../config

const thisFolder = 'arcbrowser'

def isRunning [] { (ps | where name =~ Arc | length) > 0 }

# module arcbrowser/space - set active space
export def set [
    --name (-n): string
] {
    if ((sys).host.name == Darwin) and (isRunning) {
        osascript (
            $config.PATH 
            | path expand 
            | path join $thisFolder
            | path join activateArcSpace.scpt
        ) $name
    }
}

# module arcbrowser/space - get active space
export def get [] {
    if ((sys).host.name == Darwin) and (isRunning) {
        osascript (
            $config.PATH 
            | path expand 
            | path join $thisFolder
            | path join getActiveArcSpace.scpt
        )
        | complete
        | match $in {
            {exit_code: $ec, stdout: _} if $ec != 0  => { null }
            {exit_code: 0, stdout: $space} => { $space | lines | first }
        }
    } else {
        ''
    }
}