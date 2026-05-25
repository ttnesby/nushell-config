# Create a new branch with timestamp, empty commit, and draft PR
export def create [
    branch_name: string    # Base name for the branch (e.g. ttn/test)
    commit_message: string # Message for the empty commit and PR title
    --base: string = "master" # Base branch to create from and PR against
] {
    let timestamp = (date now | format date "%Y%m%d%H%M")
    let full_branch_name = $"($branch_name)-($timestamp)"
    let full_commit_message = $"($commit_message)-($timestamp)"

    print $"Fetching latest ($base)..."
    git fetch origin $base

    print $"Creating branch: ($full_branch_name)"
    git checkout -b $full_branch_name $"origin/($base)"

    print $"Creating empty commit: ($commit_message)"
    git commit --allow-empty -m $commit_message

    print "Pushing to origin..."
    git push -u origin $full_branch_name

    print $"Creating draft PR against ($base)..."
    try {
        gh pr create --title $full_commit_message --body $"Auto-generated PR from branch ($full_branch_name)" --base $base --draft
        print "Pull request created successfully!"
    } catch {
        print "Failed to create PR. Check that 'gh' CLI is installed and authenticated."
        print $"Manual: gh pr create --title '($commit_message)' --body 'Auto-generated PR' --base ($base) --draft"
    }
}
