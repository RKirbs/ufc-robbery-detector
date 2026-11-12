# utils.R: shared helpers (polite HTTP fetching with a disk cache, name
# normalisation, stat parsing, and the project's ggplot2 theme).

suppressPackageStartupMessages({
  library(httr2)
  library(dplyr)
  library(stringr)
  library(ggplot2)
})

# ---- Project constants -------------------------------------------------------

# Freeze date: the last completed UFC event used by the project (see NOTES.md).
FREEZE_DATE <- as.Date("2026-11-07")
# Start date: the first full year after the UFC adopted the Unified Rules (UFC 28, Nov 2000).
START_DATE  <- as.Date("2001-01-01")
# Pinned commit of the Greco1899/scrape_ufc_stats mirror of UFCStats.
GRECO_SHA   <- "c742842f29466758fedc3906dbad28d6d320a8da"

# Honest user agent with no personal contact details.
SCRAPER_UA <- "ufc-robbery-detector/0.1 (academic research project; polite, cached, low-rate)"

# ---- Polite cached fetching --------------------------------------------------

# Fetch a URL once and cache the raw HTML on disk. Later calls read the cache,
# so no page is ever downloaded twice. The pause between live requests is random
# (1.5-3 s) to keep load on the source site low.
fetch_cached <- function(url, cache_file, min_wait = 1.5, max_wait = 3) {
  if (file.exists(cache_file) && file.size(cache_file) > 0) {
    return(readr::read_file(cache_file))
  }
  dir.create(dirname(cache_file), recursive = TRUE, showWarnings = FALSE)
  Sys.sleep(runif(1, min_wait, max_wait))
  resp <- request(url) |>
    req_user_agent(SCRAPER_UA) |>
    req_timeout(30) |>
    # Retry transient failures (timeouts, 429, 5xx) with exponential backoff.
    req_retry(max_tries = 4, backoff = ~ 5 * 2^(.x - 1), retry_on_failure = TRUE,
              is_transient = \(r) resp_status(r) %in% c(429, 500, 502, 503, 504)) |>
    req_error(is_error = \(r) FALSE) |>
    req_perform()
  if (resp_status(resp) != 200) {
    warning(sprintf("HTTP %s for %s", resp_status(resp), url))
    return(NA_character_)
  }
  html <- resp_body_string(resp)
  readr::write_file(html, cache_file)
  html
}

# ---- Text helpers ------------------------------------------------------------

# Normalise a person's name for record linkage: strip accents, punctuation and
# case, and collapse whitespace. "Eric Colón" -> "eric colon".
normalize_name <- function(x) {
  x |>
    stringi::stri_trans_general("Latin-ASCII") |>
    str_to_lower() |>
    str_replace_all("[^a-z ]", " ") |>
    str_squish()
}

# Parse UFCStats "X of Y" strings into landed (X) and attempted (Y).
parse_of <- function(x, part = c("landed", "attempted")) {
  part <- match.arg(part)
  m <- str_match(x, "(\\d+)\\s*of\\s*(\\d+)")
  as.numeric(if (part == "landed") m[, 2] else m[, 3])
}

# Parse "M:SS" control-time strings to seconds; "--" becomes NA.
parse_mmss <- function(x) {
  m <- str_match(x, "^(\\d+):(\\d{2})$")
  as.numeric(m[, 2]) * 60 + as.numeric(m[, 3])
}

# ---- Plot theme --------------------------------------------------------------

# Palette: red/blue corners plus neutral accents (used consistently on every chart).
pal <- c(red = "#C8102E", blue = "#1F4E9E", grey = "#8A8F98",
         ink = "#1B1F24", accent = "#E3A008")

SOURCE_CAPTION <- "Data: UFCStats, MMADecisions; analysis by Rob Kirby"

# Clean, minimal theme that stays readable at phone width.
theme_robbery <- function(base_size = 12) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title = element_text(face = "bold", size = rel(1.25), colour = pal[["ink"]]),
      plot.subtitle = element_text(size = rel(0.95), colour = "#3C4148",
                                   margin = margin(b = 8)),
      plot.caption = element_text(size = rel(0.7), colour = pal[["grey"]], hjust = 0),
      plot.title.position = "plot",
      plot.caption.position = "plot",
      panel.grid.minor = element_blank(),
      panel.grid.major = element_line(colour = "#E6E8EB", linewidth = 0.3),
      axis.title = element_text(size = rel(0.85), colour = "#3C4148"),
      legend.position = "top",
      legend.justification = "left",
      strip.text = element_text(face = "bold", hjust = 0)
    )
}

# Save a figure to figures/ at a consistent size and resolution.
save_fig <- function(plot, name, width = 8, height = 5, dpi = 200) {
  dir.create("figures", showWarnings = FALSE)
  path <- file.path("figures", paste0(name, ".png"))
  ggsave(path, plot, width = width, height = height, dpi = dpi, bg = "white")
  path
}
