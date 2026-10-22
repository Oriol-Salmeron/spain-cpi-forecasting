# Archived results — 18 October 2026

## Data cut-off

The latest historical observation used in this run is September 2026, with headline CPI year-over-year inflation of **4.9%**. The values below are forecasts prepared on 18 October 2026, not official releases for October–December.
The forecast tables report raw, unadjusted model forecasts. The companion 36-month chart shows the main script’s bias-adjusted ARIMA path for diagnostic comparison; the backtest indicates that this adjustment worsened MAE in the archived sample.

## Individual models

| Model | MAE (pp) | RMSE (pp) | Forecast errors |
|---|---:|---:|---:|
| ARIMA | 0.762 | 1.032 | 180 |
| Naive | 0.897 | 1.213 | 180 |
| ETS | 0.897 | 1.213 | 180 |
| Naive with Drift | 0.898 | 1.215 | 180 |
| Random Forest | 1.007 | 1.380 | 180 |
| Theta | 1.492 | 2.062 | 180 |
| Seasonal Naive (12) | 2.978 | 4.055 | 180 |

ARIMA was the best individual model overall. It had the lowest MAE at each horizon in the individual-model comparison.

## Fixed-weight ensembles

| Model | MAE (pp) | RMSE (pp) | Forecast errors |
|---|---:|---:|---:|
| ARIMA + Naive (75/25) | 0.741 | 1.024 | 180 |
| ARIMA + Random Forest (75/25) | 0.753 | 1.038 | 180 |
| ARIMA + Naive (50/50) | 0.758 | 1.054 | 180 |
| ARIMA | 0.762 | 1.032 | 180 |
| Mean of ARIMA, Naive and Random Forest | 0.819 | 1.128 | 180 |
| Naive | 0.897 | 1.213 | 180 |
| Random Forest | 1.007 | 1.380 | 180 |

The best ensemble by overall MAE was the 75/25 blend of ARIMA and Naive. This does not guarantee that it will outperform ARIMA in future months.

## Forecast snapshot

| Target month | ARIMA | Naive | Random Forest | ARIMA + Naive (50/50) | ARIMA + Naive (75/25) | ARIMA + Random Forest (75/25) | Three-model mean |
|---|---:|---:|---:|---:|---:|---:|---:|
| October 2026 | 5.025% | 4.900% | 4.794% | 4.962% | 4.993% | 4.967% | 4.906% |
| November 2026 | 5.139% | 4.900% | 4.894% | 5.019% | 5.079% | 5.078% | 4.978% |
| December 2026 | 5.179% | 4.900% | 4.876% | 5.039% | 5.109% | 5.103% | 4.985% |

## Bias-adjustment evaluation

The aggregate corrected MAE was higher than raw MAE for each individual model in the supplied run. The direction of the change was negative for every model, with reported MAE improvement values ranging from approximately −9.8% for ARIMA to −22.5% for Seasonal Naive (12). The default recommendation is therefore to use raw forecasts unless fresh out-of-sample evidence supports the adjustment.

## Interpretation

1. ARIMA is the strongest individual model on this sample.
2. A simple fixed-weight combination improves the overall MAE slightly, which supports testing ensembles but not assuming they always win.
3. Errors increase with the forecast horizon.
4. Seasonal Naive performs poorly in this series during the selected backtest window, partly because year-over-year inflation can change sharply across regimes.
5. The autumn-specific test contains only a small number of historical years and should be regarded as a supplementary robustness check.
