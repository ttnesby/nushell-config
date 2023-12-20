export def assignment [] {
    ^az policy assignment list --scope $in 
    | from json 
    | par-each --keep-order {|r|
        {
            displayName: $r.displayName
            name: $r.name
            url: ('https://portal.azure.com/#view/Microsoft_Azure_Policy/PolicyDetailBlade/definitionId/' + ($r.policyDefinitionId | url encode --all))
        }
    }
}