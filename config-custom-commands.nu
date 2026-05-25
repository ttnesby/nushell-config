use ./fzf
use ./op
use ./az
use ./err
use ./batch

### gen ################################################################################

# gen - custom commands overview
def cco [] {
    let withType = {|data| $data | select name | merge ($data | get description | split column ' - ' type description)}
    let cmd = scope commands | where type == custom and description != '' and name not-in ['pwd'] | select name description
    let ali = scope aliases | where description != '' | select name description

    do $withType $cmd | append (do $withType $ali) | sort-by type name #group-by type | sort
}

#gen - empty trash can
alias etc = osascript -e '
tell application "Finder"
    if (count of items in trash) > 0 then
        empty trash
    end if
end tell'

# gen - dir content as grid, used in pwd hook
def lsg []: any -> string { ls -as | sort-by type name -i | get name | grid -c }

# gen - config files to zed
alias cfg = zed -n ...[
    $nu.config-path,
    $nu.env-path,
    ([($env.HOME),'.zshrc'] | path join),
    ([($env.HOME),'.config','starship.toml'] | path join),
    ([($env.HOME),'.config','atuin','config.toml'] | path join),
    ([($env.HOME),'.local','share','atuin','init2.nu'] | path join),
    ]

# gen - overlay list
alias ol = overlay list

# gen - overlay new
alias on = overlay new

# gen - overlay use
alias ou = overlay use

# gen - overlay hide
alias oh = overlay hide

# gradle - build
alias b = ./gradlew build

# gradle - run
alias r = ./gradlew run

### cloud ##############################################################################

# cloud - az + gc
def azgc [
    --az_user(-u) = 'ra'
    --az_sub(-s) = 'Identity'
    --gc_arc_space(-a) = '@work-adm'
] {
    us $az_user; az sub set $az_sub; gc login browser --arc_space $gc_arc_space
}

### app ################################################################################

# app - check for Mac OS updates
alias osu = softwareupdate -l

# app - ngrok as 1password plugin
alias ngrok = op plugin run -- ngrok

# app - terraform
alias tf = terraform

# app - neovim editor
alias e = /opt/homebrew/bin/nvim

# app - do daily brew
alias br = do {brew update; brew upgrade; brew cleanup; brew doctor}

# app - op select service principal -q $query | az login principal
def sp [
    query: string = ''
] {
    op select service principal -q $query | az login principal
}

# app - az login browser with an selected op users
def us [
    query: string = ''
] {
    op select user -q $query | az login browser
}

### cd ################################################################################

# cd/util - yazi file manager
def --env y [...args] {
	let tmp = (mktemp -t "yazi-cwd.XXXXXX")
	yazi ...$args --cwd-file $tmp
	let cwd = (open $tmp)
	if $cwd != "" and $cwd != $env.PWD {
		cd $cwd
	}
	rm -fp $tmp
}

# cd/util - list of git repos used with gd command
def git-repos [
    --update
] {
    # https://www.nushell.sh/book/loading_data.html#nuon
    let master = '~/.gitrepos.nuon'
    let gitRepos = { glob /**/.git --depth 6 --no-file | path dirname | wrap git-repo }

    if $update or (not ($master | path exists)) {
        do $gitRepos | save --force $master
    }

    $master | open
}

# cd - to repo root from arbitrary sub folder
def --env rr [] {
    use std repeat

    pwd                                         # current path
    | path relative-to ('~' | path expand)      # the path `below` home
    | path split                                # into a list
    | reverse                                   # reversed, current folder (deepest) is 1st elem
    | enumerate                                 # introduce index
    | each {|it|                                # check if dot-git exists somewhere upwards to home
        let dots = ('.' | repeat ($it.index + 1) | str join)
        {dots: $dots, rr: ($dots | path join '.git' | path exists)}
    }
    | where $it.rr                              # filter rr and eventually do cd with enough dots
    | match $in {
        [] => { return null }
        $l => { $l | get 0.dots | cd $in }
    }
}

# # cd - to git repo
# def --env gd [
#     query: string = ''
# ] {
#     git-repos | fzf select $query | if $in != null {cd $in.git-repo}
# }

# Definer en custom command for git-repo dialog
def --env gd [editor: string = ""] {
  tv git-repos . |
  if $in != "" {
    cd $in
    match $editor {
      "i" => { ~/idea . }
      "r" => { ~/rustrover . }
      "z" => { zed . }
      _ => { }  # kun bytte folder
   }
  }
}

