use ../az/helpers/cost-cache.nu
use ../az/helpers/price-cache.nu

const dataset = 'azure_cost_management'

const cost_schema = 'cost_schema'
const cost_table = $'($dataset).subscriptions'

const price_schema = 'price_schema'
const price_table = $'($dataset).price_list'

# module gc/cost - create/delete relevant price/cost data
export def main [
    --delete
] {
    if not $delete {
        dataset
        schema price
        schema cost -p 202401
        table -t $cost_table
        load price # will delete and create table

        # load all available cost
        ls (cost-cache root | path join '**' | path expand | into glob) 
        | get name 
        | each {|d| $d | path split | last} 
        | par-each {|p| load cost -p $p} 
        | all {|e| $e}
    } else {
        table -t $cost_table --delete
        table -t $price_table --delete
        dataset --delete
    }
} 

# module gc/cost - create/delete the dataset
export def dataset [
    --delete
] {
    let exists = ($dataset in (project datasets))

    if (not $delete and $exists) { return (print $'($dataset) already exists'; true) }
    if ($delete and not $exists) { return (print $"($dataset) doesn't exist, nothing to delete"; true) }

    if (not $delete) {
        do {^bq mk --dataset $dataset}
        | complete
        | match $in {
            {stdout: _, stderr: _, exit_code: 0} => {print $'($dataset) has been created'; true}
            {stdout: _, stderr: $err, exit_code: 1} => {print -e $'could not create ($dataset) - ($err)'; false}
        }
    } else {
        do {^bq rm --dataset --force $dataset}
        | complete
        | match $in {
            {stdout: _, stderr: _, exit_code: 0} => {print $'($dataset) has been deleted'; true}
            {stdout: _, stderr: $err, exit_code: 1} => {print -e $'could not delete ($dataset) - ($err)'; false}
        }
    }
}

# module gc/cost - retrives a json based cost schema from a temporary table loaded with parquet file
export def "schema cost" [
    --periode_name(-p): string  # use a cost period as reference for schema creation
] {
    let parquet_file = (cost-cache dir -p $periode_name | path join $'($periode_name).parquet' | path expand)
    let table_name = $'($dataset).($cost_schema)_($periode_name)'
    let empty_schema = '[]'
    let schema_file = (cost-cache root | path join $'($cost_schema).json' | path expand)

    if (not ($parquet_file | path exists)) {
        print -e $"($parquet_file) doesn't exist"
        return $empty_schema
    }

    if (do { ^bq load --source_format=PARQUET $table_name $parquet_file } | complete).exit_code != 0 {
        print -e $"could not load ($parquet_file) into ($table_name)"
        return $empty_schema
    }

    do { ^bq show --format=prettyjson $table_name }
    | complete
    | match $in {
        {stdout: $stdout, stderr: _, exit_code: 0} => {
            do {^bq rm --table --force $table_name} | complete
            $stdout | from json | $in.schema.fields | to json
        }
        {stdout: _, stderr: $err, exit_code: 1} => {
            print -e $err
            return $empty_schema
        }
    }
    | save --force $schema_file

    $schema_file
}

# module gc/cost - retrives a json based price schema from a temporary table loaded with parquet file
export def "schema price" [] {
    let parquet_file = (price-cache parquet)
    let table_name = $'($dataset).($price_schema)'
    let empty_schema = '[]'
    let schema_file = (price-cache dir | path join $'($price_schema).json' | path expand)

    if (not ($parquet_file | path exists)) {
        print -e $"($parquet_file) doesn't exist"
        return $empty_schema
    }

    if (do { ^bq load --source_format=PARQUET $table_name $parquet_file } | complete).exit_code != 0 {
        print -e $"could not load ($parquet_file) into ($table_name)"
        return $empty_schema
    }

    do { ^bq show --format=prettyjson $table_name }
    | complete
    | match $in {
        {stdout: $stdout, stderr: _, exit_code: 0} => {
            do {^bq rm --table --force $table_name} | complete
            $stdout | from json | $in.schema.fields | to json
        }
        {stdout: _, stderr: $err, exit_code: 1} => {
            print -e $err
            return $empty_schema
        }
    }
    | save --force $schema_file

    $schema_file
}

