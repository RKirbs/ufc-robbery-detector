# phase4_report.R: tables and figures for the Phase 4 checkpoint (simulation,
# judge correlation, Robbery Index). Reads built targets only.

suppressPackageStartupMessages({
  library(targets); library(dplyr); library(tidyr); library(ggplot2); library(purrr)
})
source("R/utils.R")
source("R/06_round_model.R")
source("R/07_simulate.R")
tar_load(c(round_probs, triples, judge_corr, judge_corr_glmnet, ten_eight_corr, ten_ten_model,
           sims, sims_glmnet, robbery_index, fight_direct, card_check, fight_table))
hr <- \(x) cat("\n==== ", x, " ====\n", sep = "")
options(width = 250, pillar.sigfig = 3)
tier_cols <- c(Clean = "#F2C4CB", `Close / defensible` = "#E08494", Questionable = "#C8445A", Robbery = "#8E0C22")

ri <- robbery_index |> filter(winner != "draw")

hr("1. Round probabilities")
print(count(round_probs, source))

hr("2. Judge correlation (who wins the round)")
print(judge_corr)
cat("glmnet version:\n"); print(judge_corr_glmnet)
cat("Interpretation: implied correlation between two judges' round calls (phi), at p = 0.5, 0.7, 0.9:\n")
phi_at <- \(p, rho) {
  pk <- p_k_of_3(p, rho)               # P(k of 3); pairwise agreement from k distribution
  both <- pk[, 3] * (1 / 3) + pk[, 4]  # P(two given judges both pick A)
  (both - p^2) / (p * (1 - p))
}
print(tibble(p = c(0.5, 0.7, 0.9), phi = phi_at(c(0.5, 0.7, 0.9), judge_corr$rho)))

hr("3. 10-8 correlation and 10-10 model")
print(ten_eight_corr)
print(broom::tidy(ten_ten_model))

hr("4. Fight-level checks (non-draw decisions)")
fl <- ri |> select(fight_url, date, winner, p_a, p_b, p_draw, p_winner) |>
  left_join(fight_direct |> select(fight_url, p_direct), by = "fight_url") |>
  mutate(p_direct_winner = if_else(winner == "a", p_direct, 1 - p_direct))
cat("Simulation vs. direct fight model, correlation of P(A wins):",
    round(cor(fl$p_a / (fl$p_a + fl$p_b), fl$p_direct), 3), "\n")
print(bind_rows(simulation = score_fight_probs(fl$p_winner),
                direct_model = score_fight_probs(fl$p_direct_winner), .id = "model"))
cat("\nCalibration of P(fighter A wins), corner-known fights only (from", format(CORNER_KNOWN_FROM), "):\n")
cal <- fl |> filter(date >= CORNER_KNOWN_FROM) |> mutate(pa = p_a, ya = winner == "a", bin = cut(pa, seq(0, 1, 0.1), include.lowest = TRUE)) |>
  group_by(bin) |> summarise(n = n(), pred = mean(pa), obs = mean(ya))
print(cal)
cat("\nSplit decisions: predicted rate", round(mean(robbery_index$p_split), 3),
    "| actual", round(mean(fight_table$decision_type == "Split", na.rm = TRUE), 3), "\n")
cat("Draws: predicted rate", round(mean(robbery_index$p_draw), 4),
    "| actual", round(mean(fight_table$winner == "draw"), 4), "\n")

hr("5. Judge card totals vs. simulated single-judge card")
print(card_check |> filter(card_side != "even") |>
        group_by(group) |>
        summarise(cards = n(), fights = n_distinct(fight_url),
                  card_winner_agree = mean((p_card_a > 0.5) == (card_side == "a")),
                  log_loss = -mean(log(pmin(pmax(if_else(card_side == "a", p_card_a, 1 - p_card_a - p_card_even), 1e-4), 1))),
                  margin_cor = cor(exp_card_margin, margin_a)))

hr("6. Robbery Score distribution (non-draw decisions)")
print(quantile(ri$robbery_score, c(0, 0.1, 0.25, 0.5, 0.75, 0.9, 0.95, 0.99, 1)))
print(ri |> count(tier) |> mutate(pct = round(100 * n / sum(n), 1)))
print(ri |> group_by(decision_type) |> summarise(n = n(), mean_score = mean(robbery_score),
                                               robbery_or_q = mean(robbery_score >= 0.5)))
