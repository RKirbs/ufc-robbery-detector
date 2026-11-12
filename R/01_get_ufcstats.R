# 01_get_ufcstats.R: fetch UFCStats data via the Greco1899/scrape_ufc_stats mirror.
#
# Why a mirror: UFCStats.com now serves a JavaScript proof-of-work bot challenge
# to automated clients, and we don't bypass bot protection. The Greco1899 repo
# (GPL-3.0) publishes UFCStats tables as CSVs. We pin a specific commit for
# reproducibility and download the files at build time instead of committing them.

GRECO_FILES <- c("ufc_event_details", "ufc_fight_details", "ufc_fight_results",
                 "ufc_fight_stats", "ufc_fighter_details", "ufc_fighter_tott")

# Download each CSV at the pinned commit into data/raw/ufcstats_greco/ (cached).
# Returns the local file paths so the targets pipeline can track them.
get_greco_files <- function(sha = GRECO_SHA, dir = "data/raw/ufcstats_greco") {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  vapply(GRECO_FILES, \(f) {
    dest <- file.path(dir, paste0(f, ".csv"))
    if (!file.exists(dest)) {
      url <- sprintf("https://raw.githubusercontent.com/Greco1899/scrape_ufc_stats/%s/%s.csv", sha, f)
      old <- options(timeout = 600); on.exit(options(old))
      utils::download.file(url, dest, quiet = TRUE, mode = "wb")
    }
    dest
  }, character(1))
}

# Read and lightly clean the Greco CSVs into a named list of tibbles: trim
# whitespace and attach parsed event dates to fights.
read_greco <- function(paths) {
  # Look files up by basename (targets drops vector names on file targets).
  path_of <- \(f) paths[basename(paths) == paste0(f, ".csv")]
  rd <- \(f) readr::read_csv(path_of(f), show_col_types = FALSE, guess_max = 1e5) |>
    dplyr::mutate(dplyr::across(dplyr::where(is.character), stringr::str_squish))
  list(
    events   = rd("ufc_event_details") |> dplyr::mutate(date = lubridate::mdy(DATE)),
    fights   = rd("ufc_fight_details"),
    results  = rd("ufc_fight_results"),
    stats    = rd("ufc_fight_stats"),
    fighters = rd("ufc_fighter_details"),
    tott     = rd("ufc_fighter_tott")
  )
}
