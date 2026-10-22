# ============================================================================
# SPANISH CPI FORECASTING PROJECT | 2026-2027
# Forecasting headline CPI inflation in Spain (year-over-year, %)
# Random Forest, benchmark models, rolling-origin validation, and forecast tracking
# Primary data source: official Spanish National Statistics Institute (INE) Tempus3 API
# ============================================================================
# INSTRUCTIONS:
# 1) Open this file in RStudio.
# 2) Run the full script using Source.
# 3) CSV files and charts are saved to the project results directories.
# 4) To automate it, schedule this script with Windows Task Scheduler.
#    CPI is published monthly, so daily runs add no new data unless INE releases
#    a new observation.
# ============================================================================

# All generated files are written beneath results/working.
RESULTS_DIR <- file.path("results", "working")
dir.create(RESULTS_DIR, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path("results", "figures"), recursive = TRUE, showWarnings = FALSE)
output_path <- function(filename) file.path(RESULTS_DIR, filename)

# ------------------------------- 0. SETTINGS -------------------------------

FECHA_FINAL_CONCURSO <- as.Date("2026-12-01")
N_ARBOLES <- 600L
VENTANA_BACKTEST <- 60L      #  last 60 monthly origins (approximately 5 years)
VENTANA_SESGO <- 24L         #  recent errors per horizon for bias correction
SEMILLA <- 2026L

# INE series identifiers:
# IPC251856: national headline index, year-over-year change, 2021 base (historical)
# IPC290750: national headline index, year-over-year change, 2025 base (current series)
URL_API_INE <- "https://servicios.ine.es/wstempus/js/ES/DATOS_SERIE/"
CODIGO_HISTORICO <- "IPC251856"
CODIGO_ACTUAL <- "IPC290750"

# ------------------------------ 1. PACKAGES -------------------------------

paquetes <- c("httr", "jsonlite", "dplyr", "purrr", "tibble", "readr",
              "lubridate", "ranger", "forecast", "ggplot2")

faltan <- paquetes[!vapply(paquetes, requireNamespace, logical(1), quietly = TRUE)]
if (length(faltan) > 0) {
  install.packages(faltan, repos = "https://cloud.r-project.org")
}

suppressPackageStartupMessages({
  library(dplyr)
  library(purrr)
  library(tibble)
  library(readr)
  library(lubridate)
  library(ggplot2)
})

# --------------------- 2. DOWNLOAD AND PARSE INE DATA ---------------------

# Convert an INE API date to the first day of its month.
parse_mes_ine <- function(registro) {
  f <- registro$Fecha
  if (is.null(f)) f <- registro$fecha
  if (is.null(f)) f <- registro$FechaInicio
  if (is.null(f)) f <- registro$Periodo
  if (is.null(f)) return(as.Date(NA))

  # Some Tempus3 responses encode dates as Unix milliseconds.
  f_num <- suppressWarnings(as.numeric(as.character(f)))
  if (length(f_num) == 1 && is.finite(f_num) && f_num > 1e11) {
    d <- as.Date(as.POSIXct(f_num / 1000, origin = "1970-01-01", tz = "UTC"))
    return(as.Date(format(d, "%Y-%m-01")))
  }

  s <- as.character(f)[1]
  # Supported examples: 2026M09, 2026-09-01, 01/09/2026.
  if (grepl("^[0-9]{4}M[0-9]{2}$", s)) {
    return(as.Date(paste0(substr(s, 1, 4), "-", substr(s, 6, 7), "-01")))
  }
  if (grepl("^[0-9]{4}-[0-9]{2}", s)) {
    return(as.Date(paste0(substr(s, 1, 7), "-01")))
  }
  if (grepl("^[0-9]{2}/[0-9]{2}/[0-9]{4}$", s)) {
    d <- as.Date(s, format = "%d/%m/%Y")
    if (!is.na(d)) return(as.Date(format(d, "%Y-%m-01")))
  }

  # Fallback for APIs that return the year and month as numeric text.
  if (grepl("^[0-9]{8}$", s)) {
    d <- as.Date(s, format = "%Y%m%d")
    if (!is.na(d)) return(as.Date(format(d, "%Y-%m-01")))
  }
  if (grepl("^[0-9]{6}$", s)) {
    return(as.Date(paste0(substr(s, 1, 4), "-", substr(s, 5, 6), "-01")))
  }
  as.Date(NA)
}

