# 04_link_records.R: link MMADecisions decisions to UFCStats fights.
#
# The sources spell names differently (accents, nicknames, "Jr.", transliteration)
# and can date events a day apart (time zones). We match on:
#   1. event date within +/- 1 day, and
#   2. Jaro-Winkler similarity of BOTH fighters' normalised names, trying both
#      orderings (MMADecisions lists the winner first; UFCStats lists the red corner first).
# Each link gets a confidence label so low-confidence matches can be hand-reviewed.

suppressPackageStartupMessages({ library(dplyr); library(stringr); library(purrr) })

# Name similarity in [0, 1] (1 = identical) on normalised names. It's the
# best of three comparisons, so it handles the usual differences between sources:
#   - plain Jaro-Winkler ("Antonio" vs "Antônio" after accent stripping),
#   - Jaro-Winkler on alphabetically sorted words ("Zhang Tiequan" vs "Tiequan Zhang"),
#   - a subset rule: all words of the shorter name appear in the longer
#     ("Rogerio Nogueira" vs "Antonio Rogerio Nogueira").
name_sim <- function(x, y) {
  nx <- normalize_name(x); ny <- normalize_name(y)
  sort_words <- \(s) vapply(str_split(s, " "), \(w) paste(sort(w), collapse = " "), "")
  jw <- \(a, b) 1 - stringdist::stringdist(a, b, method = "jw", p = 0.1)
  subset <- map2_lgl(str_split(nx, " "), str_split(ny, " "), \(a, b) {
    if (anyNA(a) || anyNA(b)) return(FALSE)
    short <- if (length(a) <= length(b)) a else b
    long  <- if (length(a) <= length(b)) b else a
    length(short) >= 2 && all(short %in% long)
  })
  pmax(jw(nx, ny), jw(sort_words(nx), sort_words(ny)), if_else(subset, 0.97, 0))
}

# Last word of a normalised name (surname proxy), used as a secondary check.
surname <- function(x) word(normalize_name(x), -1)

# Link each MMADecisions fight to its best UFCStats candidate.
# Returns one row per MMADecisions decision with the matched fight_url (or NA),
# the orientation (is MMADecisions fighter 1 = UFCStats fighter A?), the
# similarity scores and a confidence label.
link_mmad_ufcstats <- function(mmad_fights, ufc_fights) {
  m <- mmad_fights |>
    filter(is_ufc) |>
    select(decision_id, fighter1, fighter2, mmad_date = event_date, mmad_event = event_name) |>
    mutate(lo = mmad_date - 1, hi = mmad_date + 1)
  u <- ufc_fights |>
    filter(is_decision) |>
    select(fight_url, fighter_a, fighter_b, ufc_date = date, ufc_event = event, outcome_a)

  cand <- inner_join(m, u, by = join_by(between(y$ufc_date, x$lo, x$hi))) |>
    mutate(
      s1a = name_sim(fighter1, fighter_a), s2b = name_sim(fighter2, fighter_b),
      s1b = name_sim(fighter1, fighter_b), s2a = name_sim(fighter2, fighter_a),
      sim_same  = pmin(s1a, s2b),
      sim_swap  = pmin(s1b, s2a),
      f1_is_a   = sim_same >= sim_swap,
      min_sim   = pmax(sim_same, sim_swap),
      # Similarity of the better-matching fighter in the chosen orientation.
      max_sim   = if_else(f1_is_a, pmax(s1a, s2b), pmax(s1b, s2a)),
      surnames_match = if_else(f1_is_a,
        surname(fighter1) == surname(fighter_a) & surname(fighter2) == surname(fighter_b),
        surname(fighter1) == surname(fighter_b) & surname(fighter2) == surname(fighter_a))
    )

  # Best candidate per MMADecisions decision, then enforce one-to-one matching
  # (a UFCStats fight can be claimed by only its best-scoring MMADecisions row).
  # Rank by the weaker fighter's similarity first, then by the stronger one.
  best <- cand |>
    arrange(desc(min_sim), desc(max_sim)) |>
    distinct(decision_id, .keep_all = TRUE) |>
    distinct(fight_url, .keep_all = TRUE)

  m |>
    select(decision_id, fighter1, fighter2, mmad_date, mmad_event) |>
    left_join(best |> select(decision_id, fight_url, fighter_a, fighter_b, ufc_date, ufc_event,
                             outcome_a, f1_is_a, min_sim, max_sim, surnames_match),
              by = "decision_id") |>
    mutate(confidence = case_when(
      is.na(fight_url) ~ "unmatched",
      min_sim >= 0.90 | (surnames_match & min_sim >= 0.80) ~ "high",
      # One fighter matches near-exactly on the same card and the other partly:
      # usually a nickname or alias (Kimbo Slice = Kevin Ferguson). Hand-reviewed.
      max_sim >= 0.93 & min_sim >= 0.55 ~ "medium",
      min_sim >= 0.75 ~ "low",
      TRUE ~ "unmatched"
    ),
    fight_url = if_else(confidence == "unmatched", NA_character_, fight_url))
}

# Summarise linkage quality: match rates by confidence, plus a winner-consistency
# check (MMADecisions' fighter 1 should be the UFCStats winner).
linkage_report <- function(links, mmad_fights) {
  chk <- links |>
    left_join(mmad_fights |> select(decision_id, result_word), by = "decision_id") |>
    mutate(f1_outcome = if_else(f1_is_a, outcome_a,
                                recode(outcome_a, W = "L", L = "W")),
           winner_consistent = case_when(
             is.na(fight_url) ~ NA,
             str_detect(result_word, "defeat") ~ f1_outcome == "W",
             TRUE ~ f1_outcome == "D"))
  list(
    by_confidence = count(links, confidence) |> mutate(pct = round(100 * n / sum(n), 1)),
    winner_check  = count(chk, winner_consistent),
    inconsistent  = filter(chk, winner_consistent %in% FALSE)
  )
}
