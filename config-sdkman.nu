# SDKMAN auto-env for Nushell
# Reads .sdkmanrc on directory change and switches SDK versions

const SDKMAN_DIR = "~/.sdkman"

def parse-sdkmanrc [] {
    let rc = ($env.PWD | path join ".sdkmanrc")
    if not ($rc | path exists) { return [] }
    open --raw $rc
    | lines
    | where { |line| ($line | str trim) != "" and not ($line | str starts-with "#") }
    | each { |line|
        let parts = ($line | split column "=" | first)
        { candidate: ($parts.column0 | str trim), version: ($parts.column1 | str trim) }
    }
}

def --env sdkman-switch [candidate: string, version: string] {
    let sdkman = ($SDKMAN_DIR | path expand)
    let candidate_dir = $"($sdkman)/candidates/($candidate)/($version)"
    if not ($candidate_dir | path exists) {
        print $"(ansi yellow)sdkman: ($candidate) ($version) not installed(ansi reset)"
        return
    }
    let bin_dir = $"($candidate_dir)/bin"

    $env.PATH = ($env.PATH
        | where { |p| not ($p | str contains $"/candidates/($candidate)/") }
        | prepend $bin_dir)

    if $candidate == "java" {
        $env.JAVA_HOME = $candidate_dir
    }
}

# Call this from the PWD hook in config-pwd-hook.nu
export def --env sdkman-auto-env [] {
    let sdkmanrc = ($env.PWD | path join ".sdkmanrc")
    if ($sdkmanrc | path exists) {
        let entries = (parse-sdkmanrc)
        for e in $entries {
            sdkman-switch $e.candidate $e.version
        }
    } else {
        # Restore defaults using for-loop
        let sdkman = ($SDKMAN_DIR | path expand)
        let candidates_dir = $"($sdkman)/candidates"
        if ($candidates_dir | path exists) {
            let candidates = (ls $candidates_dir | where type == dir)
            for c in $candidates {
                let current_bin = ($c.name | path join "current/bin")
                if ($current_bin | path exists) {
                    sdkman-switch ($c.name | path basename) "current"
                }
            }
        }
    }
}
