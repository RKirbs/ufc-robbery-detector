# 04_link_records.R: link MMADecisions decisions to UFCStats fights.
#
# The sources spell names differently (accents, nicknames, "Jr.", transliteration)
# and can date events a day apart (time zones). We match on:
#   1. event date within +/- 1 day, and
#   2. Jaro-Winkler similarity of BOTH fighters' normalised names, trying both
#      orderings (MMADecisions lists the winner first; UFCStats lists the red corner first).
# Each link gets a confidence label so low-confidence matches can be hand-reviewed.

suppressPackageStartupMessages({ library(dplyr); library(stringr) })

# Jaro-Winkler similarity in [0, 1] (1 = identical) on normalised names.
name_sim <- function(x, y) 1 - stringdist::stringdist(normalize_name(x), normalize_name(y),
                                                      method = "jw", p = 0.1)

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
      sim_same  = pmin(name_sim(fighter1, fighter_a), name_sim(fighter2, fighter_b)),
      sim_swap  = pmin(name_sim(fighter1, fighter_b), name_sim(fighter2, fighter_a)),
      f1_is_a   = sim_same >= sim_swap,
      min_sim   = pmax(sim_same, sim_swap),
      surnames_match = if_else(f1_is_a,
        surname(fighter1) == surname(fighter_a) & surname(fighter2) == surname(fighter_b),
        surname(fighter1) == surname(fighter_b) & surname(fighter2) == surname(fighter_a))
    )

  # Best candidate per MMADecisions decision, then enforce one-to-one matching
  # (a UFCStats fight can be claimed by only its best-scoring MMADecisions row).
  best <- cand |>
    group_by(decision_id) |> slice_max(min_sim, n = 1, with_ties = FALSE) |> ungroup() |>
    group_by(fight_url) |> slice_max(min_sim, n = 1, with_ties = FALSE) |> ungroup()

  m |>
    select(decision_id, fighter1, fighter2, mmad_date, mmad_event) |>
    left_join(best |> select(decision_id, fight_url, fighter_a, fighter_b, ufc_date, ufc_event,
                             outcome_a, f1_is_a, min_sim, surnames_match),
              by = "decision_id") |>
    mutate(confidence = case_when(
      is.na(fight_url) ~ "unmatched",
      min_sim >= 0.90 | (surnames_match & min_sim >= 0.80) ~ "high",
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
