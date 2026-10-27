# sup db - lokal Postgres for su-se-bakover: kopier fra dev, tøm, backup/restore, psql

use ./helpers.nu *

const TRUNCATE_SQL = r#'DO $$ BEGIN EXECUTE (SELECT 'TRUNCATE ' || string_agg(format('%I', tablename), ', ') || ' CASCADE' FROM pg_tables WHERE schemaname = 'public' AND tablename <> 'flyway_schema_history'); END $$;'#

# Kopier data fra dev-gcp til lokal Postgres (proxy, Flyway-sjekk, dump, tøm + import, rydd).
# Backend kjører under dumpen og stoppes bare under tøm + import; den startes igjen etterpå.
export def dump [
    --backup    # ta backup av lokal database først (sup db backup)
    --keep      # behold dumpfila (flyttes til ~/pgDump)
    --reason(-r): string = 'kopiererdevdata'   # begrunnelse for audit-logg
] {
    let db = (require-db)
    let local_version = (local-flyway)
    if $local_version == null {
        error make { msg: $"($db.project) mangler skjema. Start backend én gang så Flyway migrerer, og prøv igjen." }
    }
    let user = (gcloud config get account | str trim)
    if ($user | is-empty) { error make { msg: 'Ikke logget inn i gcloud. Kjør `nais auth login`.' } }
    if (listener $DEV.port) != null { error make { msg: $"Port ($DEV.port) er opptatt; stopp den gamle proxyen først." } }
    # proxyen kjører som bakgrunnsjobb uten terminal og kan ikke be om ny innlogging selv
    ensure-gcloud-login

    if $backup { backup | ignore }

    let tmp = (mktemp -d)
    let log = ($tmp | path join 'proxy.log')
    let file = ($tmp | path join 'dev_dump.sql')
    let pg = ['-h' '127.0.0.1' '-p' ($DEV.port | into string) '-U' $user '-d' $DEV.db]

    print $"Starter proxy til ($DEV.app) i ($DEV.env) på port ($DEV.port)"
    let proxy = (job spawn { ^nais cloudsql proxy $DEV.app -e $DEV.env -t $DEV.team -p $DEV.port -r $reason o+e> $log })

    try {
        wait-for 'proxy' 60 { (^pg_isready -q ...($pg | first 4) | complete).exit_code == 0 }

        let dev_version_sql = 'select version from flyway_schema_history where success and version is not null order by installed_rank desc limit 1'
        mut dev = (^psql ...$pg -tA -c $dev_version_sql | complete)
        if $dev.exit_code != 0 and ($dev.stderr =~ 'password authentication failed') {
            print $"Mangler databasebruker for ($user) i dev, kjører nais cloudsql grant"
            nais cloudsql grant $DEV.app -e $DEV.env -t $DEV.team -r $reason
            $dev = (^psql ...$pg -tA -c $dev_version_sql | complete)
        }
        if $dev.exit_code != 0 { error make { msg: $"Fikk ikke kontakt med dev-databasen: ($dev.stderr | str trim)" } }
        let dev_version = ($dev.stdout | str trim)

        print $"Flyway: dev ($dev_version), lokal ($local_version)"
        if ($dev_version | into float) > ($local_version | into float) {
            error make { msg: $"Dev har nyere migreringer \(($dev_version)\) enn lokal \(($local_version)\). Oppdater branchen fra master og start backend én gang, så dump igjen." }
        }
        if ($local_version | into float) > ($dev_version | into float) {
            print 'Advarsel: lokal har migreringer som ikke finnes i dev. Importen kan feile på nye NOT NULL-kolonner.'
        }

        print 'Tar dump fra dev (kan ta et par minutter)'
        ^pg_dump ...$pg --data-only --disable-triggers --exclude-table=flyway_schema_history -f $file
        job kill $proxy
        print $"Dump ferdig: ((ls $file | get 0.size))"

        with-backend-stopped {
            print $"Tømmer og importerer i ($db.project) \(én transaksjon, ruller tilbake ved feil\)"
            open --raw $file | ^docker exec -i $db.name psql -U $DB.user -d $DB.name -q -v ON_ERROR_STOP=1 --single-transaction -o /dev/null -c $TRUNCATE_SQL -f -
        }
    } catch {|err|
        do -i { job kill $proxy }
        if ($log | path exists) { print 'Proxy-logg:'; open --raw $log | lines | last 10 | each { print $"  ($in)" } | ignore }
        rm -rf $tmp
        error make { msg: $err.msg }
    }

    if $keep {
        let kept = ('~/pgDump' | path expand | path join $"dev_dump-(date now | format date '%Y%m%d%H%M').sql")
        mkdir ($kept | path dirname)
        mv $file $kept
        print $"Beholdt dump: ($kept)"
    }
    rm -rf $tmp

    print 'Ferdig.'
    counts
}

# Antall rader i sentrale tabeller.
export def counts [] {
    ['sak' 'søknad' 'behandling' 'revurdering' 'vedtak' 'utbetaling']
    | each {|t| { table: $t, rows: (local-sql $"select count\(*\) from ($t)" | str trim | into int) } }
}

# Tøm alle tabeller unntatt Flyway-historikken. Backend stoppes og startes igjen hvis den kjørte.
export def truncate [] {
    let db = (require-db)
    with-backend-stopped {
        print $"Tømmer lokale tabeller i ($db.project)"
        local-sql $TRUNCATE_SQL
    }
}

# Åpne psql mot lokal database.
export def psql [] {
    ^docker exec -it (require-db).name psql -U $DB.user -d $DB.name
}

# Backup av lokal database til ~/pgDump/<prosjekt>-<tid>.dump (pg_dump custom-format).
export def backup []: nothing -> path {
    let db = (require-db)
    let file = ('~/pgDump' | path expand | path join $"($db.project)-(date now | format date '%Y%m%d%H%M').dump")
    mkdir ($file | path dirname)
    print $"Backup av ($db.project) -> ($file)"
    ^docker exec $db.name pg_dump -U $DB.user -d $DB.name -Fc o> $file
    $file
}

# Gjenopprett lokal database fra en backup (sup db backup). Backend stoppes og startes igjen hvis den kjørte.
export def restore [
    file?: path   # backup-fil (default: velg blant ~/pgDump/*.dump)
] {
    let db = (require-db)
    let src = if $file != null { $file | path expand } else {
        use ../fzf
        ls ('~/pgDump' | path expand | path join '*.dump' | into glob) | sort-by -r modified | select name size modified | fzf select | get name
    }
    with-backend-stopped {
        print $"Gjenoppretter ($db.project) fra ($src)"
        open --raw $src | ^docker exec -i $db.name pg_restore -U $DB.user -d $DB.name --clean --if-exists --no-owner --single-transaction
    }
}

# Gi deg selv personlig tilgang til dev-databasen (engangs, oppretter IAM-bruker).
export def grant [
    --reason(-r): string = 'kopiererdevdata'
] {
    ensure-gcloud-login
    nais cloudsql grant $DEV.app -e $DEV.env -t $DEV.team -r $reason
}
