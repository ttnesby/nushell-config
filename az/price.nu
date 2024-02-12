use ./helpers/price-cache.nu

# see https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices?view=rest-cost-management-2023-11-01

def 'compile url' [
    --currency-code: string = 'NOK'
] {
    let url_rec = {
        scheme: 'https'
        host: 'prices.azure.com'
        path: '/api/retail/prices'
    }

    let params = {
        'api-version': '2023-01-01-preview'
        currencyCode: $currency_code
    }

    {...$url_rec, ...{params: $params}} | url join
}

def next [url: string] {

    let rec = {|url: string, items: list<any>| {next_url: $url, items: $items}}

    print $url
    match (http get --allow-errors --full $url) {
        {headers: _, body: $b, status: 200} => { do $rec $b.NextPageLink $b.Items }
        _ => { do $rec null [] }
    }
}

# module az/price - get price list for all az services as json file (~442 MB)
export def 'as json file' [--currency-code: string = 'NOK'] {

    mut next_url = (compile url --currency-code $currency_code)
    mut items = []

    while ($next_url != null) {
        let rec = (next $next_url)
        $items = ($items | append $rec.items)
        $next_url = $rec.next_url
    }

    $items | to json | save --force (price-cache json)
    price-cache json
}

# module az/price - get price list for all az services as parquet file (~25 MB)
export def 'as parquet file' [--currency-code: string = 'NOK'] {
    
    # ideally, work with dfr only, but there are dfr schema details (savingsPlan, effectiveEndDate, ...)
    # cheating with converting full json to parquet
    
    dfr open (as json file) | dfr to-parquet (price-cache parquet)
}

const sqlite_t_price = price
const sqlite_t_savings = savings

def 'create price table' [] {
    let schema_price = {
        currencyCode: str
        tierMinimumUnits: float
        retailPrice: float
        unitPrice: float
        armRegionName: str
        location: str
        effectiveStartDate: datetime
        meterId: str
        meterName: str
        productId: str
        skuId: str
        productName: str
        skuName: str
        serviceName: str
        serviceId: str
        serviceFamily: str
        unitOfMeasure: str
        type: str
        isPrimaryMeterRegion: bool
        armSkuName: str
        reservationTerm: str
        effectiveEndDate: datetime
    }

    stor create -t $sqlite_t_price -c $schema_price
}

def 'create savings table' [] {
    let schema_savings = {
        meterId: str
        unitPrice: float
        retailPrice: float
        term: str
    }

    stor create -t $sqlite_t_savings -c $schema_savings
}

def 'sqlite create tables' [
] {

    # schema overview
    # (http get --allow-errors --full "https://prices.azure.com/api/retail/prices?api-version=2023-01-01-preview").body.Items | each {|r| $r | describe -d | $in.columns} | reduce --fold {} {|it, acc| $acc | merge $it}

    stor reset
    create price table
    create savings table
}

const savings_plan = savingsPlan

def 'has savings plan' [] { $in | columns | any {|e| $e == $savings_plan} }

def 'insert price' [] { stor insert -t $sqlite_t_price -d $in }

def 'insert savings' [] { stor insert -t $sqlite_t_savings -d $in }

def 'sqlite insert' [] {
    $in
    | par-each {|r: any|
        if ($r | (has savings plan)) {
            $r | reject $savings_plan | insert price
            $r | get $savings_plan | each {|s| {meterId: $r.meterId, ...$s } | insert savings}
        } else {
            $r | insert price
        }
    }
}

# module az/price - get price list for all az services as sqlite database file (~197 MB)
export def 'as sqlite file' [--currency-code: string = 'NOK'] {

    sqlite create tables

    mut next_url = (compile url --currency-code $currency_code)

    while ($next_url != null) {
        let rec: record<next_url: string, items: list<any>> = next $next_url
        $rec.items | sqlite insert
        $next_url = $rec.next_url
    }

    stor export -f (price-cache sqlite)
    price-cache sqlite
}