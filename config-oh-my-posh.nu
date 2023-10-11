let posh_dir = (brew --prefix oh-my-posh | str trim)
let posh_theme = $'($posh_dir)/themes/' # For more [Themes demo](https://ohmyposh.dev/docs/themes)

#$env.PROMPT_COMMAND = { || oh-my-posh prompt print primary --config $'($posh_theme)/amro.omp.json' }
$env.PROMPT_COMMAND = { || oh-my-posh prompt print primary --config $'($posh_theme)/powerline.omp.json' }

#$env.PROMPT_COMMAND = { || oh-my-posh prompt print primary --config $'($posh_theme)/cloud-native-azure.omp.json' }
$env.PROMPT_COMMAND_RIGHT = ""
# Optional
$env.PROMPT_INDICATOR = $"(ansi y)$> (ansi reset)"