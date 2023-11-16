use ./helpers/cost-cache.nu
use ./cost.nu

# module az/platform - download platform cost CSVs (connectivity, management, identity) for january..current_months - 1
export def 'download cost' [] {

    let platformSubs = [575a53ac-e2a1-4215-b45f-028ec4f6f2a5, 7e260459-3026-4653-b259-0347c0bb5970, 9f66c67b-a3b2-45cb-97ec-dd5017e94d89]
    let n = date now | date to-record

    1..($n.month - 1)
    | each {|m| # NB! not doing par-each due to rate limiting (429)
        let p = ($'($n.year)-($m)-1' | into datetime | format date "%Y%m")
        $platformSubs | par-each {|s| 
          let file = (cost-cache file -s $s -p $p)
          if not ( $file | path exists) {$s | cost --periode $p} else { $file } 
        }
    }
}

# module az/platform - return aggregated (monthly cost), min,max,mean,std, and total for january..current_month - 1
export def 'cost trend' [] {
    let platformSubs = [575a53ac-e2a1-4215-b45f-028ec4f6f2a5, 7e260459-3026-4653-b259-0347c0bb5970, 9f66c67b-a3b2-45cb-97ec-dd5017e94d89]
    let n = date now | date to-record

    # get data frames for all subscriptions and months until current month
    let dFrames = 1..($n.month - 1)
    | par-each {|m|
        let p = ($'($n.year)-($m)-1' | into datetime | format date "%Y%m")
        $platformSubs | cost --periode $p | par-each {|f| dfr open $f }
    }
    | flatten

    # reduce all data frames into a single frame
    let theFrame = $dFrames | skip 1 | reduce -f ($dFrames | first) {|df, acc| $df | dfr append $acc --col }

    # do some basic calculation (min, max, mean, std, sum) for platform subscriptions
    $theFrame
    | dfr with-column ($theFrame | dfr get BillingPeriodEndDate | dfr as-datetime "%m/%d/%Y" | dfr strftime '%m') --name BillingMonth
    | dfr with-column ($theFrame | dfr get BillingPeriodEndDate | dfr as-datetime "%m/%d/%Y" | dfr strftime '%Y') --name BillingYear
    | dfr group-by SubscriptionName BillingYear BillingMonth
    | dfr agg [
        (dfr col SubscriptionId | dfr first)
        (dfr col CostInBillingCurrency | dfr sum | dfr as Sum)
    ]
    | dfr sort-by SubscriptionName BillingMonth
    | dfr group-by SubscriptionName BillingYear
    | dfr agg [
        (dfr col Sum | dfr min | dfr as MonthlyMin)
        (dfr col Sum | dfr max | dfr as MonthlyMax)
        (dfr col Sum | dfr mean | dfr as MonthlyMean)
        (dfr col Sum | dfr std | dfr as MonthlyStd)
        (dfr col Sum | dfr sum | dfr as SumYear)
    ]
    | dfr sort-by SubscriptionName
}