parse_valor_ine <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_real_)
  if (is.numeric(x)) return(as.numeric(x[1]))
  s <- trimws(as.character(x)[1])
  if (is.na(s) || s == "" || s %in% c("..", "...")) return(NA_real_)
  # Support values formatted as 4,9 or 1.234,5.
  if (grepl(",", s, fixed = TRUE) && grepl(".", s, fixed = TRUE)) {
    s <- gsub(".", "", s, fixed = TRUE)
    s <- sub(",", ".", s, fixed = TRUE)
  } else {
    s <- sub(",", ".", s, fixed = TRUE)
  }
  suppressWarnings(as.numeric(s))
}

leer_serie_ine <- function(codigo) {
  url <- paste0(URL_API_INE, codigo)
  respuesta <- httr::GET(
    url,
    query = list(nult = 1000, tip = "AM"),
    httr::user_agent("RStudio MMIF time-series forecasting exercise"),
    httr::timeout(45)
  )
  httr::stop_for_status(respuesta)
  cuerpo <- httr::content(respuesta, as = "text", encoding = "UTF-8")
  objeto <- jsonlite::fromJSON(cuerpo, simplifyVector = FALSE)

  # The API may return observations under a nested Data field or directly.
  # Both response structures are supported.
  if (is.list(objeto) && !is.null(objeto$Data)) {
    observaciones <- objeto$Data
  } else if (is.list(objeto) && !is.null(objeto$Valor)) {
    observaciones <- list(objeto)
  } else if (is.list(objeto) && length(objeto) >= 1 &&
             is.list(objeto[[1]]) && !is.null(objeto[[1]]$Data)) {
    observaciones <- objeto[[1]]$Data
  } else {
    observaciones <- objeto
  }

  observaciones <- purrr::keep(observaciones, function(z) {
    is.list(z) && !is.null(z$Valor)
  })
  if (length(observaciones) == 0) {
    stop("The INE API returned no observations for series ", codigo,
         ". Check connectivity and the series identifier.")
  }

  salida <- purrr::map_dfr(observaciones, function(z) {
    tibble(
      fecha = parse_mes_ine(z),
      ipc_interanual = parse_valor_ine(z$Valor),
      codigo_serie = codigo
    )
  }) %>%
    filter(!is.na(fecha), !is.na(ipc_interanual)) %>%
    arrange(fecha) %>%
    distinct(fecha, .keep_all = TRUE)

  if (nrow(salida) == 0) {
    stop("Received series ", codigo,
         ", but its dates and values could not be parsed.")
  }
  salida
}

message("Downloading historical and current INE series...")
serie_historica <- leer_serie_ine(CODIGO_HISTORICO) %>%
  filter(fecha <= as.Date("2025-12-01")) %>%
  mutate(prioridad = 1L)
serie_actual <- leer_serie_ine(CODIGO_ACTUAL) %>%
  mutate(prioridad = 2L)

# If both series contain a date, prefer the newer 2025-base series.
datos <- bind_rows(serie_actual, serie_historica) %>%
  arrange(fecha, desc(prioridad)) %>%
  distinct(fecha, .keep_all = TRUE) %>%
  arrange(fecha) %>%
  select(fecha, ipc_interanual, codigo_serie)

if (nrow(datos) < 60) {
  stop("Only ", nrow(datos),
       " observations were retrieved. At least 60 months are required.")
}

# Check monthly continuity; missing observations are never filled artificially.
fechas_esperadas <- seq.Date(min(datos$fecha), max(datos$fecha), by = "month")
if (!identical(as.character(fechas_esperadas), as.character(datos$fecha))) {
  faltantes <- setdiff(as.character(fechas_esperadas), as.character(datos$fecha))
  stop("The series has missing months. First missing months: ",
       paste(head(faltantes, 6), collapse = ", "),
       ". Values will not be imputed automatically, to avoid introducing fabricated data.")
}

