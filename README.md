# nushell-config

This repo contains a few modules and scripts. These are configured in `$nu.config-path`.

Example of config is

```nushell

...
$env.config = {...}

# nvim as editor, using vi as edit mode
$env.config.buffer_editor = '/opt/homebrew/bin/nvim'
$env.config.edit_mode = 'vi'

# enable testing
use std testing run-tests

# need a constant
use ~/gitHub/ttnesby/nushell-config/config

# most custom features as different modules
use ($config.PATH | path join az)
use ($config.PATH | path join cidr)
use ($config.PATH | path join err)
# due to fzf custom command and required consistent table management - no footer
$env.config.table.mode = 'light'
$env.config.footer_mode = 'never'
use ($config.PATH | path join fzf)
use ($config.PATH | path join gc)
use ($config.PATH | path join ipv4)
use ($config.PATH | path join op)
use ($config.PATH | path join arcbrowser)

source ($config.PATH | path join config-oh-my-posh.nu)
source ($config.PATH | path join config-completer.nu)
# a few global custom commands, lsg used in pwd hook
source ($config.PATH | path join config-custom-commands.nu)
source ($config.PATH | path join config-pwd-hook.nu)
source ($config.PATH | path join config-keybindings.nu)
```
