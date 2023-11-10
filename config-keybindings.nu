$env.config.keybindings = (
  $env.config.keybindings
  | append {
      name: reload_config
      modifier: none
      keycode: f5
      mode: emacs
      event: {
        send: executehostcommand,
        cmd: $"source '($nu.config-path)'"
      }
  }
)