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