cat("Robbery-tier counts by era:\n")
print(ri |> mutate(era = cut(as.integer(format(date, "%Y")), c(2000, 2010, 2016, 2026), labels = c("2001-10", "2011-16", "2017-26"))) |>
        group_by(era) |> summarise(n = n(), questionable = mean(tier == "Questionable"), robbery = mean(tier == "Robbery")))

hr("6b. Media agreement by tier and score band (fights with >= 5 media scores)")
med <- ri |> filter(media_scored >= 5) |>
  mutate(media_majority_loser = media_for_loser > media_scored / 2)
print(med |> group_by(tier) |>
        summarise(n = n(), mean_media_loser_share = mean(media_loser_share),
                  media_majority_for_loser = mean(media_majority_loser)))
print(med |> mutate(band = cut(robbery_score, c(0, 0.25, 0.5, 0.6, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95, 1), include.lowest = TRUE)) |>
        group_by(band) |>
        summarise(n = n(), mean_media_loser_share = mean(media_loser_share),
                  media_majority_for_loser = mean(media_majority_loser)))
cat("Pearson r (score vs media loser share):", round(cor(med$robbery_score, med$media_loser_share), 3), "\n")
cat("Deduction fights:", sum(!is.na(ri$ded_note)), "| of which robbery-tier:", sum(!is.na(ri$ded_note) & ri$tier == "Robbery"), "\n")
rk <- filter(ri, date >= CORNER_KNOWN_FROM)
cat("Corner-known fights: mean simulated P(red wins) vs actual red win share (non-draws):",
    round(mean(rk$p_a), 3), "vs", round(mean(rk$winner == "a"), 3), "(n =", nrow(rk), ")\n")

hr("7. Sensitivity: glmnet round model")
sens <- ri |> select(fight_url, winner, robbery_score, tier) |>
  inner_join(sims_glmnet |> select(fight_url, g_a = p_a, g_b = p_b), by = "fight_url") |>
  mutate(score_glmnet = 1 - if_else(winner == "a", g_a, g_b), tier_glmnet = robbery_tier(score_glmnet))
cat("Spearman:", round(cor(sens$robbery_score, sens$score_glmnet, method = "spearman"), 3),
    "| Pearson:", round(cor(sens$robbery_score, sens$score_glmnet), 3),
    "| same tier:", round(mean(sens$tier == sens$tier_glmnet), 3), "\n")
top_x <- slice_max(sens, robbery_score, n = 25)$fight_url
top_g <- slice_max(sens, score_glmnet, n = 25)$fight_url
cat("Top-25 overlap:", length(intersect(top_x, top_g)), "of 25\n")
print(table(xgboost = sens$tier, glmnet = sens$tier_glmnet))

hr("8. Top 25")
show <- \(d) d |> transmute(date, event = stringr::str_trunc(event, 34), winner = winner_name, loser = loser_name,
                            decision_type, cards = judge_cards_a, p_win = round(p_winner, 3), p_draw = round(p_draw, 3),
                            score = round(robbery_score, 3), media_loser = scales::percent(media_loser_share, 1),
                            n_media = media_scored)
top25 <- ri |> arrange(desc(robbery_score)) |> head(25)
print(show(top25), n = 25)
cat("\nExplanations:\n"); walk2(seq_len(25), top25$why, \(i, w) cat(sprintf("%2d. %s\n", i, w)))
readr::write_csv(ri |> arrange(desc(robbery_score)) |> head(100), "data/interim/top100_robberies.csv")

hr("9. Bottom 25 (most clearly supported results)")
bot25 <- ri |> arrange(robbery_score, desc(abs(sig_w - sig_l))) |> head(25)
print(show(bot25), n = 25)

hr("10. Draws (reported separately)")
print(robbery_index |> filter(winner == "draw") |>
        summarise(n = n(), mean_p_draw = mean(p_draw), median_max_side = median(pmax(p_a, p_b))))

# ---- Figures --------------------------------------------------------------------

# Fig 1: Robbery Score distribution with tiers.
f1 <- ri |> mutate(bin = floor(robbery_score / 0.025) * 0.025 + 0.0125)
p1 <- ggplot(f1, aes(robbery_score, fill = tier)) +
  geom_histogram(breaks = seq(0, 1, 0.025), colour = "white", linewidth = 0.3) +
  geom_vline(xintercept = c(0.25, 0.5, 0.75), colour = pal[["ink"]], linetype = "dotted") +
  scale_fill_manual(values = tier_cols, name = NULL, drop = FALSE) +
  scale_x_continuous(breaks = seq(0, 1, 0.25)) +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "Robbery Score for every UFC decision, 2001 to 2026",
       subtitle = sprintf("Robbery Score = 1 - P(declared winner wins | fight stats). n = %s decisions (draws excluded).",
                          format(nrow(ri), big.mark = ",")),
       x = "Robbery Score", y = "Decisions", caption = SOURCE_CAPTION) +
  theme_robbery()