# module gc/cost - create/delete price list table or cost table for subscriptions
export def table [
    --table_name(-t): string
    --delete
] {
    let schema_file = (
        if $table_name == $cost_table {
            cost-cache root | path join $'($cost_schema).json' | path expand
        } else {
            price-cache dir | path join $'($price_schema).json' | path expand
        }
    )
    let table_exists = ($table_name in (dataset tables))

    if (not $delete and $table_exists) {return (print $'($table_name) already exists'; true)}
    if ($delete and not $table_exists) {return (print $"($table_name) doesn't exist, nothing to delete"; true)}

    if (not $delete) {
        let creation = (
            if $table_name == $cost_table {
                {|| ^bq mk --table --schema $schema_file --time_partitioning_field BillingPeriodStartDate --time_partitioning_type DAY $cost_table}
            } else {
                {|| ^bq mk --table --schema $schema_file $price_table}
            }
        )
        do $creation
        | complete
        | match $in {
            {stdout: _, stderr: _, exit_code: 0} => {print $'($table_name) has been created'; true}
            {stdout: _, stderr: $err, exit_code: 1} => {print -e $'could not create ($table_name) - ($err)'; false}
        }
    } else {
        do {^bq rm --table --force $table_name}
        | complete
        | match $in {
            {stdout: _, stderr: _, exit_code: 0} => {print $'($table_name) has been deleted'; true}
            {stdout: _, stderr: $err, exit_code: 1} => {print -e $'could not delete ($table_name) - ($err)'; false}
        }
    }
}

# module gc/cost - load cost
export def "load cost" [
    --periode_name(-p): string
] {
    let parquet_file = (cost-cache dir -p $periode_name | path join $'($periode_name).parquet' | path expand)
    let partition = $'($cost_table)$($periode_name)01'

    if (not ($parquet_file | path exists)) {
        print -e $"($parquet_file) doesn't exist"
        return false
    }

    # delete relevant partition
    if (do {^bq rm --table --force $partition}|complete).exit_code != 0 {
        print -e $'Cannot delete partition ($partition)'
        return false
    }

    # load new data
    if (do { ^bq load --source_format=PARQUET $cost_table $parquet_file } | complete).exit_code == 0 {
        print $"cost periode ($periode_name) has been loaded"; true
    } else {
        print -e $"couldn't load cost periode ($periode_name)"; false
    }
}

# module gc/cost - load price list
export def "load price" [] {
    let parquet_file = (price-cache parquet)

    if (not ($parquet_file | path exists)) {
        print -e $"($parquet_file) doesn't exist"
        return false
    }

    if ((table -t $price_table --delete) and (table -t $price_table)) {
        if (do { ^bq load --source_format=PARQUET $price_table $parquet_file } | complete).exit_code == 0 {
            print "price list has been loaded"; true
        }
    } else {
        print -e "couldn't load price list"; false
    }
}

# module gc/cost - list all tables in relevant dataset
export def "dataset tables" [] {
    match (do {^bq ls --format=json $dataset} | complete) {
        {stdout: $out, stderr:_, exit_code: 0} if ($out | str length ) == 0 => {[]}
        {stdout: $out, stderr:_, exit_code: 0} if ($out | str length ) > 0 => {
            $out
            | from json
            | where type == TABLE
            | $in.tableReference
            | each {|r| $'($r.datasetId).($r.tableId)'}
        }
        _ => { print -e "couldn't get dataset information"; []}
    }
}

# module gc/cost - list all datasets in relevant project
export def "project datasets" [] {
    match (do {^bq ls --format=json} | complete) {
        {stdout: $out, stderr:_, exit_code: 0} if ($out | str length ) == 0 => {[]}
        {stdout: $out, stderr:_, exit_code: 0} if ($out | str length ) > 0 => {
            $out
            | from json
            | each {|r| $r.datasetReference.datasetId}
        }
        _ => { print -e "couldn't get dataset information"; []}
    }
}