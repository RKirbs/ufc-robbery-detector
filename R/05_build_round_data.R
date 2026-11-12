# 05_build_round_data.R: clean the UFCStats (Greco1899) tables into a fight
# table and a fighter x round stats table, then join official judge scores
# from MMADecisions to build the judge x round modeling table.

suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(stringr); library(purrr) })

# Some events appear under two names in the mirror (for example "UFC Fight Night:
# Lopes vs. Silva" and "Noche UFC: Lopes vs. Silva"). Map them to the name used
# in the events file so each fight appears once.
EVENT_ALIASES <- c(
  "UFC Fight Night: Lopes vs. Silva"         = "Noche UFC: Lopes vs. Silva",
  "UFC Fight Night: Grasso vs. Shevchenko 2" = "Noche UFC: Grasso vs. Shevchenko 2"
)
fix_event <- function(x) dplyr::recode(x, !!!EVENT_ALIASES)

# Build one row per UFC fight with dates, fighters (A = listed first, which on
# UFCStats is the red corner), result, method and scheduled rounds.
clean_greco_fights <- function(greco) {
  greco$results |>
    mutate(EVENT = fix_event(EVENT)) |>
    distinct(URL, .keep_all = TRUE) |>
    inner_join(greco$events |> select(EVENT, event_url = URL, date, LOCATION), by = "EVENT") |>
    separate_wider_delim(BOUT, " vs. ", names = c("fighter_a", "fighter_b"),
                         too_many = "merge", cols_remove = FALSE) |>
    transmute(
      fight_url = URL, event = EVENT, event_url, date, location = LOCATION, bout = BOUT,
      fighter_a = str_squish(fighter_a), fighter_b = str_squish(fighter_b),
      outcome_a = str_extract(OUTCOME, "^[A-Z]+"),        # W, L, D, NC for fighter A
      method = str_squish(METHOD),
      is_decision = str_detect(method, "^Decision"),
      decision_type = str_extract(method, "Unanimous|Split|Majority"),
      last_round = as.integer(ROUND),
      sched_rounds = as.integer(str_extract(`TIME FORMAT`, "^\\d+")),
      weightclass = WEIGHTCLASS,
      title_fight = str_detect(WEIGHTCLASS, regex("title", ignore_case = TRUE)),
      referee = REFEREE, details = DETAILS
    )
}

# Parse the per-round stats into numeric columns (landed/attempted pairs and
# control time in seconds). Keep only "Round N" rows (not fight totals).
clean_greco_round_stats <- function(greco, fights) {
  greco$stats |>
    mutate(EVENT = fix_event(EVENT)) |>
    filter(str_detect(ROUND, "^Round \\d+$")) |>
    distinct() |>
    # Stats carry no fight URL, so join on event + bout. Drop the rare ambiguous
    # pairs (the same bout twice on one card: only UFC Japan 1997, outside our window).
    inner_join(fights |> add_count(event, bout) |> filter(n == 1) |>
                 select(event, bout, fight_url, fighter_a, fighter_b),
               by = c("EVENT" = "event", "BOUT" = "bout")) |>
    transmute(
      fight_url, round = as.integer(str_extract(ROUND, "\\d+")),
      fighter = str_squish(FIGHTER),
      corner = case_when(fighter == fighter_a ~ "a", fighter == fighter_b ~ "b"),
      kd = as.numeric(KD),
      sig_l = parse_of(`SIG.STR.`, "landed"),  sig_a = parse_of(`SIG.STR.`, "attempted"),
      tot_l = parse_of(`TOTAL STR.`, "landed"), tot_a = parse_of(`TOTAL STR.`, "attempted"),
      td_l = parse_of(TD, "landed"), td_a = parse_of(TD, "attempted"),
      sub_att = as.numeric(SUB.ATT), rev = as.numeric(REV.),
      ctrl_s = parse_mmss(CTRL),
      head_l = parse_of(HEAD, "landed"),     head_a = parse_of(HEAD, "attempted"),
      body_l = parse_of(BODY, "landed"),     body_a = parse_of(BODY, "attempted"),
      leg_l  = parse_of(LEG, "landed"),      leg_a  = parse_of(LEG, "attempted"),
      dist_l = parse_of(DISTANCE, "landed"), dist_a = parse_of(DISTANCE, "attempted"),
      clinch_l = parse_of(CLINCH, "landed"), clinch_a = parse_of(CLINCH, "attempted"),
      ground_l = parse_of(GROUND, "landed"), ground_a = parse_of(GROUND, "attempted")
    )
}

# Stats whose A-minus-B differential is a model feature.
DIFF_VARS <- c("kd", "sig_l", "sig_a", "tot_l", "td_l", "td_a", "sub_att", "rev", "ctrl_s",
               "head_l", "body_l", "leg_l", "dist_l", "clinch_l", "ground_l")

# Build the modeling table: one row per judge x round of a linked decision.
# Scores are re-oriented from MMADecisions (fighter 1 = winner) to UFCStats
# (A = red corner), and each row gets that round's stats only (no leakage
# from other rounds or from the result).
build_judge_rounds <- function(judge_rounds, links, rs_wide, ufc_fights) {
  judge_rounds |>
    mutate(round = suppressWarnings(as.integer(round))) |>
    filter(!is.na(round), !is.na(score_f1), !is.na(score_f2)) |>
    inner_join(links |> filter(confidence != "unmatched") |>
                 select(decision_id, fight_url, f1_is_a, link_confidence = confidence),
               by = "decision_id") |>
    mutate(score_a = if_else(f1_is_a, score_f1, score_f2),
           score_b = if_else(f1_is_a, score_f2, score_f1),
           judge_winner = case_when(score_a > score_b ~ "a", score_b > score_a ~ "b", TRUE ~ "even"),
           margin = abs(score_a - score_b)) |>          # 1 = 10-9, 2 = 10-8, 0 = 10-10
    inner_join(rs_wide, by = c("fight_url", "round")) |>
    left_join(ufc_fights |> select(fight_url, date, event, fighter_a, fighter_b, outcome_a,
                                   decision_type, sched_rounds, title_fight, weightclass),
              by = "fight_url") |>
    mutate(across(all_of(paste0(DIFF_VARS, "_a")),
                  \(x) x - get(sub("_a$", "_b", cur_column())),
                  .names = "d_{sub('_a$', '', .col)}"))
}

# Reshape fighter rows to one row per fight-round with A and B stats side by side.
round_stats_wide <- function(round_stats) {
  round_stats |>
    filter(!is.na(corner)) |>
    select(-fighter) |>
    distinct(fight_url, round, corner, .keep_all = TRUE) |>
    pivot_wider(names_from = corner, values_from = -c(fight_url, round, corner),
                names_glue = "{.value}_{corner}")
}
