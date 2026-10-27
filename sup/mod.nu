# module sup - supplerende stønad: lokalt testmiljø for su-se-bakover + su-se-framover
#
# Hver bakover-worktree har eget compose-prosjekt og egen Postgres (egne data og migreringer).
# Bare én kan ha port 5432 om gangen, så `sup up` stopper de andre (volumene beholdes).
#
#   sup up [bakover] [framover]   docker + backend + frontend fra valgte worktrees
#   sup down                      stopp alt (volumene beholdes)
#   sup status                    hva kjører, og fra hvilken worktree
#   sup wt [--pr]                 worktrees i begge repo
#   sup clean [--force]           Postgres-volumer fra slettede bakover-worktrees
#   sup doctor                    sjekk verktøy og innlogging
#   sup backend|frontend start|stop
#   sup db dump|truncate|psql|backup|restore|grant

use ./helpers.nu *
export use ./db.nu

# Start docker, backend og frontend. Worktree velges med query, der du står, eller fzf.
export def up [
    bakover?: string    # query for bakover-worktree
    framover?: string   # query for framover-worktree
    --no-app            # bare docker, ikke backend/frontend
    --no-wait           # ikke vent på at backend/frontend svarer
] {
    let b = (pick-worktree $BAKOVER $bakover)
    let f = (pick-worktree $FRAMOVER $framover)

    docker-up-bakover $b
    docker-up-framover $f

    if not $no_app {
        backend start $b
        frontend start $f
        if not $no_wait {
            print 'Venter på frontend og backend (Gradle kan bruke noen minutter, Ctrl+C avbryter ventingen)'
            wait-for 'frontend' 120 { (listener $PORTS.bff) != null }
            wait-for 'backend' 600 { (listener $PORTS.backend) != null }
            print 'Klar: http://localhost:3000'
        }
    }
    status
}

# Stopp backend, frontend og docker for begge repo. Volumene beholdes.
export def down [
    --keep-docker   # stopp bare backend/frontend
] {
    backend stop
    frontend stop
    if not $keep_docker {
        compose-projects $BAKOVER | where Status =~ 'running' | each {|p|
            print $"Stopper ($p.Name)"
            docker compose -p $p.Name down
        }
        print $"Stopper ($FRAMOVER)"
        docker compose -p $FRAMOVER down
    }
    status
}

# Hva kjører lokalt, og fra hvilken worktree.
export def status [] {
    let db = (db-container)
    let docker_dir = {|name|
        docker ps --filter $"name=^($name)$" --format '{{.Label "com.docker.compose.project.working_dir"}}' | str trim
    }
    let proc_dir = {|port| listener $port | if $in == null { '' } else { cwd-of $in } }

    [
        [service port source];
        [postgres $PORTS.postgres (if $db == null { '' } else { $db.project })]
        [mock-oauth2-server $PORTS.oauth (do $docker_dir mock-oauth2-server)]
        [wonderwall $PORTS.wonderwall (do $docker_dir wonderwall)]
        [backend $PORTS.backend (do $proc_dir $PORTS.backend)]
        [bff $PORTS.bff (do $proc_dir $PORTS.bff)]
        [vite $PORTS.vite (do $proc_dir $PORTS.vite)]
    ]
    | insert up {|r| $r.source != '' }
    | update source {|r| $r.source | str replace ($env.HOME | path join 'gitHub' 'navikt' '') '' }
    | move up --after service
}

# Worktrees i bakover og framover, med det som kjører merket.
export def wt [
    --pr    # vis åpne PR-er for branchene (gh)
] {
    let db = (db-container)
    let fe = (listener $PORTS.bff | if $in == null { '' } else { cwd-of $in })

    [$BAKOVER $FRAMOVER] | each {|repo|
        let prs = if $pr {
            gh pr list -R $"navikt/($repo)" --author '@me' --json headRefName,number,isDraft,url | from json
        } else { [] }

        worktrees $repo | each {|w|
            let running = if $repo == $BAKOVER {
                $db != null and (compose-project $w.path) == $db.project
            } else { $fe == $w.path }
            let p = ($prs | where headRefName == $w.branch | get -o 0)
            {
                repo: $repo
                branch: $w.branch
                running: $running
                pr: (if $p == null { '' } else { $"#($p.number)(if $p.isDraft { ' draft' } else { '' })" })
                path: $w.path
            }
        }
    }
    | flatten
    | if $pr { $in } else { reject pr }
}

# Postgres-volumer fra bakover-worktrees som ikke finnes lenger. Dry-run som standard; --force sletter.
export def clean [
    --force     # slett volumene (og evt. containere/nettverk fra samme prosjekt)
] {
    let existing = (worktrees $BAKOVER | each {|w| compose-project $w.path })
    let orphans = (
        docker volume ls --filter label=com.docker.compose.volume=supstonad-db-local --format '{{.Name}}|{{.Label "com.docker.compose.project"}}'
        | lines
        | parse '{volume}|{project}'
        | where project not-in $existing
        | insert created {|v| docker volume inspect $v.volume --format '{{.CreatedAt}}' | into datetime }
    )

    if ($orphans | is-empty) {
        print 'Ingenting å rydde.'
        return
    }
    if not $force {
        print 'Dry-run — ville slettet (kjør med --force for å utføre):'
        return ($orphans | select project created volume)
    }

    for o in $orphans {
        print $"Sletter ($o.project) og volumet ($o.volume)"
        docker compose -p $o.project down
        docker volume rm $o.volume
    }
    print 'Ferdig.'
}

