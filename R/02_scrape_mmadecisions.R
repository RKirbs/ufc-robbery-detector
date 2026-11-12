# 02_scrape_mmadecisions.R: collect official judge round-by-round scorecards
# and media scorecards from MMADecisions.com.
#
# Access note: MMADecisions' robots.txt disallows generic bots, but the site
# owner gave the project author permission (2026-11-11) to collect the data
# (see NOTES.md). We still scrape politely: one request at a time, 1.5-3 s
# pauses, an honest user agent, and every page cached to data/raw/mmadecisions/
# so nothing is downloaded twice.

suppressPackageStartupMessages({
  library(rvest)
  library(dplyr)
  library(purrr)
  library(stringr)
  library(tibble)
})

MMAD_BASE <- "https://mmadecisions.com/"
MMAD_RAW  <- "data/raw/mmadecisions"

# Squish text and convert non-breaking spaces to plain spaces.
clean_txt <- function(x) str_squish(str_replace_all(x, " ", " "))

# Extract the numeric ID from links like "decision/16460/Name-vs-Name".
href_id <- function(href) as.integer(str_match(href, "/(\\d+)/")[, 2])

# ---- Year index ---------------------------------------------------------------

# List every event on a year page with its date and number of decisions.
mmad_year_events <- function(year) {
  html <- fetch_cached(paste0(MMAD_BASE, "decisions-by-event/", year, "/"),
                       file.path(MMAD_RAW, "years", paste0(year, ".html")))
  rows <- read_html(html) |> html_elements("tr.decision")
  tibble(
    event_date  = rows |> html_element("td.list-center") |> html_text() |> clean_txt(),
    event_href  = rows |> html_element("td.list a") |> html_attr("href") |> str_squish(),
    event_name  = rows |> html_element("td.list a") |> html_text() |> clean_txt(),
    n_decisions = rows |> html_element("td.list-center:nth-of-type(3)") |> html_text() |>
      clean_txt() |> as.integer()
  ) |>
    filter(!is.na(event_href)) |>
    mutate(event_date = as.Date(event_date, format = "%b %d, %Y"),
           event_id = href_id(event_href), year = year)
}

# ---- Event page ---------------------------------------------------------------

# Download an event page; return whether it is a UFC event (the site shows a UFC
# logo for UFC cards) and the links to its decision pages.
mmad_event_decisions <- function(event_id, event_href) {
  html <- fetch_cached(paste0(MMAD_BASE, event_href),
                       file.path(MMAD_RAW, "events", paste0(event_id, ".html")))
  if (is.na(html)) return(tibble(event_id = event_id, is_ufc = NA, decision_href = NA_character_))
  hrefs <- read_html(html) |> html_elements("a[href^='decision/']") |>
    html_attr("href") |> str_squish() |> unique()
  tibble(event_id = event_id,
         is_ufc = str_detect(html, "ufc_small\\.png"),
         decision_href = if (length(hrefs)) hrefs else NA_character_)
}

# ---- Decision page ------------------------------------------------------------

# Download (or read from cache) one decision page.
mmad_decision_html <- function(decision_href) {
  id <- href_id(decision_href)
  fetch_cached(paste0(MMAD_BASE, decision_href),
               file.path(MMAD_RAW, "decisions", paste0(id, ".html")))
}

