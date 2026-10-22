# Reproducibility notes

## Script order and dependencies

Run the four scripts from the repository root in the order listed in the README. Each script writes intermediate and final CSV files to `results/working/`. The charts are saved under `results/figures/`.

The extended comparison expects the historical series and core backtest produced by the first script. The ensemble script expects the extended backtest and current forecast-comparison file produced by the second script. Running a later script alone against a fresh folder will fail until its required upstream files exist.

## Snapshot versus live run

The CSVs in `results/snapshot/` and the publication-ready chart files preserve the output snapshot bundled with the original project. They are not automatically refreshed by a live run. The R scripts write their own working outputs to `results/working/`; compare those new outputs with the archived snapshot after each rerun.

## Validation checks before publication or use

- Confirm the latest INE observation date and value.
- Confirm that each forecast origin has sufficient training data and that no target-month actual value is included in training.
- Review warnings from failed ARIMA/ETS/Theta fits or unavailable Random Forest results.
- Check MAE/RMSE by horizon as well as in aggregate.
- Do not assume the month-start timestamp means the CPI observation was published on that date. For a strict real-time backtest, use the actual INE release calendar and point-in-time data vintages.
- Record the data cut-off, script version, and forecast origin date alongside every future forecast snapshot.

## Execution environment caveat

The scripts were reviewed and paths were refactored for the repository layout, but this build environment did not have R installed. The pipeline therefore has not been executed end-to-end here. Run it locally in R before relying on fresh outputs.
