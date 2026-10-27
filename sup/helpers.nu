# sup helpers — felles oppslag for lokalt testmiljø (su-se-bakover + su-se-framover)

use ../repo/pr.nu
use ../fzf

export const BAKOVER = 'su-se-bakover'
export const FRAMOVER = 'su-se-framover'
export const PORTS = { postgres: 5432, backend: 8080, bff: 5678, vite: 1234, wonderwall: 3000, oauth: 4321 }
export const DB = { user: 'user', name: 'supstonad-db-local' }
export const DEV = { app: 'su-se-bakover', team: 'supstonad', env: 'dev-gcp', db: 'supstonad', port: 5433 }

# Gradle init-script som registrerer :web-regresjonstest:supLocal (LocalApplicationWithTestdata)
export const INIT_SCRIPT = path self ./local-app.init.gradle.kts

# Hovedklonen for et repo.
export def main-clone [repo: string]: nothing -> path {
    '~/gitHub/navikt' | path join $repo | path expand
}

# Alle worktrees for et repo.
export def worktrees [repo: string]: nothing -> table {
    pr list (main-clone $repo)
}

# Velg worktree: query via fzf, ellers den du står i, ellers fzf-valg blant alle.
export def pick-worktree [repo: string, query?: string]: nothing -> path {
    let wts = (worktrees $repo)
    # PWD kan gå via en symlenke (f.eks. mise trusted-configs), sammenlign på reell sti
    let pwd = ($env.PWD | path expand)
    let here = if $query == null {
        $wts
        | where {|w| $pwd == $w.path or ($pwd | str starts-with $"($w.path)/") }
        | sort-by -r {|w| $w.path | str length }  # dypeste treff, .claude/worktrees ligger under hovedklonen
        | get -o 0
    }
    if $here != null { return $here.path }

    print $"Velg worktree for ($repo):"
    $wts | fzf select ($query | default '') | if $in == null {
        error make { msg: $"Ingen worktree valgt for ($repo)" }
    } else {
        $in.path
    }
}

# Compose-prosjektnavn slik docker compose utleder det fra mappenavnet.
export def compose-project [dir: path]: nothing -> string {
    $dir | path basename | str lowercase | str replace --all --regex '[^a-z0-9_-]' ''
}

# Compose-prosjekter (også stoppede) som hører til et repo, uansett worktree.
export def compose-projects [repo: string]: nothing -> table {
    docker compose ls --all --format json
    | from json
    | where ConfigFiles =~ $"/($repo)"
    | select Name Status ConfigFiles
}

# Container som publiserer lokal Postgres-port, eller null.
export def db-container []: nothing -> any {
    docker ps --filter $"publish=($PORTS.postgres)" --format '{{.Names}}|{{.Label "com.docker.compose.project"}}'
    | lines
    | parse '{name}|{project}'
    | get -o 0
}

# Som db-container, men feiler med hint når Postgres ikke kjører.
export def require-db []: nothing -> record {
    db-container | if $in == null {
        error make { msg: $"Ingen lokal Postgres på port ($PORTS.postgres). Kjør `sup up` først." }
    } else { $in }
}

# Kjør SQL mot lokal database (stdin til psql i containeren).
export def local-sql [sql: string, ...flags: string]: nothing -> string {
    $sql | ^docker exec -i (require-db).name psql -U $DB.user -d $DB.name -v ON_ERROR_STOP=1 -tA ...$flags
}

# Siste vellykkede Flyway-migrering i lokal database, eller null.
export def local-flyway []: nothing -> any {
    try {
        local-sql 'select version from flyway_schema_history where success and version is not null order by installed_rank desc limit 1' | str trim
    } catch { null }
}

# PID som lytter på en TCP-port, eller null.
export def listener [port: int]: nothing -> any {
    ^lsof -nP -t $"-iTCP:($port)" -sTCP:LISTEN
    | complete
    | if $in.exit_code != 0 { null } else { $in.stdout | lines | first | into int }
}

# Arbeidsmappe for en prosess.
export def cwd-of [pid: int]: nothing -> string {
    ^lsof -a -p $pid -d cwd -Fn | lines | where ($it | str starts-with 'n') | first | str substring 1..
}

# Stopp prosessen på backend-porten (også når den er startet fra IntelliJ) og lukk fanen.
# Returnerer worktreen den kjørte fra, eller null.
export def stop-backend [
    --keep-tab   # behold fanen (for omstart i samme fane)
]: nothing -> any {
    let pid = (listener $PORTS.backend)
    let dir = if $pid == null { print 'Backend kjører ikke'; null } else {
        let dir = (cwd-of $pid)
        print $"Stopper backend \(pid ($pid), ($dir)\)"
        kill $pid
        wait-for 'backend stopp' 30 { (listener $PORTS.backend) == null }
        $dir
    }
    if not $keep_tab { iterm-close backend }
    $dir
}

