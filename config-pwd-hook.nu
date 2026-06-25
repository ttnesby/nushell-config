# set the pwd hook in config
$env.config = ($env.config | upsert hooks {
    env_change: {
        PWD: [
            {
                condition:{|_,_| true}
                code: {|_,_| print (lsg)}
            }
            {
                condition: {|_, after|
                    let dir = '/Users/torsteinnesby/go/ttnesby/azure-alert-slack-notification'
                    let util = 'utilities.nu'

                    let inDir = $after == $dir
                    let hasUtilities = $after | path join $util | path exists

                    ($inDir and $hasUtilities)
                }
                code: "overlay use utilities.nu"
            }
        ]
    }
})

$env.config.hooks.pre_prompt = (
    $env.config.hooks.pre_prompt | append {||
        let title = (
            if (".git" | path exists) or (do { git rev-parse --git-dir } | complete).exit_code == 0 {
                let repo = (git rev-parse --show-toplevel | path basename)
                let branch = (git branch --show-current)
                if ($branch | is-empty) {
                    # Detached HEAD - vis kort SHA
                    let sha = (git rev-parse --short HEAD)
                    $"($repo)@($sha)"
                } else {
                    $"($repo):($branch)"
                }
            } else {
                pwd | path basename
            }
        )
        print -n $"\e]1;($title)\u{07}"
    }
)
