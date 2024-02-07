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

# module az/price - get price list for all az services
export def main [
    --currency-code: string = 'NOK'
    --arm-region-name: string = 'norwayeast'

] {

    let url_rec = {
        scheme: 'https'
        host: 'prices.azure.com'
        path: '/api/retail/prices'
    }

    let params = {
        'api-version': '2023-01-01-preview'
        currencyCode: $currency_code
        armRegionName: $arm_region_name
    }

    mut url = ({...$url_rec, ...{params: $params}} | url join)
    mut continue = true
    mut items = []

    while $continue {

        let res = http get --allow-errors --full $url
        if $res.status == 200 {
            $continue = $res.body.NextPageLink != null
            $url = $res.body.NextPageLink
            $items = ($items | append $res.body.Items)
            print $url
        } else {
            $continue = false
        }
    }

    $items
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

# module az/price - create sqlite tables for azure price list
export def 'sqlite create tables' [
] {

    # schema overview
    # (http get --allow-errors --full "https://prices.azure.com/api/retail/prices?api-version=2023-01-01-preview").body.Items | each {|r| $r | describe -d | $in.columns} | reduce --fold {} {|it, acc| $acc | merge $it}

    let existing_tables = (stor open | schema | $in.tables | columns)

    if ($existing_tables | all {|e| $e != $sqlite_t_price}) { create price table}
    if ($existing_tables | all {|e| $e != $sqlite_t_savings}) { create savings table}
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

# module az/price - get price list for all az services as sqlite database
export def 'into sqlite' [
    --currency-code: string = 'NOK'
] { 

    def next [url: string] {
        print $url
        match (http get --allow-errors --full $url) {
            {headers: _, body: $b, status: 200} => {
                $b.Items | sqlite insert
                $b.NextPageLink
            }
            _ => { null }
        }
    }
    
    mut next_url = (compile url --currency-code $currency_code)
    while ($next_url != null) { $next_url = (next $next_url) }
}