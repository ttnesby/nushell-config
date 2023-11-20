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
const PERSONAL_CONFIG_FOLDER = '~/gitHub/ttnesby/nushell-config'
$env.PCF = $PERSONAL_CONFIG_FOLDER

# most custom features as different modules
use ($PERSONAL_CONFIG_FOLDER | path join az)
use ($PERSONAL_CONFIG_FOLDER | path join cidr)
use ($PERSONAL_CONFIG_FOLDER | path join err)
# due to fzf custom command and required consistent table management - no footer
$env.config.table.mode = 'light'
$env.config.footer_mode = 'never'
use ($PERSONAL_CONFIG_FOLDER | path join fzf)
use ($PERSONAL_CONFIG_FOLDER | path join gc)
use ($PERSONAL_CONFIG_FOLDER | path join ipv4)
use ($PERSONAL_CONFIG_FOLDER | path join op)
use ($PERSONAL_CONFIG_FOLDER | path join arcbrowser)

source ($PERSONAL_CONFIG_FOLDER | path join config-oh-my-posh.nu)
source ($PERSONAL_CONFIG_FOLDER | path join config-completer.nu)
# a few global custom commands, lsg used in pwd hook
source ($PERSONAL_CONFIG_FOLDER | path join config-custom-commands.nu)
source ($PERSONAL_CONFIG_FOLDER | path join config-pwd-hook.nu)
source ($PERSONAL_CONFIG_FOLDER | path join config-keybindings.nu)
```