save_fig(p1, "p4_robbery_distribution", width = 9, height = 5)

# Fig 1b: zoom on the right tail (score >= 0.25) so the rare tiers are visible.
p1b <- p1
p1b$data <- filter(f1, robbery_score >= 0.25)
p1b <- p1b +
  labs(title = "The right tail: decisions the stats did not clearly support",
       subtitle = sprintf("Robbery Score >= 0.25 (n = %d).", sum(ri$robbery_score >= 0.25)))
save_fig(p1b, "p4_robbery_tail", width = 9, height = 5)

# Fig 2: does the judge-correlation model reproduce how often judges split?
f2 <- triples |>
  mutate(closeness = cut(pmin(p_a, 1 - p_a), c(0, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5), include.lowest = TRUE)) |>
  group_by(closeness) |>
  summarise(Observed = mean(!unanimous),
            `Model, correlated judges` = mean(1 - rowSums(p_k_of_3(p_a, judge_corr$rho)[, c(1, 4)])),
            `Model, independent judges` = mean(1 - rowSums(p_k_of_3(p_a, 0)[, c(1, 4)])),
            n = n(), .groups = "drop") |>
  pivot_longer(c(Observed, `Model, correlated judges`, `Model, independent judges`), names_to = "series", values_to = "split")
p2 <- ggplot(f2, aes(closeness, split, colour = series, group = series, shape = series)) +
  geom_line(linewidth = 0.9) + geom_point(size = 2.8) +
  scale_colour_manual(values = c(Observed = pal[["ink"]], `Model, correlated judges` = "#2a78d6",
                                 `Model, independent judges` = pal[["grey"]]), name = NULL) +
  scale_shape_manual(values = c(Observed = 16, `Model, correlated judges` = 17, `Model, independent judges` = 15), name = NULL) +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "How often the three judges split on a round",
       subtitle = sprintf("Rounds grouped by how lopsided the model thought they were.\nEstimated latent judge correlation rho = %.2f (95%% CI %.2f-%.2f).",
                          judge_corr$rho, judge_corr$rho_lo, judge_corr$rho_hi),
       x = "Model probability of the round's underdog (0 = one-sided, 0.5 = toss-up)", y = "Rounds with a split",
       caption = SOURCE_CAPTION) +
  theme_robbery()
save_fig(p2, "p4_judge_split_rates", width = 9, height = 5)

# Fig 3: fight-level calibration.
p3 <- cal |>
  ggplot(aes(pred, obs)) +
  geom_abline(linetype = "dashed", colour = pal[["grey"]]) +
  geom_point(aes(size = n), shape = 21, fill = "white", colour = pal[["ink"]], stroke = 1) +
  scale_size_area(max_size = 6, name = "Decisions") +
  scale_x_continuous(labels = scales::percent, limits = c(0, 1)) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
  coord_equal() +
  labs(title = "Fight-level calibration of the simulation",
       subtitle = "Simulated P(red corner wins) vs. how often the red corner won the decision\n(fights from March 2010 on, when UFCStats lists the red corner first).",
       x = "Simulated probability", y = "Observed share", caption = SOURCE_CAPTION) +
  theme_robbery()
save_fig(p3, "p4_fight_calibration", width = 6, height = 6)

# Fig 4: sensitivity to the round model.
p4 <- ggplot(sens, aes(robbery_score, score_glmnet)) +
  geom_abline(linetype = "dashed", colour = pal[["grey"]]) +
  geom_point(alpha = 0.25, size = 1, colour = pal[["ink"]]) +
  coord_equal() +
  labs(title = "Robbery Score with xgboost vs. glmnet round models",
       subtitle = sprintf("Spearman correlation %.3f; %d of the top 25 are the same.",
                          cor(sens$robbery_score, sens$score_glmnet, method = "spearman"),
                          length(intersect(top_x, top_g))),
       x = "Robbery Score (xgboost, final)", y = "Robbery Score (glmnet)", caption = SOURCE_CAPTION) +
  theme_robbery()
save_fig(p4, "p4_sensitivity_glmnet", width = 6, height = 6)

cat("\nFigures written to figures/\n")
