/// Closed SQL function identity; runtime signatures belong to the SQL binder.
public enum SQLAggregateFunction: String, Sendable, Hashable, CaseIterable {
    case count
    case sum
    case avg
    case min
    case max
    case stringAgg = "string_agg"
    case arrayAgg = "array_agg"
    case boolAnd = "bool_and"
    case boolOr = "bool_or"
    case every
    case bitAnd = "bit_and"
    case bitOr = "bit_or"
    case bitXor = "bit_xor"
    case jsonAgg = "json_agg"
    case jsonbAgg = "jsonb_agg"
    case jsonObjectAgg = "json_object_agg"
    case jsonbObjectAgg = "jsonb_object_agg"
    case varPop = "var_pop"
    case varSamp = "var_samp"
    case variance
    case stddevPop = "stddev_pop"
    case stddevSamp = "stddev_samp"
    case stddev
    case corr
    case covarPop = "covar_pop"
    case covarSamp = "covar_samp"
    case regrCount = "regr_count"
    case regrAvgx = "regr_avgx"
    case regrAvgy = "regr_avgy"
    case regrSxx = "regr_sxx"
    case regrSxy = "regr_sxy"
    case regrSyy = "regr_syy"
    case regrSlope = "regr_slope"
    case regrIntercept = "regr_intercept"
    case regrR2 = "regr_r2"
    case percentileCont = "percentile_cont"
    case percentileDisc = "percentile_disc"
    case mode
}
