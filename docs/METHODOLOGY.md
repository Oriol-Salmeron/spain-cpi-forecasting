# Methodology

## Target variable and data construction

The target is Spain's headline CPI year-over-year inflation rate, expressed as a percentage. The historical observations are retrieved from the Spanish National Statistics Institute (INE) Tempus3 API. The pipeline combines the historical series on the 2021 base with the current series on the 2025 base. For overlapping months, the current-base series takes precedence. A monthly continuity check stops execution if there are missing months rather than imputing unsupported values.

The timestamp associated with each observation is normalized to the first day of the month. This is a monthly indexing convention, not an assertion that the observation was publicly released on that date.

## Forecasting models

### Seasonal ARIMA

The model is selected using `forecast::auto.arima()` on a monthly time series with frequency 12. The fitted model forecasts one to three months ahead.

### Naive benchmarks

- **Naive:** every future horizon equals the latest observed inflation rate.
- **Seasonal Naive (12):** future forecasts repeat the value from the corresponding month one year earlier.
- **Naive with Drift:** random-walk benchmark with a linear drift estimated from the training history.

### Exponential smoothing and Theta

ETS models are fitted with `forecast::ets()`, while Theta forecasts are generated with `forecast::thetaf()`.

### Random Forest

The Random Forest uses 600 trees and a fixed seed. Predictor features include lags 1, 2, 3, 6 and 12; trailing three- and six-month means; a trailing six-month standard deviation; and sine/cosine transformations of the target month. Features use historical observations only. For horizons beyond one month, the model is forecast recursively by appending each generated forecast to its history.

## Rolling-origin backtest

The pipeline evaluates up to 60 forecast origins near the end of the historical series, using an expanding training window. At each origin, models forecast the next three months where sufficient data are available. This produces horizon-specific error estimates and lets the analysis compare models using a common set of target periods.

For an actual value \(y_t\) and forecast \(\hat{y}_t\), the error convention is:

\[
e_t = y_t - \hat{y}_t
\]

The two headline metrics are:

\[
\mathrm{MAE} = \frac{1}{n}\sum_{t=1}^{n}|e_t|,
\qquad
\mathrm{RMSE} = \sqrt{\frac{1}{n}\sum_{t=1}^{n}e_t^2}
\]

Both are measured in percentage points of year-over-year inflation. Lower values are better. RMSE penalizes large individual errors more heavily than MAE.

## Fixed-weight ensembles

The ensemble stage compares four prespecified combinations:

- 50% ARIMA + 50% Naive
- 75% ARIMA + 25% Naive
- 75% ARIMA + 25% Random Forest
- Equal-weight mean of ARIMA, Naive and Random Forest

Weights are not optimized on the same backtest sample, reducing the risk of tuning directly to the evaluation results.

## Bias adjustment

For each model and horizon, the pipeline estimates a correction from recent historical forecast errors and compares the raw and corrected predictions. In the archived run, corrected MAE was higher for all seven individual models. Therefore, the evidence from this sample does not support routinely applying the correction.

Important caveat: dates are stored at monthly frequency using month-start timestamps. The pipeline does not incorporate the exact date on which each CPI value was released by INE. Its target-date-versus-origin-date filter is therefore only a simplified timing convention, not a full real-time-vintage backtest. A stricter evaluation would use actual publication dates and the data vintages available to forecasters at each origin.

## Forecast horizon and archived run

The submitted snapshot was generated on 18 October 2026 with data through September 2026, and includes forecasts for October, November and December 2026. The cached output files preserve those values. Re-running the scripts retrieves current INE data and should be expected to alter the estimates and metrics.