# Parse one decision page into three tidy tables:
#   fight  - one row: fighters, result, method, event, date
#   judges - one row per judge x round with both fighters' scores
#   media  - one row per media member: outlet, score, who they picked
# Fighter 1 is the fighter listed on top (the declared winner unless it's a draw).
mmad_parse_decision <- function(html, decision_id) {
  doc <- read_html(html)
  f1 <- doc |> html_element("td.decision-top a[href^='fighter/']")
  f2 <- doc |> html_element("td.decision-bottom a[href^='fighter/']")
  ev <- doc |> html_element("td.decision-top2")
  ev_lines <- ev |> html_text2() |> str_split("\n") |> pluck(1) |> clean_txt()
  ev_lines <- ev_lines[ev_lines != ""]

  fight <- tibble(
    decision_id = decision_id,
    fighter1 = clean_txt(html_text(f1)), fighter1_id = href_id(html_attr(f1, "href")),
    fighter2 = clean_txt(html_text(f2)), fighter2_id = href_id(html_attr(f2, "href")),
    result_word = doc |> html_element("td.decision-middle") |> html_text() |> clean_txt(),
    method = doc |> html_element("th.event2") |> html_text() |> clean_txt(),
    event_name = ev |> html_element("a") |> html_text() |> clean_txt(),
    event_id = ev |> html_element("a") |> html_attr("href") |> href_id(),
    event_date = as.Date(ev_lines[2], format = "%B %d, %Y"),
    location = ev_lines[3],
    is_ufc = str_detect(html, "ufc_small\\.png")
  )

  # Each judge's card is a small table headed by td.judge.
  judge_cells <- doc |> html_elements("td.judge")

  # Card totals. Older pages often show "-" for every round but still give the
  # judge's total, so we keep totals separately.
  judge_totals <- map_dfr(seq_along(judge_cells), \(i) {
    tbl <- judge_cells[[i]] |> html_element(xpath = "ancestor::table[1]")
    tot <- tbl |> html_elements("td.bottom-cell") |> html_text() |> clean_txt()
    tibble(decision_id = decision_id, judge_order = i,
           judge = judge_cells[[i]] |> html_text() |> clean_txt(),
           judge_id = judge_cells[[i]] |> html_element("a") |> html_attr("href") |> href_id(),
           total_f1 = suppressWarnings(as.integer(tot[1])),
           total_f2 = suppressWarnings(as.integer(tot[2])))
  })

  judges <- map_dfr(seq_along(judge_cells), \(i) {
    tbl <- judge_cells[[i]] |> html_element(xpath = "ancestor::table[1]")
    rows <- tbl |> html_elements("tr.decision")
    cells <- map(rows, \(r) r |> html_elements("td") |> html_text() |> clean_txt())
    cells <- keep(cells, \(x) length(x) == 3)
    if (!length(cells)) return(NULL)
    tibble(
      decision_id = decision_id,
      judge_order = i,
      judge = judge_cells[[i]] |> html_text() |> clean_txt(),
      judge_id = judge_cells[[i]] |> html_element("a") |> html_attr("href") |> href_id(),
      round = map_chr(cells, 1),
      score_f1 = suppressWarnings(as.integer(map_chr(cells, 2))),
      score_f2 = suppressWarnings(as.integer(map_chr(cells, 3)))
    )
  })

  # Media scores are the rows that follow the "MEDIA SCORES" header row (matched
  # exactly so we don't pick up the tale-of-the-tape rows in the outer table).
  rows <- doc |> html_elements(xpath = paste0(
    "//td[normalize-space(.)='MEDIA SCORES']/parent::tr",
    "/following-sibling::tr[contains(@class,'decision')]"))
  media <- if (!length(rows)) NULL else {
    map_dfr(rows, \(r) {
      td <- r |> html_elements("td")
      if (length(td) < 3) return(NULL)
      who <- td[[1]] |> html_text2() |> str_split("\n") |> pluck(1) |> clean_txt()
      tibble(decision_id = decision_id,
             media_member = who[1],
             outlet = if (length(who) > 1) paste(who[-1], collapse = " ") else NA_character_,
             media_score = clean_txt(html_text(td[[2]])),
             media_pick = clean_txt(html_text(td[[3]])))
    })
  }

  list(fight = fight, judges = judges, judge_totals = judge_totals, media = media)
}

# Parse every cached decision page and stack the results into three tables.
# Pages that fail to parse are reported, not silently dropped.
parse_all_decisions <- function(files) {
  ids <- as.integer(tools::file_path_sans_ext(basename(files)))
  parsed <- map2(files, ids, \(f, id) tryCatch(
    mmad_parse_decision(readr::read_file(f), id),
    error = \(e) { warning(sprintf("Parse failed for decision %s: %s", id, conditionMessage(e))); NULL }))
  parsed <- compact(parsed)
  list(fight        = map_dfr(parsed, "fight"),
       judges       = map_dfr(parsed, "judges"),
       judge_totals = map_dfr(parsed, "judge_totals"),
       media        = map_dfr(parsed, "media"))
}

# Point deductions. Pages note them as "Swick was deducted 1 point in round 3:
# Grabbing the Cage". Judges' round scores on MMADecisions already include the
# deduction, so we record them to (a) restore each judge's own round call for
# modeling and (b) apply them to simulated cards.
mmad_parse_deductions <- function(files) {
  map_dfr(files, \(f) {
    s <- readr::read_file(f)
    if (!str_detect(s, regex("was deducted", ignore_case = TRUE))) return(NULL)
    t <- s |> str_replace_all("<[^>]+>", " | ") |> str_squish()
    m <- str_match_all(t, regex("([^|]{1,60}?) was deducted (\\d+) points? in round (\\d+):?\\s*\\|?\\s*([^|]*)",
                                ignore_case = TRUE))[[1]]
    if (!nrow(m)) return(NULL)
    tibble(decision_id = as.integer(tools::file_path_sans_ext(basename(f))),
           who = str_squish(m[, 2]), points = as.integer(m[, 3]),
           round = as.integer(m[, 4]), reason = str_squish(m[, 5]))
  })
}

# Write a data frame to Parquet and return its path (for format = "file" targets).
write_parquet_target <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  arrow::write_parquet(df, path)
  path
}
