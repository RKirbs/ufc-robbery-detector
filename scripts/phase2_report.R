# phase2_report.R: diagnostics for the Phase 2 checkpoint (coverage, linkage,
# data consistency). Reads built targets only; run after targets::tar_make().

suppressPackageStartupMessages({ library(targets); library(dplyr); library(tidyr); library(stringr) })
source("R/utils.R")
tar_load(c(mmad_parsed, ufc_fights, links, link_report, judge_rounds, fight_table, rs_wide))
set.seed(2026)
hr <- \(x) cat("\n==== ", x, " ====\n", sep = "")

hr("1. Collection")
cat("MMADecisions UFC decision pages parsed:", nrow(mmad_parsed$fight),
    "| non-UFC:", sum(!mmad_parsed$fight$is_ufc), "\n")
ufc_dec <- ufc_fights |> filter(is_decision)
cat("UFCStats decisions in window:", nrow(ufc_dec), "\n")

hr("2. Linkage")
print(link_report$by_confidence)
print(link_report$winner_check)
cat("UFCStats decisions linked:", sum(ufc_dec$fight_url %in% fight_table$fight_url), "of", nrow(ufc_dec),
    sprintf("(%.1f%%)\n", 100 * mean(ufc_dec$fight_url %in% fight_table$fight_url)))
cat("\nUFCStats decisions with no MMADecisions page:\n")
print(ufc_dec |> filter(!fight_url %in% fight_table$fight_url) |> select(date, event, bout, method), n = 50)
cat("\nMMADecisions decisions not linked:\n")
print(links |> filter(confidence == "unmatched") |> select(mmad_date, mmad_event, fighter1, fighter2), n = 50)
cat("\nNon-high-confidence links (hand review):\n")
print(links |> filter(confidence %in% c("medium", "low")) |>
        select(mmad_date, fighter1, fighter2, fighter_a, fighter_b, min_sim, confidence), n = 60, width = 200)

hr("3. Hand-check sample: 12 random high-confidence links")
print(links |> filter(confidence == "high") |> slice_sample(n = 12) |>
        select(mmad_date, ufc_date, fighter1, fighter2, fighter_a, fighter_b, min_sim), width = 200)

hr("4. Coverage by year")
cov <- fight_table |>
  mutate(year = as.integer(format(date, "%Y"))) |>
  group_by(year) |>
  summarise(decisions = n(),
            round_scores_pct = round(100 * mean(has_round_scores %in% TRUE), 1),
            media_any_pct = round(100 * mean(n_media > 0), 1),
            media_mean = round(mean(n_media), 1),
            split = sum(decision_type == "Split", na.rm = TRUE),
            draws = sum(winner == "draw"))
print(cov, n = 30)
cat("\nTotals: decisions", nrow(fight_table),
    "| with full judge round scores", sum(fight_table$has_round_scores %in% TRUE),
    "| with >=1 media score", sum(fight_table$n_media > 0),
    "| media scores", sum(fight_table$n_media), "\n")
cat("Media picks that couldn't be mapped to a fighter:", sum(fight_table$n_media_unmapped, na.rm = TRUE), "\n")
cat("Placeholder judge totals (e.g. 1-0):", sum(fight_table$placeholder_totals, na.rm = TRUE), "fights\n")

hr("5. Judge x round table")
cat("Rows:", nrow(judge_rounds), "| fights:", n_distinct(judge_rounds$fight_url),
    "| rounds:", nrow(distinct(judge_rounds, fight_url, round)), "\n")
print(judge_rounds |> count(margin, judge_winner) |> mutate(pct = round(100 * n / sum(n), 2)))
jn <- judge_rounds |> count(judge_id, judge, sort = TRUE)
cat("Judges:", nrow(jn), "| with >=100 rounds:", sum(jn$n >= 100), "| >=300:", sum(jn$n >= 300), "\n")
print(head(jn, 10))
cat("Missing values in feature columns:\n")
print(colSums(is.na(select(judge_rounds, starts_with("d_"))))[colSums(is.na(select(judge_rounds, starts_with("d_")))) > 0])

hr("6. Consistency checks")
# (a) Round scores sum to the card total.
chk <- mmad_parsed$judges |>
  group_by(decision_id, judge_order) |>
  summarise(s1 = sum(score_f1), s2 = sum(score_f2), .groups = "drop") |>
  filter(!is.na(s1)) |>
  inner_join(mmad_parsed$judge_totals, by = c("decision_id", "judge_order"))
cat("Cards where round scores sum to the total:", sum(chk$s1 == chk$total_f1 & chk$s2 == chk$total_f2),
    "of", nrow(chk), "\n")
# (b) The round count on the cards matches the rounds fought on UFCStats.
rc <- judge_rounds |> group_by(fight_url, judge_id) |> summarise(r = n(), .groups = "drop") |>
  left_join(ufc_fights |> select(fight_url, last_round), by = "fight_url")
cat("Judge cards whose round count matches UFCStats:", sum(rc$r == rc$last_round), "of", nrow(rc), "\n")
# (c) Sanity: how often the round's significant-strike leader wins the judge's card.
s <- judge_rounds |> filter(judge_winner != "even", d_sig_l != 0)
cat(sprintf("Sanity: judge gives the round to the sig-strike leader in %.1f%% of rounds (n = %d)\n",
            100 * mean((s$d_sig_l > 0) == (s$judge_winner == "a")), nrow(s)))
# (d) Red corner share of judge round wins (descriptive only; not a finding yet).
cat(sprintf("Descriptive: red corner (A) wins %.1f%% of non-even judge rounds\n",
            100 * mean(judge_rounds$judge_winner[judge_rounds$judge_winner != "even"] == "a")))

readr::write_csv(links |> filter(confidence != "high"), "data/interim/links_for_review.csv")
