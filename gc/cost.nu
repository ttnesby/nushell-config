# module gc/cost - load cost CSV  in ~/.azcost/*.csv into big query
export def loadCost-gc [] {
    ls ~/.azcost/*.csv
    | each {|f|
        bq load --source_format=CSV --skip_leading_rows=1 --autodetect --format=json delta-sanctum-793:7e260459_3026_4653_b259_0347c0bb5970.cost $f.name
    }
}