fechas <- datos$fecha
y <- as.numeric(datos$ipc_interanual)
ultima_fecha <- max(fechas)
ultimo_valor <- y[length(y)]

cat("\nLatest official observation downloaded:", format(ultima_fecha, "%Y-%m"),
    "| year-over-year CPI inflation =", format(round(ultimo_valor, 2), nsmall = 2), "%\n")
if (ultima_fecha < as.Date("2026-09-01")) {
  warning("The downloaded series does not reach September 2026. Check the INE API before presenting the results.")
}

# -------------------------- 3. RANDOM FOREST -------------------------------

# The target is year-over-year CPI inflation (%). Predictors are built only
# from values available through the previous month to avoid data leakage.

crear_entrenamiento_rf <- function(y, fechas) {
  n <- length(y)
  if (n < 40) stop("Insufficient history to train the Random Forest model.")
  indices <- seq.int(13, n)
  mes <- lubridate::month(fechas[indices])

  tibble(
    objetivo = y[indices],
    lag1 = y[indices - 1L],
    lag2 = y[indices - 2L],
    lag3 = y[indices - 3L],
    lag6 = y[indices - 6L],
    lag12 = y[indices - 12L],
    media3 = vapply(indices, function(i) mean(y[(i - 3L):(i - 1L)]), numeric(1)),
    media6 = vapply(indices, function(i) mean(y[(i - 6L):(i - 1L)]), numeric(1)),
    sd6 = vapply(indices, function(i) stats::sd(y[(i - 6L):(i - 1L)]), numeric(1)),
    sin_mes = sin(2 * pi * mes / 12),
    cos_mes = cos(2 * pi * mes / 12)
  )
}

crear_fila_rf <- function(y_hist, fecha_objetivo) {
  n <- length(y_hist)
  mes <- lubridate::month(fecha_objetivo)
  tibble(
    lag1 = y_hist[n],
    lag2 = y_hist[n - 1L],
    lag3 = y_hist[n - 2L],
    lag6 = y_hist[n - 5L],
    lag12 = y_hist[n - 11L],
    media3 = mean(y_hist[(n - 2L):n]),
    media6 = mean(y_hist[(n - 5L):n]),
    sd6 = stats::sd(y_hist[(n - 5L):n]),
    sin_mes = sin(2 * pi * mes / 12),
    cos_mes = cos(2 * pi * mes / 12)
  )
}

pronosticar_rf <- function(y, fechas, fechas_futuras) {
  if (length(fechas_futuras) == 0) return(numeric(0))
  entrenamiento <- crear_entrenamiento_rf(y, fechas)
  ajuste <- ranger::ranger(
    objetivo ~ ., data = as.data.frame(entrenamiento),
    num.trees = N_ARBOLES, min.node.size = 5,
    seed = SEMILLA, importance = "permutation"
  )
  historia_extendida <- y
  predicciones <- numeric(length(fechas_futuras))

  for (j in seq_along(fechas_futuras)) {
    fila <- crear_fila_rf(historia_extendida, fechas_futuras[j])
    pred <- as.numeric(predict(ajuste, data = as.data.frame(fila))$predictions[1])
    predicciones[j] <- pred
    # See docs/METHODOLOGY.md for the rationale behind this step.
    historia_extendida <- c(historia_extendida, pred)
  }
  predicciones
}

# ----------------------- 4. BENCHMARK MODELS ------------------------------

pronosticar_arima <- function(y, h) {
  # Annual seasonality (frequency 12) is enabled for this monthly series.
  modelo <- forecast::auto.arima(
    stats::ts(y, frequency = 12), seasonal = TRUE,
    stepwise = TRUE, approximation = FALSE
  )
  as.numeric(forecast::forecast(modelo, h = h)$mean)
}

pronosticar_naive <- function(y, h) rep(tail(y, 1), h)

