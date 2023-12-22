use ./helpers/http-as-file.nu

export def assignment [] {
    let scope = $in
    let policyDefinitionBlade = 'https://portal.azure.com/#view/Microsoft_Azure_Policy/PolicyDetailBlade/definitionId/'

    ^az policy assignment list --scope $scope
    | from json
    | par-each --keep-order {|r|
        {
            displayName: $r.displayName
            name: $r.name
            policyDefinition: (http-as-file --name $r.name --url ($policyDefinitionBlade + ($r.policyDefinitionId | url encode --all)))
        }
    }
}