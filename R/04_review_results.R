# ============================================================================
# SPANISH CPI PROJECT — REVIEW OF PRECOMPUTED RESULTS
# This script does not rerun the backtest or refit the models.
# It reads the main script CSV outputs, displays forecasts and metrics,
# and generates a chart focused on the latest 36 months.
# In RStudio, open this file and click Source; do not run isolated lines.
# ============================================================================

RESULTS_DIR <- file.path("results", "working")
FIGURES_DIR <- file.path("results", "figures")
dir.create(RESULTS_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(FIGURES_DIR, recursive = TRUE, showWarnings = FALSE)

# 1. Install/load required packages
paquetes <- c("readr", "dplyr", "lubridate", "ggplot2", "tibble")
faltan <- paquetes[!vapply(paquetes, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltan) > 0) {
  install.packages(faltan, repos = "https://cloud.r-project.org")
}

suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
  library(lubridate)
  library(ggplot2)
  library(tibble)
})

cat("\n============================================================\n")
cat("SPAIN CPI RESULTS REVIEW\n")
cat("Working directory: ", getwd(), "\n", sep = "")
cat("============================================================\n")

# 2. Check that the main script output files exist
archivos <- c(
  serie = file.path(RESULTS_DIR, "ipc_serie_historica.csv"),
  pred = file.path(RESULTS_DIR, "ipc_predicciones_actuales.csv"),
  metricas = file.path(RESULTS_DIR, "ipc_metricas_modelos.csv"),
  metricas_h = file.path(RESULTS_DIR, "ipc_metricas_por_horizonte.csv")
)
no_encontrados <- archivos[!file.exists(archivos)]
if (length(no_encontrados) > 0) {
  cat("\nThe following files are missing from the working directory:\n")
  cat(paste0(" - ", no_encontrados, collapse = "\n"), "\n")
  stop(
    "Open the project used for the main run and check getwd() and the CSV paths. This file error does not require rerunning the backtest."
  )
}

# 3. Read CSV files and create the series, forecast, and metric objects
cat("\nReading CSV files...\n")
serie <- read_csv(archivos[["serie"]], show_col_types = FALSE)
pred <- read_csv(archivos[["pred"]], show_col_types = FALSE)
metricas <- read_csv(archivos[["metricas"]], show_col_types = FALSE)
metricas_h <- read_csv(archivos[["metricas_h"]], show_col_types = FALSE)

# 4. Validate the required columns before proceeding
columnas_serie <- c("fecha", "ipc_interanual")
columnas_pred <- c("fecha_objetivo", "modelo_seleccionado", "prediccion_bruta",
                   "correccion_sesgo", "prediccion_ajustada")
columnas_metricas <- c("modelo", "MAE", "RMSE")
columnas_h <- c("modelo", "horizonte", "MAE", "RMSE")

if (!all(columnas_serie %in% names(serie))) {
  cat("Columns found in ipc_serie_historica.csv:\n")
  print(names(serie))
  stop("The historical CSV is missing the expected columns: fecha and ipc_interanual.")
}
if (!all(columnas_pred %in% names(pred))) {
  cat("Columns found in ipc_predicciones_actuales.csv:\n")
  print(names(pred))
  stop("The forecast CSV is missing one or more expected columns. Review the column names printed above.")
}
if (!all(columnas_metricas %in% names(metricas))) {
  cat("Columns found in ipc_metricas_modelos.csv:\n")
  print(names(metricas))
  stop("The overall metrics CSV is missing the required model, MAE, and RMSE columns.")
}
if (!all(columnas_h %in% names(metricas_h))) {
  cat("Columns found in ipc_metricas_por_horizonte.csv:\n")
  print(names(metricas_h))
  stop("The horizon-specific metrics CSV is missing one or more expected columns.")
}

# Convert dates to Date objects in case they were read as text
serie <- serie %>% mutate(fecha = as.Date(as.character(fecha)))
pred <- pred %>% mutate(fecha_objetivo = as.Date(as.character(fecha_objetivo)))

# Ensure numeric fields are actually numeric
serie <- serie %>% mutate(ipc_interanual = suppressWarnings(as.numeric(ipc_interanual)))
pred <- pred %>% mutate(
  prediccion_bruta = suppressWarnings(as.numeric(prediccion_bruta)),
  correccion_sesgo = suppressWarnings(as.numeric(correccion_sesgo)),
  prediccion_ajustada = suppressWarnings(as.numeric(prediccion_ajustada))
)
metricas <- metricas %>% mutate(across(any_of(c("MAE", "RMSE")), ~ suppressWarnings(as.numeric(.x))))
metricas_h <- metricas_h %>% mutate(
  horizonte = suppressWarnings(as.integer(horizonte)),
  across(any_of(c("MAE", "RMSE")), ~ suppressWarnings(as.numeric(.x)))
)

