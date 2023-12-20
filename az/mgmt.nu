use ./policy.nu

# module az/mgmt - get management group hierarchy from the start node
export def main [
    start: string = 'b3031fb2-0a12-44be-a964-c0132fd251b0'
] {
    az account management-group show --no-register --name $start -e -r 
    | from json 
    | iterate
}

def iterate [
] {
    let node = $in

    if ($node == null) or ($node.type != 'Microsoft.Management/managementGroups') { return null }

    [{
        displayName: $node.displayName
        id: $node.id
        url: ('https://portal.azure.com/#view/Microsoft_Azure_Policy/PolicyMenuBlade/~/Assignments/scope/' + ($node.id | url encode --all))
        assignments: ($node.id | policy assignment)
    }] 
    | append ($node.children | par-each --keep-order {|node| $node | iterate})
}