# Start backend (LocalApplicationWithTestdata via Gradle) fra en worktree i backend-fanen.
export def start-backend [dir: path] {
    print $"Starter backend fra ($dir) i iTerm-fanen 'sup backend'"
    iterm-run backend $dir $"mise exec -- ./gradlew --init-script '($INIT_SCRIPT)' :web-regresjonstest:supLocal"
}

# Kjør en operasjon med backend stoppet, og start den igjen i samme worktree (og fane) hvis den kjørte.
# Backend startes igjen også når operasjonen feiler.
export def with-backend-stopped [op: closure] {
    let dir = (stop-backend --keep-tab)
    let err = try { do $op | ignore; null } catch {|e| $e }
    if $dir != null { start-backend $dir }
    if $err != null { error make { msg: $err.msg } }
}

# Er gcloud-innloggingen (bruker + ADC, som Cloud SQL-proxyen bruker) gyldig uten ny innlogging?
export def gcloud-login-valid []: nothing -> bool {
    (^gcloud auth print-access-token | complete).exit_code == 0 and (^gcloud auth application-default print-access-token | complete).exit_code == 0
}

# Sørg for gyldig gcloud-innlogging før kommandoer som kjører uten terminal (proxy i bakgrunnen).
# Google krever jevnlig ny innlogging; da logges du inn på nytt i nettleseren via `nais auth login`.
export def ensure-gcloud-login [] {
    if (gcloud-login-valid) { return }
    print 'gcloud-innloggingen har utløpt, logger inn på nytt (nettleser)'
    ^nais auth login --yes
    if not (gcloud-login-valid) {
        error make { msg: 'gcloud-innloggingen er fortsatt ikke gyldig. Kjør `nais auth login` manuelt.' }
    }
}

# Vent til en betingelse er sann, med timeout i sekunder.
export def wait-for [what: string, timeout: int, check: closure] {
    let start = (date now)
    while not (do $check) {
        if ((date now) - $start) > ($timeout * 1sec) {
            error make { msg: $"Tidsavbrudd: ($what) etter ($timeout) sekunder" }
        }
        sleep 500ms
    }
}

# ── iTerm-faner ───────────────────────────────────────────────
# Hver tjeneste (backend/frontend) får én fane. Fanens økt-UUID lagres i en tilstandsfil,
# slik at fanen gjenbrukes ved omstart og lukkes ved stopp – uansett hvilket vindu den ligger i.
# NB: mise-hooken bytter verktøy først ved neste prompt, ikke etter `cd` på samme linje,
# så kommandoer som trenger mappens Java/Node må kjøres via `mise exec --`.

const ITERM = 'com.googlecode.iterm2'
const SHELLS = [login nu zsh bash sh]

def tabs-file []: nothing -> path {
    '~/.local/state/sup/tabs.nuon' | path expand
}

def tabs []: nothing -> record {
    let f = (tabs-file)
    if ($f | path exists) { open $f } else { {} }
}

def tabs-set [role: string, id: any] {
    let f = (tabs-file)
    mkdir ($f | path dirname)
    tabs | upsert $role $id | save --force $f
}

# AppleScript som finner økten med gitt UUID i alle vinduer og kjører `action` på den (variabel s).
def with-session [id: string, action: string]: nothing -> string {
    ^osascript -e $"
        tell application id \"($ITERM)\"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if id of s is \"($id)\" then
                            ($action)
                        end if
                    end repeat
                end repeat
            end repeat
            return \"\"
        end tell
    " | complete | get stdout | str trim
}

# Er økten ledig, dvs. bare skallet kjører i den? (tty fra iTerm, prosesser fra ps)
def session-idle [tty: string]: nothing -> bool {
    ^ps -t ($tty | str replace '/dev/' '') -o command=
    | lines
    | each {|c| $c | str trim | split row ' ' | first | path basename | str trim --left --char '-' }
    | all {|c| $c in $SHELLS }
}

# Kjør en kommando i tjenestens fane: gjenbruk den hvis den finnes og er ledig, ellers ny fane.
export def iterm-run [role: string, dir: path, cmd: string] {
    let line = $"cd '($dir)'; ($cmd)"
    let id = (tabs | get -o $role)
    if $id != null {
        let tty = (with-session $id 'return tty of s')
        if $tty != '' and (session-idle $tty) {
            with-session $id $"tell s to write text \"($line)\"
                            return \"ok\"" | ignore
            print $"  \(gjenbruker fanen 'sup ($role)'\)"
            return
        }
    }
    let new_id = (^osascript -e $"
        tell application id \"($ITERM)\"
            if \(count of windows\) = 0 then create window with default profile
            tell current window
                set originalTab to current tab
                set newTab to \(create tab with default profile\)
                tell current session of newTab
                    set name to \"sup ($role)\"
                    write text \"($line)\"
                    set sid to id
                end tell
                select originalTab
            end tell
            return sid
        end tell
    " | str trim)
    tabs-set $role $new_id
}

# Lukk tjenestens fane hvis den finnes.
export def iterm-close [role: string] {
    let id = (tabs | get -o $role)
    if $id == null { return }
    with-session $id 'close s
                            return "ok"' | ignore
    tabs-set $role null
}
