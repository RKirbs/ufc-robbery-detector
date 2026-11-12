# phase5_report.R: tables and figures for the Phase 5 checkpoint (validation,
# judges, 2017 criteria). Reads built targets only.

suppressPackageStartupMessages({
  library(targets); library(dplyr); library(tidyr); library(ggplot2); library(purrr)
})
source("R/utils.R"); source("R/06_round_model.R"); source("R/07_simulate.R"); source("R/08_validation_judges.R")
tar_load(c(robbery_index, media_valid, media_disagree, round_agree, face_valid, judge_agree, judge_tend,
           corner, recency, criteria_era, criteria_era_no2017, ten_eight_era, robbery_time))
hr <- \(x) cat("\n==== ", x, " ====\n", sep = "")
options(width = 250, pillar.sigfig = 3)
era_cols <- c(`Before 2017` = "#2a78d6", `2017-2026` = "#eb6834")

hr("7.1 Media validation")
print(media_valid)
show_dis <- \(d) d |> transmute(date, winner = winner_name, loser = loser_name, decision_type,
                                score = round(robbery_score, 3), media_loser = sprintf("%d/%d", media_for_loser, media_scored))
cat("\nStats favour the loser, media sided with the winner:\n"); print(show_dis(media_disagree$model_not_media))
cat("\nMedia favoured the loser, stats backed the winner:\n"); print(show_dis(media_disagree$media_not_model))

hr("7.2 Round-level agreement")
print(round_agree)

hr("7.3 Face validity: widely debated decisions")
print(face_valid |> transmute(query, decision_type, score = round(robbery_score, 3), tier, rank,
                              top_pct = scales::percent(1 - pct_rank, 0.1),
                              media_loser = scales::percent(media_loser_share, 1), media_scored))

hr("8.1 Judge agreement with the model (adjusted for closeness; shrunk)")
ja <- judge_agree |> filter(eligible)
cat(nrow(ja), "judges with >=", MIN_JUDGE_ROUNDS, "rounds. League-average agreement on a 75/25 round:",
    round(ja$league_adj_agree[1], 3), "| range", round(min(ja$adj_agree), 3), "-", round(max(ja$adj_agree), 3),
    "| intervals excluding the average:", sum(ja$adj_lo > ja$league_adj_agree[1] | ja$adj_hi < ja$league_adj_agree[1]), "\n")
print(ja |> select(judge, rounds, raw_agree, expected_agree, adj_agree, adj_lo, adj_hi), n = 60)

hr("8.2 Judge tendencies: grappling vs striking emphasis")
jt <- judge_tend |> filter(eligible) |> arrange(desc(grap_emphasis))
cat("Intervals excluding 1:", sum(jt$grap_lo > 1 | jt$grap_hi < 1), "of", nrow(jt), "\n")
print(jt |> select(judge, rounds, strike_w, grap_w, grap_emphasis, grap_lo, grap_hi), n = 60)

hr("8.3 Corner, title, record, recency")
print(corner$simple); print(corner$full); print(corner$by_era)
cat("Judge-level SD of red-corner lean (log-odds):", round(corner$re_sd, 3), "\n")
cj <- corner$judges |> filter(eligible)
cat("Judges whose lean interval excludes the league average:", sum(abs(cj$re) > 1.96 * cj$re_se), "of", nrow(cj), "\n")
pp <- \(b) 100 * (plogis(b) - 0.5)
cat(sprintf("Red-corner shift on a toss-up round: %.1f pts (simple), %.1f pts (with controls)\n",
            pp(corner$simple$est[1]), pp(corner$full$est[1])))
print(recency)

hr("9.1 Era interactions in the round model")
cat(sprintf("Joint Wald test (13 interactions): chi2 = %.1f, p = %.4f; without 2017: p = %.4f\n",
            criteria_era$wald_chi2, criteria_era$wald_p, criteria_era_no2017$wald_p))
print(criteria_era$interactions)
print(criteria_era$rates |> select(feature, era, head_equiv, lo, hi) |>
        pivot_wider(names_from = era, values_from = c(head_equiv, lo, hi)))

hr("9.2 10-8 rate")
print(ten_eight_era[-1] |> as_tibble())
print(ten_eight_era$by_year, n = 30)

hr("9.3 Robbery rate over time")
print(robbery_time$pre_post)
cat("OR robbery tier, 2017+ vs 2011-16:", round(robbery_time$or_robbery, 2),
    "| OR questionable-or-worse:", round(robbery_time$or_q_or_worse, 2), "\n")

# ---- Figures --------------------------------------------------------------------

ri <- robbery_index |> filter(winner != "draw", coalesce(media_scored, 0L) >= MIN_MEDIA)
lab <- bind_rows(head(media_disagree$model_not_media, 4), head(media_disagree$media_not_model, 4),
                 robbery_index |> filter(winner != "draw") |> slice_max(robbery_score, n = 3)) |>
  distinct(fight_url, .keep_all = TRUE) |>
  mutate(label = paste0(surname_of(winner_name), " def. ", surname_of(loser_name), " (", format(date, "%Y"), ")"))
