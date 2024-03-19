use ../az/helpers/cost-cache.nu

const dataset = 'azure_cost_management'
const cost_schema = 'cost_schema'
const cost_table = $'($dataset).subscriptions'

# module gc/cost - load cost CSV  in ~/.azcost/*.csv into big query
export def load [
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
    (do { ^bq load --source_format=PARQUET $cost_table $parquet_file } | complete).exit_code == 0
}

# module gc/cost - schema retrives a json based schema from a temporary table loaded with parquet file
export def schema [
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
            ^bq rm --table --force $table_name
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

# module gc/cost - create/delete the cost table for subscriptions
export def table [
    --delete
] {
    let schema_file = (cost-cache root | path join $'($cost_schema).json' | path expand)
    let table_exists = ($cost_table in (dataset tables))

    if (not $delete) {
        if $table_exists {return $'($cost_table) already exists'}

        do {^bq mk --table --schema $schema_file --time_partitioning_field BillingPeriodStartDate --time_partitioning_type DAY $cost_table}
        | complete
        | match $in {
            {stdout: _, stderr: _, exit_code: 0} => {print $'($cost_table) has been created'}
            {stdout: _, stderr: $err, exit_code: 1} => {print -e $'could not create ($cost_table) - ($err)'}
        }
    } else {
        if (not $table_exists) {return $"($cost_table) doesn't exist, nothing to delete"}

        do {^bq rm --table --force $cost_table}
        | complete
        | match $in {
            {stdout: _, stderr: _, exit_code: 0} => {print $'($cost_table) has been deleted'}
            {stdout: _, stderr: $err, exit_code: 1} => {print -e $'could not delete ($cost_table) - ($err)'}
        }
    }
}

# module gc/cost - list all tables in relevant dataset
export def "dataset tables" [] {
    ^bq ls --format=json $dataset
    | from json
    | where type == TABLE
    | $in.tableReference
    | each {|r| $'($r.datasetId).($r.tableId)'}
}