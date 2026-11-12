# 03_bestfightodds.R: historical betting odds from BestFightOdds (Phase 6).
#
# Access check (2026-11-12): robots.txt allows everything except /cnadm/, and the
# terms of service contain only a warranty disclaimer (copies in phase0_audit/).
# Event pages only show today's sportsbooks, so historical lines come from
# fighter pages, which list every fight with the opening line and the closing
# range across books. One fighter page also shows the opponent's line, so we
# fetch a small set of fighter pages that covers every UFC decision (greedy set
# cover), politely and cached like everything else.

suppressPackageStartupMessages({ library(dplyr); library(stringr); library(purrr); library(rvest) })

BFO_BASE <- "https://www.bestfightodds.com"
BFO_RAW <- "data/raw/bestfightodds"
BFO_SINCE <- as.Date("2007-01-01")   # BestFightOdds coverage starts around 2007

# Fighter index from the site's own sitemap (URL slug -> name).
bfo_fighter_index <- function(sitemap = file.path(BFO_RAW, "sitemap-teams.xml")) {
  urls <- str_match_all(readr::read_file(sitemap), "<loc>([^<]+)</loc>")[[1]][, 2]
  m <- str_match(urls, "/fighters/(.+)-(\\d+)$")
  tibble(url = urls, key = str_replace_all(m[, 2], "-", " "), bfo_id = m[, 3]) |>
    filter(!is.na(bfo_id)) |>
    add_count(key, name = "n_pages")
}

# Pages to fetch: a greedy set cover of decisions using fighters with exactly one
# matching page, plus every candidate page for fighters in fights left uncovered.
bfo_targets <- function(fight_table, index, since = BFO_SINCE) {
  d <- fight_table |> filter(date >= since)
  long <- bind_rows(d |> transmute(fight_url, fighter = fighter_a),
                    d |> transmute(fight_url, fighter = fighter_b)) |>
    mutate(key = normalize_name(fighter)) |>
    left_join(index, by = "key", relationship = "many-to-many")
  uniq <- filter(long, n_pages == 1)
  uncov <- unique(uniq$fight_url)
  picked <- character()
  while (length(uncov)) {
    s <- uniq |> filter(fight_url %in% uncov) |> count(url, sort = TRUE)
    if (!nrow(s)) break
    picked <- c(picked, s$url[1])
    uncov <- setdiff(uncov, uniq$fight_url[uniq$url == s$url[1]])
  }
  rest <- setdiff(d$fight_url, uniq$fight_url)
  extra <- long |> filter(fight_url %in% rest, !is.na(url)) |> pull(url)
  unique(c(picked, extra))
}

bfo_cache_path <- function(url) file.path(BFO_RAW, "fighters", paste0(basename(url), ".html"))

# American odds string ("+110", "-155") -> implied probability.
american_to_prob <- function(x) {
  v <- suppressWarnings(as.numeric(str_replace(x, "^\\+", "")))
  case_when(is.na(v) ~ NA_real_, v < 0 ~ -v / (-v + 100), TRUE ~ 100 / (v + 100))
}

# Parse one fighter page: one row per (fight, side) with the opening line and
# the closing range. Rows come in pairs (fighter, opponent) under an event header.
bfo_parse_fighter <- function(path) {
  doc <- read_html(path)
  tab <- html_element(doc, "table.team-stats-table")
  if (is.na(tab)) return(NULL)
  rows <- html_elements(tab, "tbody tr")
  out <- list(); hdr <- NA_character_
  i <- 1
  while (i <= length(rows)) {
    cls <- coalesce(html_attr(rows[[i]], "class"), "")
    if (str_detect(cls, "event-header")) { hdr <- html_text2(rows[[i]]); i <- i + 1; next }
    if (str_detect(cls, "main-row") && i < length(rows)) {
      a <- rows[[i]]; b <- rows[[i + 1]]
      cell <- \(r) html_elements(r, "th, td")
      ca <- cell(a); cb <- cell(b)
      txt_a <- html_text2(ca); txt_b <- html_text2(cb)
      odds_a <- str_subset(txt_a, "^[+-]\\d+$"); odds_b <- str_subset(txt_b, "^[+-]\\d+$")
      ev_link <- html_element(a, "a[href*='/events/']")
      out[[length(out) + 1]] <- tibble(
        page = basename(path), header = hdr,
        event_name = html_text2(ev_link), event_href = html_attr(ev_link, "href"),
        date_text = tail(txt_b, 1),
        fighter = txt_a[1], opponent = txt_b[1],
        f_open = odds_a[1], f_close_lo = odds_a[2], f_close_hi = odds_a[3],
        o_open = odds_b[1], o_close_lo = odds_b[2], o_close_hi = odds_b[3])
      i <- i + 2; next
    }
    i <- i + 1
  }
  bind_rows(out)
}
