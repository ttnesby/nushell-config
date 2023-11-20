$env.config.keybindings = (
    $env.config.keybindings
    | append {
        name: reload_config
        modifier: none
        keycode: f5
        mode: vi_insert
        event: {
            send: executehostcommand,
            cmd: $"source '($nu.config-path)'"
        }
    }
    | append {
        name: reload_config
        modifier: none
        keycode: f5
        mode: vi_normal
        event: {
            send: executehostcommand,
            cmd: $"source '($nu.config-path)'"
        }
    }
)