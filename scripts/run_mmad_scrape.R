# run_mmad_scrape.R: one-off driver that downloads (and caches) every
# MMADecisions page the project needs. It's run outside the targets pipeline
# because it's slow (hours) and network-bound. The pipeline then parses only the
# cached HTML, so rebuilding never re-hits the site.
#
# Usage (from the project root):  Rscript scripts/run_mmad_scrape.R
# Safe to stop and restart: cached pages are skipped.

source("R/utils.R")
source("R/01_get_ufcstats.R")
source("R/02_scrape_mmadecisions.R")
suppressPackageStartupMessages({ library(dplyr); library(purrr) })

log_msg <- function(...) {
  msg <- sprintf("[%s] %s", format(Sys.time(), "%H:%M:%S"), sprintf(...))
  message(msg)
  cat(msg, "\n", file = file.path(MMAD_RAW, "scrape_log.txt"), append = TRUE)
}
dir.create(MMAD_RAW, recursive = TRUE, showWarnings = FALSE)

# 1. UFC event dates from UFCStats (used to skip non-UFC promotions).
greco <- read_greco(get_greco_files())
ufc_dates <- greco$events$date
ufc_dates <- ufc_dates[ufc_dates >= START_DATE & ufc_dates <= FREEZE_DATE]

# 2. Year index pages.
years <- seq(as.integer(format(START_DATE, "%Y")), as.integer(format(FREEZE_DATE, "%Y")))
events <- map_dfr(years, mmad_year_events)
log_msg("Year pages: %d events listed for %d-%d", nrow(events), min(years), max(years))

# Keep events within +/-1 day of a UFC event date (time zones) and up to the freeze date.
near_ufc <- vapply(events$event_date, \(d) any(abs(as.numeric(d - ufc_dates)) <= 1), logical(1))
cand <- events |> filter(near_ufc, event_date <= FREEZE_DATE, event_date >= START_DATE)
log_msg("Candidate events (date matches a UFC event): %d", nrow(cand))

# 3. Event pages: confirm UFC via the logo and collect decision links.
ev_dec <- map2_dfr(cand$event_id, cand$event_href, \(id, href) {
  out <- mmad_event_decisions(id, href)
  out
})
ufc_dec <- ev_dec |> filter(is_ufc, !is.na(decision_href)) |> distinct(decision_href, .keep_all = TRUE)
log_msg("UFC events: %d | decision pages to fetch: %d",
        n_distinct(ev_dec$event_id[ev_dec$is_ufc %in% TRUE]), nrow(ufc_dec))
readr::write_csv(cand, file.path(MMAD_RAW, "candidate_events.csv"))
readr::write_csv(ev_dec, file.path(MMAD_RAW, "event_decision_links.csv"))

# 4. Decision pages (the slow part). Progress is logged every 100 pages.
for (i in seq_len(nrow(ufc_dec))) {
  html <- tryCatch(mmad_decision_html(ufc_dec$decision_href[i]),
                   error = \(e) { log_msg("ERROR %s: %s", ufc_dec$decision_href[i], conditionMessage(e)); NA })
  if (i %% 100 == 0 || i == nrow(ufc_dec)) log_msg("Decision pages: %d / %d", i, nrow(ufc_dec))
}
log_msg("DONE")
