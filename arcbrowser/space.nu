use ../config

def isRunning [] {(ps | where name =~ Arc | length) > 0}

# module arcbrowser/space - set active space
export def set [
  --name (-n): string
] {
  if ((sys).host.name == Darwin) and (isRunning) {
    osascript ($config.PATH | path expand | path join activateArcSpace.scpt) $name
  }
}

# module arcbrowser/space - get active space
export def get [] {
  if ((sys).host.name == Darwin) and (isRunning) {
    osascript ($config.PATH | path expand | path join getActiveArcSpace.scpt)
  } else {
    ''
  }  
}