pronosticar_naive_estacional <- function(y, h) {
  historia <- y
  salida <- numeric(h)
  for (j in seq_len(h)) {
    indice <- length(historia) - 11L
    salida[j] <- if (indice >= 1) historia[indice] else tail(historia, 1)
    historia <- c(historia, salida[j])
  }
  salida
}

pronosticar_metodo <- function(modelo, y, fechas, fechas_futuras) {
  h <- length(fechas_futuras)
  if (h == 0) return(numeric(0))
  resultado <- switch(
    modelo,
    "Random Forest" = pronosticar_rf(y, fechas, fechas_futuras),
    "ARIMA" = pronosticar_arima(y, h),
    "Naive" = pronosticar_naive(y, h),
    "Seasonal Naive (12)" = pronosticar_naive_estacional(y, h),
    stop("Unknown method: ", modelo)
  )
  as.numeric(resultado)
}

pronosticar_todos <- function(y, fechas, fechas_futuras) {
  h <- length(fechas_futuras)
  salida <- list(
    "Random Forest" = tryCatch(pronosticar_rf(y, fechas, fechas_futuras),
                               error = function(e) rep(NA_real_, h)),
    "ARIMA" = tryCatch(pronosticar_arima(y, h),
                       error = function(e) rep(NA_real_, h)),
    "Naive" = pronosticar_naive(y, h),
    "Seasonal Naive (12)" = pronosticar_naive_estacional(y, h)
  )
  salida
}

# -------------------------- 5. TEMPORAL BACKTEST ---------------------------

# Expanding-window rolling-origin validation: each origin uses past data only.
# The original settings are retained (600 trees and 60 forecast origins).
# Progress reporting is added without reducing the number of evaluation runs.
progress_msg <- function(...) {
  cat(..., "\n", sep = "")
  flush.console()
}

progress_msg("Evaluating models with rolling-origin temporal validation...")
progress_msg("Configuration: ", N_ARBOLES, " Random Forest trees; up to ",
             VENTANA_BACKTEST, " origins; forecast horizons of 1–3 months.")
n <- length(y)
h_backtest <- min(3L, n - 60L)
if (h_backtest < 1L) stop("There are not enough observations for the backtest.")
primer_origen <- max(60L, n - VENTANA_BACKTEST - h_backtest + 1L)
ult_origen <- n - h_backtest
origenes <- seq.int(primer_origen, ult_origen)
lista_bt <- list()
contador <- 1L
tiempo_inicio_backtest <- proc.time()[["elapsed"]]

