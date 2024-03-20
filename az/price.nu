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

    let price_json = (as json file)    
    dfr open $price_json | dfr to-parquet (price-cache parquet)
}