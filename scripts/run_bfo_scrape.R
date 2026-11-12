# run_bfo_scrape.R: fetch the BestFightOdds fighter pages that cover every UFC
# decision since 2007 (about 1,000 pages, ~40 min at 1.5-3 s per request).
# Cached: re-running never re-downloads a page.
suppressPackageStartupMessages({ library(targets); library(dplyr) })
source("R/utils.R"); source("R/03_bestfightodds.R")
tar_load(fight_table)
idx <- bfo_fighter_index()
targets_urls <- bfo_targets(fight_table, idx)
readr::write_csv(tibble::tibble(url = targets_urls), file.path(BFO_RAW, "fighter_targets.csv"))
log <- file.path(BFO_RAW, "scrape_log.txt")
cat(format(Sys.time()), "starting", length(targets_urls), "pages\n", file = log, append = TRUE)
for (k in seq_along(targets_urls)) {
  u <- targets_urls[k]
  res <- tryCatch(fetch_cached(u, bfo_cache_path(u)), error = \(e) { cat("ERROR", u, conditionMessage(e), "\n", file = log, append = TRUE); NA })
  if (k %% 50 == 0) cat(format(Sys.time()), k, "of", length(targets_urls), "\n", file = log, append = TRUE)
}
cat(format(Sys.time()), "done\n", file = log, append = TRUE)