for (i_origen in seq_along(origenes)) {
  origen <- origenes[i_origen]
  tiempo_inicio_origen <- proc.time()[["elapsed"]]
  y_train <- y[seq_len(origen)]
  fechas_train <- fechas[seq_len(origen)]
  fechas_obj <- fechas[origen + seq_len(h_backtest)]

  progress_msg("\n[BACKTEST ", i_origen, "/", length(origenes), " | ",
               sprintf("%.1f", 100 * i_origen / length(origenes)),
               "%] Data available through ", format(fechas[origen], "%Y-%m"))

  # Keep the original model order and configuration.
  # Print status messages before fitting each model to make progress visible.
  tiempo_modelo <- proc.time()[["elapsed"]]
  progress_msg("  -> Random Forest: fitting ", N_ARBOLES, " trees...")
  pred_rf <- tryCatch(
    pronosticar_rf(y_train, fechas_train, fechas_obj),
    error = function(e) {
      progress_msg("  !! Random Forest unavailable at this origin: ", conditionMessage(e))
      rep(NA_real_, h_backtest)
    }
  )
  progress_msg("  <- Random Forest completed in ",
               sprintf("%.1f", proc.time()[["elapsed"]] - tiempo_modelo), " s.")

  tiempo_modelo <- proc.time()[["elapsed"]]
  progress_msg("  -> Seasonal ARIMA: searching and fitting the model...")
  pred_arima <- tryCatch(
    pronosticar_arima(y_train, h_backtest),
    error = function(e) {
      progress_msg("  !! ARIMA unavailable at this origin: ", conditionMessage(e))
      rep(NA_real_, h_backtest)
    }
  )
  progress_msg("  <- ARIMA completed in ",
               sprintf("%.1f", proc.time()[["elapsed"]] - tiempo_modelo), " s.")

  progress_msg("  -> Calculating benchmark models (Naive and Seasonal Naive)...")
  pred_naive <- pronosticar_naive(y_train, h_backtest)
  pred_naive_estacional <- pronosticar_naive_estacional(y_train, h_backtest)

  pronosticos <- list(
    "Random Forest" = pred_rf,
    "ARIMA" = pred_arima,
    "Naive" = pred_naive,
    "Seasonal Naive (12)" = pred_naive_estacional
  )

  for (nombre_modelo in names(pronosticos)) {
    valores <- pronosticos[[nombre_modelo]]
    if (length(valores) != h_backtest) next
    for (hh in seq_len(h_backtest)) {
      if (is.finite(valores[hh])) {
        lista_bt[[contador]] <- tibble(
          fecha_origen = fechas[origen],
          fecha_objetivo = fechas_obj[hh],
          horizonte = hh,
          modelo = nombre_modelo,
          prediccion = as.numeric(valores[hh]),
          real = y[origen + hh],
          error = y[origen + hh] - as.numeric(valores[hh])
        )
        contador <- contador + 1L
      }
    }
  }

  tiempo_origen <- proc.time()[["elapsed"]] - tiempo_inicio_origen
  tiempo_total <- proc.time()[["elapsed"]] - tiempo_inicio_backtest
  progress_msg("[COMPLETED ", i_origen, "/", length(origenes), "] Origin completed in ",
               sprintf("%.1f", tiempo_origen), " s; cumulative time: ",
               sprintf("%.1f", tiempo_total / 60), " min.")
}

progress_msg("Backtest completed: ", length(origenes), " forecast origins evaluated in ",
             sprintf("%.1f", (proc.time()[["elapsed"]] - tiempo_inicio_backtest) / 60), " min.")

backtest <- bind_rows(lista_bt)
if (nrow(backtest) == 0) stop("The backtest did not produce valid results.")

metricas <- backtest %>%
  group_by(modelo) %>%
  summarise(
    MAE = mean(abs(error), na.rm = TRUE),
    RMSE = sqrt(mean(error^2, na.rm = TRUE)),
    observaciones = sum(is.finite(error)),
    .groups = "drop"
  ) %>%
  filter(is.finite(MAE), observaciones >= 20) %>%
  arrange(MAE)

if (nrow(metricas) == 0) stop("There are not enough valid forecasts to compare models.")
best_model <- metricas$modelo[1]
metricas_por_horizonte <- backtest %>%
  group_by(modelo, horizonte) %>%
  summarise(
    MAE = mean(abs(error), na.rm = TRUE),
    RMSE = sqrt(mean(error^2, na.rm = TRUE)),
    observaciones = sum(is.finite(error)),
    .groups = "drop"
  ) %>% arrange(horizonte, MAE)

write_csv(metricas, output_path("ipc_metricas_modelos.csv"))
write_csv(metricas_por_horizonte, output_path("ipc_metricas_por_horizonte.csv"))
write_csv(backtest, output_path("ipc_backtest_detalle.csv"))
write_csv(datos, output_path("ipc_serie_historica.csv"))

cat("\nModel comparison (lower MAE is better):\n")
print(metricas %>% mutate(across(c(MAE, RMSE), ~ round(.x, 3))))
cat("\nModel selected by rolling-origin MAE:", best_model, "\n")

# -------------------------- 6. OCT-DEC FORECAST ----------------------------

fecha_inicio <- ultima_fecha %m+% months(1)
fechas_futuras <- if (fecha_inicio <= FECHA_FINAL_CONCURSO) {
  seq.Date(from = fecha_inicio, to = FECHA_FINAL_CONCURSO, by = "month")
} else {
  as.Date(character())
}