serie <- serie %>% filter(!is.na(fecha), is.finite(ipc_interanual)) %>% arrange(fecha)
pred <- pred %>% filter(!is.na(fecha_objetivo), is.finite(prediccion_ajustada)) %>% arrange(fecha_objetivo)

if (nrow(serie) == 0) stop("The historical file contains no valid observations.")
if (nrow(pred) == 0) stop("The forecast CSV contains no valid forecasts. Check the end date in the main script.")

# 5. Display the latest historical observation
ultima_fecha <- max(serie$fecha)
ultimo_registro <- serie %>% filter(fecha == ultima_fecha) %>% slice_tail(n = 1)
cat("\n================ LATEST HISTORICAL OBSERVATION ================\n")
print(ultimo_registro)
cat("Latest observation date: ", format(ultima_fecha, "%Y-%m"), "\n", sep = "")

# 6. Display the current forecasts
cat("\n================ CURRENT FORECASTS ================\n")
pred_mostrar <- pred %>%
  mutate(target_month = format(fecha_objetivo, "%Y-%m")) %>%
  select(target_month, any_of("horizonte_meses"), modelo_seleccionado,
         prediccion_bruta, correccion_sesgo, prediccion_ajustada) %>%
  mutate(across(where(is.numeric), ~ round(.x, 3)))
print(pred_mostrar, n = Inf)

# 7. Display overall and horizon-specific metrics
cat("\n================ OVERALL METRICS (lower MAE is better) ================\n")
print(metricas %>% arrange(MAE) %>% mutate(across(any_of(c("MAE", "RMSE")), ~ round(.x, 3))), n = Inf)

cat("\n================ METRICS BY HORIZON (lower MAE is better) ================\n")
print(metricas_h %>% arrange(horizonte, MAE) %>%
        mutate(across(any_of(c("MAE", "RMSE")), ~ round(.x, 3))), n = Inf)

modelo <- unique(na.omit(as.character(pred$modelo_seleccionado)))
if (length(modelo) == 0) modelo <- "Selected model"
modelo <- paste(modelo, collapse = ", ")

# 8. Create a readable chart of the latest 36 months and forecasts
meses_grafico <- 36L
desde <- ultima_fecha %m-% months(meses_grafico - 1L)
serie_reciente <- serie %>% filter(fecha >= desde) %>% arrange(fecha)

ultimo_valor <- ultimo_registro$ipc_interanual[1]
linea_prevision <- bind_rows(
  tibble(fecha = ultima_fecha, valor = ultimo_valor),
  pred %>% transmute(fecha = fecha_objetivo, valor = prediccion_ajustada)
) %>% filter(!is.na(fecha), is.finite(valor)) %>% arrange(fecha)

# If forecasts begin after the observed series, connect them
# to the final observed value to make the transition clear.
grafico_reciente <- ggplot() +
  geom_line(data = serie_reciente,
            aes(x = fecha, y = ipc_interanual, color = "Observed CPI inflation"),
            linewidth = 1.05, na.rm = TRUE) +
  geom_point(data = serie_reciente %>% slice_tail(n = 6),
             aes(x = fecha, y = ipc_interanual, color = "Observed CPI inflation"),
             size = 1.8, na.rm = TRUE) +
  geom_line(data = linea_prevision,
            aes(x = fecha, y = valor, color = "Bias-adjusted forecast"),
            linewidth = 1.1, linetype = "dashed", na.rm = TRUE) +
  geom_point(data = linea_prevision %>% filter(fecha > ultima_fecha),
             aes(x = fecha, y = valor, color = "Bias-adjusted forecast"),
             size = 2.8, na.rm = TRUE) +
  geom_vline(xintercept = as.numeric(ultima_fecha),
             linetype = "dotted", color = "grey40") +
  scale_x_date(date_breaks = "3 months", date_labels = "%b %Y",
               expand = expansion(mult = c(0.01, 0.04))) +
  labs(
    title = "Spain headline CPI: latest 36 months and forecast",
    subtitle = paste("Model selected by rolling-origin validation:", modelo),
    x = "Month", y = "Year-over-year CPI inflation (%)", color = "Series",
    caption = "Historical source: INE. Dashed line: bias-adjusted forecast."
  ) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom",
        axis.text.x = element_text(angle = 45, hjust = 1))

print(grafico_reciente)
ggsave(file.path(FIGURES_DIR, "cpi_forecast_latest_36_months.png"), plot = grafico_reciente,
       width = 12, height = 7, dpi = 180)

cat("\nChart saved as: results/figures/cpi_forecast_latest_36_months.png\n")
cat("\nFiles read from: ", getwd(), "\n", sep = "")
cat("Review complete. The backtest was not rerun and no model was refitted.\n")