p1 <- ggplot(ri, aes(robbery_score, media_loser_share)) +
  geom_point(aes(size = media_scored), alpha = 0.18, colour = pal[["ink"]], stroke = 0) +
  geom_smooth(method = "loess", formula = y ~ x, se = TRUE, colour = pal[["red"]], fill = pal[["red"]], alpha = 0.15) +
  ggrepel::geom_text_repel(data = filter(lab, coalesce(media_scored, 0L) >= MIN_MEDIA), aes(label = label),
                           size = 2.8, min.segment.length = 0, box.padding = 0.5, colour = pal[["ink"]]) +
  scale_size_area(max_size = 4, name = "Media scores") +
  scale_x_continuous(breaks = seq(0, 1, 0.25)) +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "The Robbery Score tracks what the media saw",
       subtitle = sprintf("Each dot is a decision with >= %d media scorecards (n = %s). Pearson r = %.2f (95%% CI %.2f-%.2f).",
                          MIN_MEDIA, format(media_valid$n_fights, big.mark = ","), media_valid$pearson,
                          media_valid$pearson_lo, media_valid$pearson_hi),
       x = "Robbery Score (model)", y = "Media scorecards favouring the official loser", caption = SOURCE_CAPTION) +
  theme_robbery()
save_fig(p1, "p5_media_scatter", width = 9, height = 6)

# Judge agreement caterpillar.
f2 <- ja |> mutate(judge = forcats::fct_reorder(paste0(judge, " (", scales::comma(rounds), ")"), adj_agree))
p2 <- ggplot(f2, aes(adj_agree, judge)) +
  geom_vline(xintercept = ja$league_adj_agree[1], colour = pal[["grey"]], linetype = "dashed") +
  geom_errorbar(aes(xmin = adj_lo, xmax = adj_hi), width = 0, orientation = "y", colour = pal[["grey"]], linewidth = 0.7) +
  geom_point(size = 2.2, colour = pal[["ink"]]) +
  scale_x_continuous(labels = scales::percent_format(1)) +
  labs(title = "Judges agree with the stats model at very similar rates",
       subtitle = paste0("Agreement on a typical round (model favours one fighter 75/25), adjusted for how close each judge's\n",
                         "rounds were and shrunk toward the average. Judges with >= 100 rounds (count in brackets). Bars: 95% intervals."),
       x = "Adjusted agreement with the model's round winner", y = NULL, caption = SOURCE_CAPTION) +
  theme_robbery(base_size = 10)
save_fig(p2, "p5_judge_agreement", width = 8.5, height = 10)

# Grappling emphasis caterpillar.
f3 <- jt |> mutate(judge = forcats::fct_reorder(paste0(judge, " (", scales::comma(rounds), ")"), grap_emphasis))
p3 <- ggplot(f3, aes(grap_emphasis, judge)) +
  geom_vline(xintercept = 1, colour = pal[["grey"]], linetype = "dashed") +
  geom_errorbar(aes(xmin = grap_lo, xmax = grap_hi), width = 0, orientation = "y", colour = pal[["grey"]], linewidth = 0.7) +
  geom_point(size = 2.2, colour = pal[["ink"]]) +
  annotate("text", x = c(0.62, 1.38), y = 1, label = c("<- weights striking more", "weights grappling more ->"),
           size = 3, colour = pal[["grey"]], vjust = -0.5) +
  labs(title = "Some judges lean toward grappling, others toward striking",
       subtitle = paste0("Each judge's weight on grappling (takedowns, control, submissions) relative to striking,\n",
                         "vs. the league average (= 1). Mixed model with judge random slopes; judges with >= 100 rounds."),
       x = "Relative grappling emphasis", y = NULL, caption = SOURCE_CAPTION) +
  theme_robbery(base_size = 10)
save_fig(p3, "p5_judge_grappling", width = 8.5, height = 10)

# Corner / title effects in percentage points on a toss-up round.
ce <- bind_rows(
  corner$simple |> filter(term == "(Intercept)") |> mutate(what = "Red corner, stats only"),
  corner$full |> filter(term == "(Intercept)") |> mutate(what = "Red corner, + experience & record"),
  corner$by_era |> filter(term == "(Intercept)") |> mutate(what = paste0("Red corner, ", era)),
  corner$full |> filter(term == "title_fightTRUE") |> mutate(what = "Extra red-corner lean in title fights")
) |> mutate(pt = pp(est), lo = pp(est - 1.96 * se), hi = pp(est + 1.96 * se),
            what = factor(what, rev(unique(what))))
