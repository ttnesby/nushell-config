# repo pr — opprett/rydd arbeidsbranches som egne git worktrees ved siden av hovedklonen.
#
# Konvensjon: hovedklonen står permanent på base (master) som referanse.
# Hver arbeidsbranch får sin egen worktree som søsken-mappe: <repo>.<branch>
# Eksempel:
#   gitHub/navikt/pensjon-regler/                      <- alltid master
#   gitHub/navikt/pensjon-regler.ttn-test-2026.../     <- arbeidsbranch

# Intern: finn hovedklonen (mappa som eier den delte .git-katalogen).
# Virker fra hvilken som helst worktree i repoet.
def main-root [] {
    git rev-parse --path-format=absolute --git-common-dir | str trim | path dirname
}

# Intern: parse `git worktree list` til en tabell { path, branch }.
def worktrees [] {
    git worktree list --porcelain
    | split row "\n\n"
    | where ($it | str trim | is-not-empty)
    | each { |block|
        let f = ($block | lines)
        let path = ($f | where ($it | str starts-with "worktree ") | first | str replace "worktree " "")
        let brs = ($f | where ($it | str starts-with "branch ") | each { |b| $b | str replace "branch refs/heads/" "" })
        { path: $path, branch: (if ($brs | is-empty) { "" } else { $brs | first }) }
    }
}

# Vis alle worktrees for dette repoet.
export def list [] {
    worktrees
}

# Opprett ny branch i egen worktree (søsken til hovedklonen), tom commit + draft PR.
# Du blir stående i den nye worktree-mappa etterpå.
export def --env create [
    branch_name: string         # Basenavn for branchen (f.eks. ttn/test)
    commit_message: string      # Melding for tom commit og PR-tittel
    --base: string = "master"   # Base-branch å lage fra og PR mot
] {
    let timestamp = (date now | format date "%Y%m%d%H%M")
    let full_branch_name = $"($branch_name)-($timestamp)"
    let full_commit_message = $"($commit_message)-($timestamp)"

    let root = (main-root)
    let parent = ($root | path dirname)
    let repo_name = ($root | path basename)
    let safe = ($full_branch_name | str replace --all "/" "-")
    let wt_path = ($parent | path join $"($repo_name).($safe)")

    print $"Henter siste ($base)..."
    git fetch origin $base

    print $"Lager worktree ($wt_path) på branch ($full_branch_name)"
    git worktree add -b $full_branch_name $wt_path $"origin/($base)"

    cd $wt_path

    print $"Lager tom commit: ($commit_message)"
    git commit --allow-empty -m $commit_message

    print "Pusher til origin..."
    git push -u origin $full_branch_name

    print $"Lager draft PR mot ($base)..."
    try {
        gh pr create --title $full_commit_message --body $"Auto-generert PR fra branch ($full_branch_name)" --base $base --draft
        print "Pull request opprettet!"
    } catch {
        print "Klarte ikke å lage PR. Sjekk at 'gh' er installert og autentisert."
        print $"Manuelt: gh pr create --title '($commit_message)' --base ($base) --draft"
    }
    print $"Du står nå i ($wt_path)"
}

# Rydd worktrees: fjern de hvis remote-branch er borte (PR merget+slettet)
# eller hvis branchen er merget inn i base. Dry-run som standard; --force for å faktisk fjerne.
export def --env clean [
    --base: string = "master"   # Base å måle "merget" mot
    --force                     # Faktisk fjern (ellers bare vis hva som ville blitt fjernet)
] {
    print "Henter og pruner remotes..."
    git fetch --prune origin

    let root = (main-root)
    let here = (pwd)

    let candidates = (worktrees | where path != $root and branch != $base and branch != "")

    let report = ($candidates | each { |w|
        let gone = ((do -i { git rev-parse --verify --quiet $"origin/($w.branch)" } | complete).exit_code != 0)
        let merged = ((do -i { git merge-base --is-ancestor $w.branch $"origin/($base)" } | complete).exit_code == 0)
        let reason = (if $gone { "remote borte" } else if $merged { "merget i base" } else { "" })
        { path: $w.path, branch: $w.branch, remove: ($gone or $merged), reason: $reason }
    })

    let to_remove = ($report | where remove == true)

    if ($to_remove | is-empty) {
        print "Ingenting å rydde."
        return
    }

    if not $force {
        print "Dry-run — ville fjernet (kjør med --force for å utføre):"
        return ($to_remove | select branch reason path)
    }

    for w in $to_remove {
        # ikke fjern worktree du står i — gå til hovedklonen først
        if ($here | str starts-with $w.path) {
            cd $root
        }
        print $"Fjerner worktree ($w.path) [($w.reason)]"
        git worktree remove --force $w.path
        # slett lokal branch hvis den fortsatt finnes
        do -i { git branch -D $w.branch }
    }
    git worktree prune
    print "Ferdig."
    worktrees
}
