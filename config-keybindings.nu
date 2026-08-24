$env.config.keybindings = (
    $env.config.keybindings
    | where name != reload_config
    | append {
        name: reload_config
        modifier: none
        keycode: f5
        mode: [vi_insert,vi_normal]
        event: {
            send: executehostcommand,
            cmd: $"source '($nu.config-path)'"
        }
    }
)