predicciones_actuales <- tibble(
  fecha_objetivo = as.Date(character()),
  horizonte_meses = integer(),
  modelo_seleccionado = character(),
  prediccion_bruta = double(),
  correccion_sesgo = double(),
  prediccion_ajustada = double()
)
if (length(fechas_futuras) > 0) {
  pronostico_bruto <- pronosticar_metodo(best_model, y, fechas, fechas_futuras)

  # See docs/METHODOLOGY.md for the rationale behind this step.
  # calculated separately for each horizon for the selected model.
  sesgo_por_h <- vapply(seq_along(fechas_futuras), function(hh) {
    tmp <- backtest %>%
      filter(modelo == best_model, horizonte == hh) %>%
      arrange(fecha_origen) %>%
      slice_tail(n = VENTANA_SESGO)
    if (nrow(tmp) == 0) 0 else mean(tmp$error, na.rm = TRUE)
  }, numeric(1))

  predicciones_actuales <- tibble(
    fecha_objetivo = fechas_futuras,
    horizonte_meses = seq_along(fechas_futuras),
    modelo_seleccionado = best_model,
    prediccion_bruta = as.numeric(pronostico_bruto),
    correccion_sesgo = as.numeric(sesgo_por_h),
    prediccion_ajustada = as.numeric(pronostico_bruto + sesgo_por_h)
  )

  write_csv(predicciones_actuales, output_path("ipc_predicciones_actuales.csv"))
  cat("\nHEADLINE CPI FORECASTS (year-over-year, %):\n")
  print(predicciones_actuales %>%
          mutate(fecha_objetivo = format(fecha_objetivo, "%Y-%m"),
                 across(c(prediccion_bruta, correccion_sesgo, prediccion_ajustada),
                        ~ round(.x, 2))))
} else {
  message("There are no future months left to forecast through December 2026.")
  write_csv(predicciones_actuales, output_path("ipc_predicciones_actuales.csv"))
}

# --------------------- 7. FORECAST HISTORY AND ERRORS ----------------------

# Append a forecast version only when it is new or has changed.
# Repeated runs without new data therefore do not fill the history with
# identical copies or overweight those months in historical error calculations.
ruta_historial <- output_path("ipc_historico_predicciones.csv")
columnas_historial <- c(
  "fecha_ejecucion", "fecha_objetivo", "modelo_seleccionado",
  "prediccion_bruta", "correccion_sesgo", "prediccion_ajustada"
)

if (file.exists(ruta_historial)) {
  historial_antiguo <- readr::read_csv(
    ruta_historial,
    col_types = cols(
      fecha_ejecucion = col_date(),
      fecha_objetivo = col_date(),
      .default = col_guess()
    ),
    show_col_types = FALSE
  ) %>% select(any_of(columnas_historial))
} else {
  historial_antiguo <- tibble(
    fecha_ejecucion = as.Date(character()),
    fecha_objetivo = as.Date(character()),
    modelo_seleccionado = character(),
    prediccion_bruta = double(),
    correccion_sesgo = double(),
    prediccion_ajustada = double()
  )
}

nuevo_historial_completo <- predicciones_actuales %>%
  transmute(
    fecha_ejecucion = as.Date(Sys.Date()),
    fecha_objetivo,
    modelo_seleccionado,
    prediccion_bruta,
    correccion_sesgo,
    prediccion_ajustada
  )

if (nrow(nuevo_historial_completo) > 0 && nrow(historial_antiguo) > 0) {
  ultima_version_por_objetivo <- historial_antiguo %>%
    arrange(fecha_ejecucion) %>%
    group_by(fecha_objetivo) %>%
    slice_tail(n = 1) %>%
    ungroup() %>%
    transmute(
      fecha_objetivo,
      modelo_anterior = modelo_seleccionado,
      prediccion_anterior = prediccion_ajustada
    )

  nuevo_historial <- nuevo_historial_completo %>%
    left_join(ultima_version_por_objetivo, by = "fecha_objetivo") %>%
    filter(
      is.na(modelo_anterior) |
        modelo_seleccionado != modelo_anterior |
        abs(prediccion_ajustada - prediccion_anterior) > 1e-8
    ) %>%
    select(all_of(columnas_historial))
} else {
  nuevo_historial <- nuevo_historial_completo
}