p4 <- ggplot(ce, aes(pt, what)) +
  geom_vline(xintercept = 0, colour = pal[["grey"]]) +
  geom_errorbar(aes(xmin = lo, xmax = hi), width = 0, orientation = "y", colour = pal[["red"]], linewidth = 0.9) +
  geom_point(size = 3, colour = pal[["red"]]) +
  geom_text(aes(label = sprintf("%+.1f", pt)), vjust = -0.9, size = 3, colour = pal[["ink"]]) +
  labs(title = "Judges give the red corner a small edge the stats don't explain",
       subtitle = "Extra chance (percentage points) that a judge gives a statistically even round to the red corner.\n95% CIs clustered by fight (mixed model for the controlled estimate).",
       x = "Percentage points on a 50/50 round", y = NULL, caption = SOURCE_CAPTION) +
  theme_robbery()
save_fig(p4, "p5_red_corner", width = 9, height = 4.8)

# What judges reward, before vs after 2017.
f5 <- criteria_era$rates |> filter(feature != "d_head_l") |>
  mutate(sc = if_else(feature == "d_sig_acc", 0.1, 1), across(c(head_equiv, lo, hi), \(x) x * sc),
         label = if_else(feature == "d_sig_acc", "Sig. strike accuracy (+10 pts)", FEATURE_LABELS[feature]),
         era = factor(era, c("Before 2017", "2017-2026"))) |>
  group_by(feature) |> mutate(ord = mean(head_equiv)) |> ungroup() |>
  mutate(label = forcats::fct_reorder(label, ord))
p5 <- ggplot(f5, aes(head_equiv, label, colour = era)) +
  geom_vline(xintercept = 0, colour = pal[["grey"]]) +
  geom_errorbar(aes(xmin = lo, xmax = hi), width = 0, orientation = "y", linewidth = 0.8,
                position = position_dodge(width = 0.6)) +
  geom_point(size = 2.6, position = position_dodge(width = 0.6)) +
  scale_colour_manual(values = era_cols, name = NULL) +
  labs(title = "After 2017, knockdowns count for more and takedowns for less",
       subtitle = sprintf("Value of each edge in significant head strikes, before vs. after the 2017 criteria update.\nJoint test that nothing changed: p = %.4f.",
                          criteria_era$wald_p),
       x = "Equivalent significant head strikes", y = NULL, caption = SOURCE_CAPTION) +
  theme_robbery()
save_fig(p5, "p5_criteria_weights", width = 9, height = 6.5)

# 10-8 rate by year.
f6 <- ten_eight_era$by_year |> filter(rounds >= 100)
p6 <- ggplot(f6, aes(year, rate)) +
  geom_vline(xintercept = 2016.5, colour = pal[["grey"]], linetype = "dashed") +
  annotate("text", x = 2016.6, y = max(f6$rate) * 1.05, label = "2017 criteria", hjust = 0, size = 3, colour = pal[["grey"]]) +
  geom_line(colour = pal[["red"]], linewidth = 0.9) + geom_point(colour = pal[["red"]], size = 2.2) +
  scale_y_continuous(labels = scales::percent_format(0.1), limits = c(0, NA)) +
  labs(title = "10-8 rounds jumped after the 2017 update, then faded",
       subtitle = "Share of judge-round scores that were 10-8 or wider (years with >= 100 judge-rounds).",
       x = NULL, y = "10-8 share", caption = SOURCE_CAPTION) +
  theme_robbery()
save_fig(p6, "p5_ten_eight_by_year", width = 9, height = 5)

# Robbery rate by year.
f7 <- robbery_time$by_year |> filter(year >= 2006) |>
  select(year, decisions, `Robbery tier` = robbery, `Questionable or Robbery` = questionable_or_worse) |>
  pivot_longer(-c(year, decisions), names_to = "series", values_to = "share")
p7 <- ggplot(f7, aes(year, share, colour = series, shape = series)) +
  geom_vline(xintercept = 2016.5, colour = pal[["grey"]], linetype = "dashed") +
  annotate("text", x = 2016.6, y = max(f7$share) * 1.05, label = "2017 criteria", hjust = 0, size = 3, colour = pal[["grey"]]) +
  geom_line(linewidth = 0.9) + geom_point(size = 2.2) +
  scale_colour_manual(values = c(`Robbery tier` = "#8E0C22", `Questionable or Robbery` = "#E08494"), name = NULL) +
  scale_shape_manual(values = c(`Robbery tier` = 16, `Questionable or Robbery` = 17), name = NULL) +
  scale_y_continuous(labels = scales::percent_format(1), limits = c(0, NA)) +
  labs(title = "No clear change in robbery rates after 2017",
       subtitle = "Share of decisions in each tier by year, 2006-2026.",
       x = NULL, y = "Share of decisions", caption = SOURCE_CAPTION) +
  theme_robbery()
save_fig(p7, "p5_robbery_by_year", width = 9, height = 5)

cat("\nFigures written to figures/\n")
