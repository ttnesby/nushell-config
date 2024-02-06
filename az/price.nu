# see https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices?view=rest-cost-management-2023-11-01

# module az/priceList - get price list for all az services
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