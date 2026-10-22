# Data dictionary

The project contains two kinds of result files.

- `results/snapshot/`: selected output tables with English column names, copied and relabelled from the archived run dated 18 October 2026. These are intended for browsing, charts, and downstream reuse.
- `results/working/`: original intermediate outputs retained with their original filenames and column names so that the supplied multi-script R pipeline remains compatible. These files are replaced or updated when the R scripts are run.

## English-readable snapshot tables

| File | Description |
|---|---|
| `historical_cpi.csv` | Historical headline CPI year-over-year inflation values returned by INE. |
| `backtest_detail.csv` | Model forecasts, actual values and errors for each rolling-origin forecast. |
| `model_metrics.csv` | Overall raw and bias-adjusted MAE/RMSE for each individual model. |
| `horizon_metrics.csv` | Raw accuracy metrics separated by forecast horizon. |
| `ensemble_metrics.csv` | Aggregate errors for individual models and fixed-weight combinations. |
| `ensemble_horizon_metrics.csv` | Ensemble performance by horizon. |
| `forecast_snapshot_oct_dec_2026.csv` | Frozen point forecasts for October, November and December 2026. |
| `bias_correction_by_horizon.csv` | Bias-correction performance for each model and horizon. |
| `oct_dec_backtest_metrics.csv` | Historical October–December backtest metrics. |
| `model_forecast_comparison_oct_dec_2026.csv` | Raw, adjusted and recommended forecasts, with the original recommendation rule. |

## Common fields

- `date`: month timestamp normalized to the first day of the month.
- `cpi_yoy_pct`: year-over-year headline CPI inflation in percent.
- `origin_date`: final month in the training sample for a forecast.
- `target_date`: month being forecast.
- `horizon_months`: forecast horizon in months (1, 2, or 3).
- `model`: forecasting method or ensemble label.
- `forecast_pct`: forecast of year-over-year inflation, expressed in percentage points.
- `actual_pct`: observed year-over-year inflation for the target month.
- `error_actual_minus_forecast`: observed value minus the forecast.
- `MAE`: mean absolute error; lower values indicate lower average absolute error.
- `RMSE`: root mean squared error; lower values indicate lower squared-error loss.

The forecast snapshots do not contain seasonally adjusted month-over-month inflation or the CPI index level; they contain year-over-year inflation rates only.