# cd - to terraform solution within a repo
def --env td [
    query: string = ''
] {
    rr # as starting point for the glob
    glob **/*.tf --depth 10 | path dirname | uniq | wrap 'terraform-folder' | fzf select $query | if $in != null {cd $in.terraform-folder}
}

### git ###############################################################################

# git - gently try to delete merged branches, excluding the checked out one
def gbd [branch: string = main] {
    git checkout $branch
    git pull
    git branch --merged
    | lines
    | where $it !~ '\*'
    | str trim
    | where $it != 'master' and $it != 'main'
    | each { |it| git branch -d $it }}

# git - switch branch
def gb [
    query: string = ''
] {
    git branch
    | lines
    | enumerate
    | where not ($it.item | str starts-with '*')
    | match $in {
        [] => {
            print 'Current branch is the only one'
            return null
        }
        _ => $in
    }
    | par-each --keep-order {|r| {item: ($r.item | str trim)}}
    | fzf select $query
    | if $in != null {git checkout $in.item}
}


### iTerm ###############################################################################

# iterm - new tab
def nt [cmd?: string] {
    let dir = $env.PWD
    let run = if ($cmd | is-empty) { "" } else { $"; ($cmd)" }
    osascript -e $"
        tell application \"iTerm2\"
            tell current window
                set originalTab to current tab
                create tab with default profile
                tell current session of current tab
                    write text \"cd '($dir)'($run)\"
                end tell
                select originalTab
            end tell
        end tell
    "
}

# code2rm.nu — Pakk et kildekode-repo som syntax-highlighted EPUB for reMarkable
#
# EPUB gir klikkbar TOC, kapittelnavigasjon og fleksibel fontstørrelse
# på brettet — mye bedre enn PDF for lange kodesamlinger.
#
# Struktur: Filer grupperes etter mappe → mappe blir kapittel (H1),
# filnavn blir seksjon (H2). Strukturen leses av reMarkables innebygde
# leser-TOC (tapp midt på skjermen, finn liste-ikonet).
#
# Krever: pandoc (≥3.0)

# CSS: venstrejustert alt (unngå reMarkable-default "justify" som strekker linjer),
# kompakt TOC, monospace filnavn, kode med linjebryting.
def default-css [] {
    'body, p, li, pre, code, nav, h1, h2, h3 {
  text-align: left !important;
  hyphens: none;
  -webkit-hyphens: none;
}
body { font-family: serif; line-height: 1.5; }
h1 {
  page-break-before: always;
  font-size: 1.4em;
  border-bottom: 1px solid #888;
  padding-bottom: 0.3em;
  margin-top: 0;
}
h1:first-of-type { page-break-before: avoid; }
h2 {
  font-family: "DejaVu Sans Mono", "Liberation Mono", monospace;
  font-size: 1.0em;
  font-weight: bold;
  margin-top: 1.8em;
  margin-bottom: 0.4em;
  color: #333;
}
pre, code {
  font-family: "DejaVu Sans Mono", "Liberation Mono", monospace;
  font-size: 0.78em;
}
pre {
  white-space: pre-wrap;
  overflow-wrap: break-word;
  background: #f5f5f5;
  padding: 0.5em;
  line-height: 1.35;
  margin: 0.5em 0;
}
code { background: #f0f0f0; padding: 0.1em 0.3em; }
pre code { background: transparent; padding: 0; font-size: 1em; }'
}

export def code2rm [
    repo: path = "."                        # Repo-rot
    --pattern (-p): string = "**/*.hs"      # Glob (relativt til repo)
    --exclude (-e): list<string> = [".stack-work" "dist-newstyle" ".git" "node_modules" ".cabal-sandbox"]
    --output (-o): path                     # Output-EPUB (default: <repo>.epub)
    --title (-t): string                    # Dokumenttittel (default: repo-navn)
    --author (-a): string = "Torstein Nesby"
    --language (-l): string = "haskell"     # Språk for fenced blocks
    --lang: string = "nb"                   # Dokumentspråk (nb|en|...)
    --highlight-style: string = "tango"     # tango|kate|pygments|haddock|breezedark|espresso
    --strip-prefix: string = ""             # Fjern fra start av stier før gruppering (f.eks. "src/")
    --flat                                  # Ingen gruppering — hver fil som eget kapittel (gammel oppførsel)
    --keep-md                               # Behold mellomliggende .md for debugging
    --css: path                             # Custom CSS (overstyrer default)
    --open                                  # Åpne EPUB-en etter generering
] {
    let repo_abs = ($repo | path expand)
    let repo_name = ($repo_abs | path basename)
    let doc_title = ($title | default $repo_name)
    let out = ($output | default $"($repo_name).epub" | path expand)

    # Finn filer og filtrer
    let pattern_full = ($repo_abs | path join $pattern)
    let all_files = (glob $pattern_full | sort)
    let files = ($all_files | where {|f|
        let rel = ($f | path relative-to $repo_abs)
        not ($exclude | any {|ex| ($rel | str contains $ex) })
    })
    if ($files | is-empty) {
        error make { msg: $"Ingen filer matcher '($pattern)' i ($repo_abs)" }
    }
    print $"Fant ($files | length) filer i ($repo_name)"

    # Lag entries: for hver fil, finn "chapter" (mappe) og "section" (filnavn)
    let entries = ($files | each {|f|
        let rel_raw = ($f | path relative-to $repo_abs)
        # Strip prefix hvis oppgitt
        let rel = (if ($strip_prefix | is-empty) {
            $rel_raw
        } else {
            if ($rel_raw | str starts-with $strip_prefix) {
                $rel_raw | str substring ($strip_prefix | str length)..
            } else {
                $rel_raw
            }
        })
        let parent = ($rel | path dirname)
        let base = ($rel | path basename)
        let chapter = (if ($parent | is-empty) { "(rot)" } else { $parent })
        {chapter: $chapter, base: $base, rel: $rel, file: $f}
    } | sort-by chapter base)

    let today = (date now | format date '%Y-%m-%d')
    let yaml = $"---
title: \"($doc_title)\"
author: \"($author)\"
date: \"($today)\"
lang: ($lang)
---

"

    # Bygg markdown
    mut body = $yaml
    if $flat {
        # Gammel oppførsel: hver fil som eget kapittel
        for entry in $entries {
            let content = (open --raw $entry.file)
            $body = $body + $"# ($entry.rel)\n\n```($language)\n($content)\n```\n\n"
        }
    } else {
        # Hierarkisk: mappe = H1 kapittel, filnavn = H2 seksjon
        mut current_chapter = ""
        for entry in $entries {
            if $entry.chapter != $current_chapter {
                $body = $body + $"# ($entry.chapter)\n\n"
                $current_chapter = $entry.chapter
            }
            let content = (open --raw $entry.file)
            $body = $body + $"## ($entry.base)\n\n```($language)\n($content)\n```\n\n"
        }
    }

    let tmp_md = (mktemp --suffix ".md")
    $body | save -f $tmp_md

    # CSS-håndtering
    let css_file = (if $css == null {
        let f = (mktemp --suffix ".css")
        default-css | save -f $f
        $f
    } else {
        $css | path expand
    })

    print $"Kjører pandoc → ($out)"
    (pandoc $tmp_md
        -o $out
        --split-level 1
        --highlight-style $highlight_style
        --css $css_file
        --metadata $"title=($doc_title)"
        --metadata $"author=($author)"
        --metadata $"lang=($lang)")

    if not ($out | path exists) {
        error make { msg: $"Pandoc feilet — ingen output på ($out). Beholder ($tmp_md) for debug." }
    }

    if $keep_md {
        let kept = ($out | str replace ".epub" ".md")
        mv $tmp_md $kept
        print $"Beholdt markdown: ($kept)"
    } else {
        rm $tmp_md
    }
    if $css == null { rm $css_file }

    let size_kb = ((ls $out | get size.0) / 1kb | math round)
    print $"✓ ($out) \(($size_kb) KiB\)"

    if $open { ^open $out }
}

# Hjelper: generer sammenligning av highlight-styles for ett sett filer.
export def code2rm-style-test [
    repo: path = "."
    --pattern (-p): string = "**/*.hs"
    --language (-l): string = "haskell"
    --strip-prefix: string = ""
    --styles: list<string> = [tango kate pygments haddock breezedark espresso]
    --out-dir: path = "/tmp/syntax-test"
] {
    mkdir $out_dir
    for style in $styles {
        let out = ($out_dir | path join $"test-($style).epub")
        print $"\n── ($style) ──"
        code2rm $repo --pattern $pattern --language $language --strip-prefix $strip_prefix --highlight-style $style --output $out
    }
    print $"\nFerdig. Se ($out_dir)/"
    ^open $out_dir
}