# Sjekk verktøy, innlogging og kubeconfig som `sup` trenger.
export def doctor [] {
    let tool = {|cmd, fix| { check: $cmd, ok: (which $cmd | is-not-empty), fix: $fix } }
    let account = (^gcloud config get account | complete | get stdout | str trim)
    let contexts = (^kubectl config get-contexts -o name | complete | get stdout | lines)

    [
        (do $tool docker 'installer OrbStack')
        (do $tool fzf 'brew install fzf')
        (do $tool nais 'brew install nais/tap/nais')
        (do $tool gcloud 'brew install --cask gcloud-cli')
        (do $tool kubectl 'brew install kubectl')
        (do $tool gke-gcloud-auth-plugin 'gcloud components install gke-gcloud-auth-plugin, og google-cloud-sdk/bin på PATH (env.nu)')
        (do $tool pg_dump 'brew install libpq, og libpq/bin på PATH (env.nu)')
        (do $tool pg_isready 'brew install libpq, og libpq/bin på PATH (env.nu)')
        { check: 'gcloud-innlogging', ok: ($account | is-not-empty), fix: 'nais auth login' }
        { check: $'kubeconfig ($DEV.env)', ok: ($DEV.env in $contexts), fix: 'nais kubeconfig' }
    ]
    | update fix {|r| if $r.ok { '' } else { $r.fix } }
}

# Start backend (LocalApplicationWithTestdata via Gradle) i ny iTerm-fane.
export def "backend start" [
    worktree?: string   # path eller query for bakover-worktree
] {
    let dir = if $worktree != null and ($worktree | path exists) { $worktree | path expand } else { pick-worktree $BAKOVER $worktree }
    let pid = (listener $PORTS.backend)
    if $pid != null {
        let from = (cwd-of $pid)
        if $from == $dir { print $"Backend kjører allerede fra ($from)"; return }
        error make { msg: $"Port ($PORTS.backend) brukes allerede av ($from). Kjør `sup backend stop` først." }
    }
    let db = (require-db)
    if (compose-project $dir) != $db.project {
        print $"Advarsel: Postgres på ($PORTS.postgres) tilhører ($db.project), ikke denne worktreen."
    }
    start-backend $dir
}

# Stopp backend (prosessen på port 8080, også når den er startet fra IntelliJ).
export def "backend stop" [] {
    stop-backend | ignore
}

# Start frontend (`npm start`) i ny iTerm-fane. Lenker .env og kjører npm ci ved behov.
export def "frontend start" [
    worktree?: string   # path eller query for framover-worktree
] {
    let dir = if $worktree != null and ($worktree | path exists) { $worktree | path expand } else { pick-worktree $FRAMOVER $worktree }
    let pid = (listener $PORTS.bff)
    if $pid != null {
        let from = (cwd-of $pid)
        if $from == $dir { print $"Frontend kjører allerede fra ($from)"; return }
        error make { msg: $"Port ($PORTS.bff) brukes allerede av ($from). Kjør `sup frontend stop` først." }
    }

    # .env er ikke sjekket inn; en ny worktree låner hovedklonens
    let env_file = ($dir | path join '.env')
    let main_env = (main-clone $FRAMOVER | path join '.env')
    if not ($env_file | path exists) and ($main_env | path exists) {
        print $"Lenker ($env_file) -> ($main_env)"
        ^ln -s $main_env $env_file
    }

    let cmd = if ($dir | path join 'node_modules' | path exists) { 'mise exec -- npm start' } else { 'mise exec -- npm ci; mise exec -- npm start' }
    print $"Starter frontend fra ($dir) i ny iTerm-fane: ($cmd)"
    iterm-tab $dir $cmd
}

# Stopp frontend (hele `npm start`-gruppen: nodemon, tsx og vite).
export def "frontend stop" [] {
    let pid = (listener $PORTS.bff) | default (listener $PORTS.vite)
    if $pid == null { print 'Frontend kjører ikke'; return }
    let pgid = (^ps -o pgid= -p $pid | str trim | into int)
    let leader = (^ps -o command= -p $pgid | str trim)
    print $"Stopper frontend \((cwd-of $pid)\)"
    if ($leader | str starts-with 'npm') {
        ^kill -TERM -- $"-($pgid)"
    } else {
        kill $pid
    }
    wait-for 'frontend stopp' 30 { (listener $PORTS.bff) == null and (listener $PORTS.vite) == null }
}

# Intern: Postgres for valgt worktree; stopper andre bakover-prosjekter som vil ha samme port.
def docker-up-bakover [dir: path] {
    let project = (compose-project $dir)
    compose-projects $BAKOVER | where Name != $project and Status =~ 'running' | each {|p|
        print $"Stopper ($p.Name) \(holder port ($PORTS.postgres)\)"
        docker compose -p $p.Name down
    }
    let file = ($dir | path join 'docker-compose.yml')
    print $"Starter Postgres for ($project)"
    docker compose -f $file up -d --wait
    # en container opprettet mens porten var opptatt kan kjøre uten portbinding
    if (docker compose -f $file port postgres $PORTS.postgres | complete | get stdout | str trim | is-empty) {
        print 'Postgres mangler portbinding, gjenoppretter containeren'
        docker compose -f $file up -d --wait --force-recreate
    }
}

# Intern: mock-oauth2-server og Wonderwall fra valgt framover-worktree.
def docker-up-framover [dir: path] {
    print $"Starter mock-oauth2-server og Wonderwall fra ($dir)"
    docker compose -f ($dir | path join 'docker-compose.yml') up -d --wait
}
