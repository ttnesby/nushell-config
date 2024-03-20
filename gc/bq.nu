use ../az/helpers/cost-cache.nu
use ../az/helpers/price-cache.nu

const dataset = 'azure_cost_management'

const cost_schema = 'cost_schema'
const cost_table = $'($dataset).subscriptions'

const price_schema = 'price_schema'
const price_table = $'($dataset).price_list'

# module gc/cost - create/delete the dataset
export def dataset [
    --delete
] {
    let exists = ($dataset in (^bq ls --format=json azure_cost_management | from json | where type == TABLE | $in.tableReference | each {|r| $r.datasetId}))

    if (not $delete) {
        if $exists {return $'($dataset) already exists'}

        do {^bq mk --dataset $dataset}
        | complete
        | match $in {
            {stdout: _, stderr: _, exit_code: 0} => {print $'($dataset) has been created'}
            {stdout: _, stderr: $err, exit_code: 1} => {print -e $'could not create ($dataset) - ($err)'}
        }
    } else {
        if (not $exists) {return $"($dataset) doesn't exist, nothing to delete"}

        do {^bq rm --dataset --force $dataset}
        | complete
        | match $in {
            {stdout: _, stderr: _, exit_code: 0} => {print $'($dataset) has been deleted'}
            {stdout: _, stderr: $err, exit_code: 1} => {print -e $'could not delete ($dataset) - ($err)'}
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
export def "table cost" [
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

# module gc/cost - create/delete the price table
export def "table price" [
    --delete
] {
    let schema_file = (price-cache dir | path join $'($price_schema).json' | path expand)
    let table_exists = ($price_table in (dataset tables))

    if (not $delete) {
        if $table_exists {return $'($price_table) already exists'}

        do {^bq mk --table --schema $schema_file $price_table}
        | complete
        | match $in {
            {stdout: _, stderr: _, exit_code: 0} => {print $'($price_table) has been created'}
            {stdout: _, stderr: $err, exit_code: 1} => {print -e $'could not create ($price_table) - ($err)'}
        }
    } else {
        if (not $table_exists) {return $"($price_table) doesn't exist, nothing to delete"}

        do {^bq rm --table --force $price_table}
        | complete
        | match $in {
            {stdout: _, stderr: _, exit_code: 0} => {print $'($price_table) has been deleted'}
            {stdout: _, stderr: $err, exit_code: 1} => {print -e $'could not delete ($price_table) - ($err)'}
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
    (do { ^bq load --source_format=PARQUET $cost_table $parquet_file } | complete).exit_code == 0
}

# module gc/cost - load price list
export def "load price" [] {
    let parquet_file = (price-cache parquet)

    if (not ($parquet_file | path exists)) {
        print -e $"($parquet_file) doesn't exist"
        return false
    }    

    # delete relevant partition
    if (do {^bq rm --table --force $price_table}|complete).exit_code != 0 {
        print -e $'Cannot delete table ($price_table)'
        return false
    }

    # load new data
    (do { ^bq load --source_format=PARQUET $price_table $parquet_file } | complete).exit_code == 0
}

# module gc/cost - list all tables in relevant dataset
export def "dataset tables" [] {
    ^bq ls --format=json $dataset
    | from json
    | where type == TABLE
    | $in.tableReference
    | each {|r| $'($r.datasetId).($r.tableId)'}
}