historial <- bind_rows(historial_antiguo, nuevo_historial) %>%
  arrange(fecha_ejecucion) %>%
  group_by(fecha_ejecucion, fecha_objetivo) %>%
  slice_tail(n = 1) %>%
  ungroup()

reales <- datos %>% transmute(fecha_objetivo = fecha, IPC_real = ipc_interanual)
historial <- historial %>%
  left_join(reales, by = "fecha_objetivo") %>%
  mutate(
    error = if_else(!is.na(IPC_real), IPC_real - prediccion_ajustada, NA_real_),
    error_absoluto = abs(error)
  ) %>%
  arrange(fecha_ejecucion, fecha_objetivo)

write_csv(historial, ruta_historial)

resultados_evaluados <- historial %>% filter(!is.na(IPC_real))
if (nrow(resultados_evaluados) > 0) {
  precision_historica <- resultados_evaluados %>%
    group_by(modelo_seleccionado) %>%
    summarise(
      predicciones_evaluadas = n(),
      MAE = mean(error_absoluto, na.rm = TRUE),
      RMSE = sqrt(mean(error^2, na.rm = TRUE)),
      .groups = "drop"
    ) %>% arrange(MAE)
  write_csv(precision_historica, output_path("ipc_precision_predicciones_publicadas.csv"))
  cat("\nErrors for previous forecasts whose actual values have been published:\n")
  print(precision_historica %>% mutate(across(c(MAE, RMSE), ~ round(.x, 3))))
} else {
  message("No recorded forecast targets with published actual values are available yet.")
}

# ------------------------------- 8. CHART ---------------------------------

if (length(fechas_futuras) > 0) {
  grafico_hist <- tibble(fecha = fechas, serie = "IPC real", valor = y)
  grafico_pred <- bind_rows(
    tibble(fecha = ultima_fecha, serie = "Selected forecast", valor = ultimo_valor),
    tibble(fecha = fechas_futuras, serie = "Selected forecast",
           valor = predicciones_actuales$prediccion_ajustada)
  )
  grafico <- ggplot() +
    geom_line(data = grafico_hist, aes(x = fecha, y = valor, color = serie), linewidth = 0.8) +
    geom_point(data = grafico_hist %>% slice_tail(n = 12),
               aes(x = fecha, y = valor, color = serie), size = 1.4) +
    geom_line(data = grafico_pred, aes(x = fecha, y = valor, color = serie),
              linewidth = 1.1, linetype = "dashed") +
    geom_point(data = grafico_pred %>% filter(fecha > ultima_fecha),
               aes(x = fecha, y = valor, color = serie), size = 2.2) +
    geom_vline(xintercept = as.numeric(ultima_fecha), linetype = "dotted", color = "grey40") +
    labs(
      title = "Spain headline CPI: observed data and forecast",
      subtitle = paste("Model selected by rolling-origin validation:", best_model),
      x = "Month", y = "Year-over-year inflation (%)", color = "Series",
      caption = "Source: INE. Future forecasts use recent backtest bias adjustment."
    ) +
    theme_minimal() +
    theme(legend.position = "bottom")
  ggsave(file.path("results", "figures", "cpi_forecast_full_series.png"), plot = grafico, width = 10, height = 6, dpi = 150)
  print(grafico)
}

cat("\nWorking files saved under:", getwd(), "\n")
cat(" - ipc_predicciones_actuales.csv\n")
cat(" - ipc_metricas_modelos.csv\n")
cat(" - ipc_metricas_por_horizonte.csv\n")
cat(" - ipc_backtest_detalle.csv\n")
cat(" - ipc_serie_historica.csv\n")
cat(" - ipc_historico_predicciones.csv\n")
cat(" - ipc_precision_predicciones_publicadas.csv (when comparable actuals are available)\n")
cat(" - results/figures/cpi_forecast_full_series.png (if forecast months remain)\n")
