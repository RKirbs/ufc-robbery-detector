# 11_site_plots.R: chart functions for the Quarto site. Each takes the small
# tables in data/final/ (never the targets store) and returns a ggplot. Titles
# and subtitles state the takeaway; numbers in them are computed from the data.

suppressPackageStartupMessages({ library(ggplot2); library(dplyr); library(tidyr); library(patchwork) })

# Roles used on fight-level charts: the robbed fighter is the emphasis colour.
role_cols <- c(`Official winner` = "#6B7280", `Official loser` = "#C8102E")
model_cols_pal <- c(baseline = "#8A8F98", logistic = "#2a78d6", glmnet = "#eb6834", xgboost = "#1baf7a")
model_short <- c(baseline = "Baseline (sig. strike leader)", logistic = "Logistic", glmnet = "glmnet", xgboost = "xgboost")
tier_cols <- c(Clean = "#F2C4CB", `Close / defensible` = "#E08494", Questionable = "#C8445A", Robbery = "#8E0C22")
era_cols <- c(`Before 2017` = "#2a78d6", `2017-2026` = "#eb6834")
surname_of <- function(x) sub(".* ", "", x)
fmt_pct <- function(x, acc = 1) scales::percent(x, accuracy = acc)

# ---- Signature chart: round-by-round breakdown of one fight ---------------------

plot_fight_breakdown <- function(fight, rounds, judges) {
  W <- surname_of(fight$winner_name); L <- surname_of(fight$loser_name)
  r <- rounds |> arrange(round)
  long <- bind_rows(
    r |> transmute(round, role = "Official winner", sig = sig_w, ctrl = ctrl_w / 60, kd = kd_w, td = td_w),
    r |> transmute(round, role = "Official loser", sig = sig_l, ctrl = ctrl_l / 60, kd = kd_l, td = td_l)
  ) |> mutate(role = factor(role, names(role_cols)), round = factor(round))
  dodge <- position_dodge(width = 0.7)
  notes <- long |> filter(kd > 0 | td > 0) |>
    mutate(lab = trimws(paste0(ifelse(kd > 0, paste0(kd, " KD "), ""), ifelse(td > 0, paste0(td, " TD"), ""))))
  pa <- ggplot(long, aes(round, sig, fill = role)) +
    geom_col(position = dodge, width = 0.65) +
    geom_text(aes(label = sig, group = role), position = dodge, vjust = -0.4, size = 3, colour = pal[["ink"]]) +
    # Place KD/TD notes under the right bar even when only one fighter has one.
    geom_text(data = mutate(notes, x = as.numeric(round) + if_else(role == "Official winner", -0.175, 0.175)),
              aes(x = x, y = 0, label = lab), inherit.aes = FALSE, vjust = 1.4, size = 2.6, colour = pal[["ink"]]) +
    scale_fill_manual(values = role_cols, labels = c(paste("Official winner:", W), paste("Official loser:", L)), name = NULL) +
    scale_y_continuous(expand = expansion(mult = c(0.12, 0.15))) +
    labs(x = NULL, y = "Sig. strikes landed") +
    theme_robbery() + theme(legend.position = "top")
  pb <- ggplot(long, aes(round, ctrl, fill = role)) +
    geom_col(position = dodge, width = 0.65, show.legend = FALSE) +
    scale_fill_manual(values = role_cols) +
    labs(x = NULL, y = "Control (min)") +
    theme_robbery()
  # Who got each round: three judges plus the model.
  jt <- judges |>
    mutate(who = if_else(score_w > score_l, "Official winner", if_else(score_l > score_w, "Official loser", "Even")),
           lab = paste0(score_w, "-", score_l), row = surname_of(judge)) |>
    select(round, row, who, lab, judge_order)
  mt <- r |> transmute(round, row = "Model", who = if_else(p_loser_round > 0.5, "Official loser", "Official winner"),
                       lab = paste0(round(100 * p_loser_round), "% ", L), judge_order = 99)
  tiles <- bind_rows(jt, mt) |>
    mutate(row = factor(row, rev(unique(row[order(judge_order)]))), round = factor(round))
  pc <- ggplot(tiles, aes(round, row, fill = who)) +
    geom_tile(colour = "white", linewidth = 1.2, alpha = 0.85) +
    geom_text(aes(label = lab), size = 3, colour = "white", fontface = "bold") +
    scale_fill_manual(values = c(role_cols, Even = "#B0B4BA"), guide = "none") +
    labs(x = "Round", y = NULL) +
    theme_robbery() + theme(panel.grid = element_blank())
  (pa / pb / pc) + plot_layout(heights = c(3, 1.6, 2.2)) +
    plot_annotation(
      title = paste0(W, " def. ", L, " (", format(fight$date, "%b %d, %Y"), ")"),
      subtitle = paste0(fight$event, " · ", fight$decision_type, " decision · Robbery Score ",
                        sprintf("%.3f", fight$robbery_score),
                        if (!is.na(fight$media_scored) && fight$media_scored > 0)
                          paste0(" · media for ", L, ": ", fight$media_for_loser, " of ", fight$media_scored) else "",
                        "\nTop: stats per round. Bottom: who each judge gave each round (official scores) and the model's chance ",
                        L, " won it."),
      caption = SOURCE_CAPTION,
      theme = theme_robbery())
}

# ---- Robbery Index ---------------------------------------------------------------------

plot_robbery_distribution <- function(ri) {
  d <- ri |> filter(winner != "draw") |> mutate(tier = factor(tier, names(tier_cols)))
  ggplot(d, aes(robbery_score, fill = tier)) +
    geom_histogram(breaks = seq(0, 1, 0.025), colour = "white", linewidth = 0.3) +
    geom_vline(xintercept = c(0.25, 0.5, 0.75), colour = pal[["ink"]], linetype = "dotted") +
    scale_fill_manual(values = tier_cols, name = NULL, drop = FALSE) +
    scale_y_continuous(labels = scales::comma) +
    labs(title = "Most decisions are clean; a long tail is not",
         subtitle = sprintf("Robbery Score for %s UFC decisions, %s-%s. %s are in the Robbery tier (score >= 0.75).",
                            scales::comma(nrow(d)), min(d$year), max(d$year), scales::comma(sum(d$tier == "Robbery"))),
         x = "Robbery Score = 1 - P(declared winner wins | fight stats)", y = "Decisions", caption = SOURCE_CAPTION) +
    theme_robbery()
}

plot_robbery_by_year <- function(by_year, criteria_year = 2017) {
  f <- by_year |> filter(year >= 2006) |>
    select(year, `Robbery tier` = robbery, `Questionable or Robbery` = questionable_or_worse) |>
    pivot_longer(-year, names_to = "series", values_to = "share")
  ggplot(f, aes(year, share, colour = series, shape = series)) +
    geom_vline(xintercept = criteria_year - 0.5, colour = pal[["grey"]], linetype = "dashed") +
    annotate("text", x = criteria_year - 0.4, y = max(f$share) * 1.06, label = "2017 criteria update",
             hjust = 0, size = 3, colour = pal[["grey"]]) +
    geom_line(linewidth = 0.9) + geom_point(size = 2.2) +
    scale_colour_manual(values = c(`Robbery tier` = "#8E0C22", `Questionable or Robbery` = "#E08494"), name = NULL) +
    scale_shape_manual(values = c(`Robbery tier` = 16, `Questionable or Robbery` = 17), name = NULL) +
    scale_y_continuous(labels = scales::percent_format(1), limits = c(0, NA)) +
    labs(title = "Robbery rates have no clear trend",
         subtitle = "Share of decisions in each tier by year, 2006 onward.",
         x = NULL, y = "Share of decisions", caption = SOURCE_CAPTION) +
    theme_robbery()
}

# ---- Round model -------------------------------------------------------------------------

plot_what_judges_reward <- function(le) {
  f <- le |> filter(feature != "d_head_l") |>
    mutate(sc = if_else(feature == "d_sig_acc", 0.1, 1),
           across(c(head_equiv, head_equiv_lo, head_equiv_hi), \(x) x * sc),
           label = if_else(feature == "d_sig_acc", "Sig. strike accuracy (+10 pts)", label),
           label = paste0(label, if_else(feature %in% c("d_kd", "d_td_l", "d_sub_att", "d_rev"), " (each)", "")),
           clear = head_equiv_lo > 0 | head_equiv_hi < 0,
           label = forcats::fct_reorder(label, head_equiv))
  kd <- f$head_equiv[f$feature == "d_kd"]
  ggplot(f, aes(head_equiv, label, colour = clear)) +
    geom_vline(xintercept = 0, colour = pal[["grey"]]) +
    geom_vline(xintercept = 1, colour = pal[["grey"]], linetype = "dotted") +
    geom_errorbar(aes(xmin = head_equiv_lo, xmax = head_equiv_hi), width = 0, linewidth = 0.8, orientation = "y") +
    geom_point(size = 3) +
    geom_text(aes(label = sprintf("%.1f", head_equiv)), vjust = -0.9, size = 3, colour = pal[["ink"]]) +
    scale_colour_manual(values = c(`TRUE` = pal[["ink"]], `FALSE` = pal[["grey"]]),
                        labels = c(`TRUE` = "Clearly different from zero", `FALSE` = "Interval includes zero"), name = NULL) +
    labs(title = sprintf("A knockdown is worth about %.0f significant head strikes to judges", kd),
         subtitle = paste0("How many extra significant head strikes the same edge is worth on a judge's card (dotted line = 1).\n",
                           "Logistic model on ", scales::comma(le$n_rows[1]), " judge-round scores; 95% CIs clustered by fight."),
         x = "Equivalent significant head strikes", y = NULL, caption = SOURCE_CAPTION) +
    theme_robbery()
}

plot_model_comparison <- function(mt) {
  f <- mt |>
    transmute(model, `Log-loss (lower is better)` = log_loss, ll_lo = log_loss_lo, ll_hi = log_loss_hi,
              `Brier score (lower is better)` = brier, b_lo = brier_lo, b_hi = brier_hi,
              `Accuracy (higher is better)` = accuracy, a_lo = accuracy_lo, a_hi = accuracy_hi) |>
    pivot_longer(c(`Log-loss (lower is better)`, `Brier score (lower is better)`, `Accuracy (higher is better)`),
                 names_to = "metric", values_to = "value") |>
    mutate(lo = case_when(startsWith(metric, "Log") ~ ll_lo, startsWith(metric, "Brier") ~ b_lo, TRUE ~ a_lo),
           hi = case_when(startsWith(metric, "Log") ~ ll_hi, startsWith(metric, "Brier") ~ b_hi, TRUE ~ a_hi),
           model = factor(model, rev(names(model_short))),
           metric = factor(metric, unique(metric)))
  ggplot(f, aes(value, model, colour = model)) +
    geom_errorbar(aes(xmin = lo, xmax = hi), width = 0, linewidth = 0.8, orientation = "y") +
    geom_point(size = 3) +
    geom_text(aes(label = sprintf("%.3f", value)), vjust = -1, size = 3, colour = pal[["ink"]]) +
    facet_wrap(~metric, scales = "free_x") +
    scale_x_continuous(n.breaks = 4, expand = expansion(mult = 0.12)) +
    scale_colour_manual(values = model_cols_pal, guide = "none") +
    scale_y_discrete(labels = model_short) +
    labs(title = "All three models beat the naive baseline",
         subtitle = sprintf("Held-out judge-round scores, 2020-2026 (n = %s). Bars: 95%% bootstrap CIs over fights.",
                            scales::comma(mt$n[1])),
         x = NULL, y = NULL, caption = SOURCE_CAPTION) +
    theme_robbery() + theme(panel.spacing.x = unit(2, "lines"))
}

plot_round_calibration <- function(cal) {
  cal |>
    mutate(model = factor(model, names(model_short), labels = model_short)) |>
    ggplot(aes(pred, obs)) +
    geom_abline(linetype = "dashed", colour = pal[["grey"]]) +
    geom_linerange(aes(ymin = lo, ymax = hi), colour = pal[["ink"]], linewidth = 0.5) +
    geom_point(aes(size = n), colour = pal[["ink"]], fill = "white", shape = 21, stroke = 1) +
    facet_wrap(~model, nrow = 1) +
    scale_size_area(max_size = 5, labels = scales::comma, name = "Judge-rounds") +
    scale_x_continuous(labels = scales::percent, limits = c(0, 1)) +
    scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
    coord_equal() +
    labs(title = "Calibration: the boosted model tracks the diagonal most closely",
         subtitle = "Held-out rounds, 10 bins of predicted probability. Dashed line = perfect calibration.",
         x = "Predicted probability", y = "Observed share", caption = SOURCE_CAPTION) +
    theme_robbery()
}

plot_shap_dependence <- function(sd) {
  lab <- c(d_head_l = "Sig. head strikes", d_ctrl_min = "Control time (min)", d_body_l = "Sig. body strikes",
           d_leg_l = "Sig. leg strikes", d_td_l = "Takedowns", d_kd = "Knockdowns")
  sd |> mutate(feature = factor(feature, unique(feature), labels = coalesce(lab[unique(feature)], unique(feature)))) |>
    ggplot(aes(value, shap)) +
    geom_hline(yintercept = 0, colour = pal[["grey"]]) +
    geom_point(alpha = 0.15, size = 1, colour = model_cols_pal[["xgboost"]]) +
    facet_wrap(~feature, scales = "free_x") +
    labs(title = "Diminishing returns: a big strike lead stops adding value",
         subtitle = "Boosted model, each dot a judge-round. x: A-minus-B differential; y: push toward fighter A (log-odds).",
         x = "Differential (A minus B)", y = "SHAP (log-odds)", caption = SOURCE_CAPTION) +
    theme_robbery()
}

# ---- Simulation ----------------------------------------------------------------------------

plot_judge_split <- function(js, rho, rho_lo, rho_hi) {
  f <- js |> pivot_longer(c(observed, correlated, independent), names_to = "series", values_to = "split") |>
    mutate(series = factor(series, c("observed", "correlated", "independent"),
                           c("Observed", "Model, correlated judges", "Model, independent judges")),
           closeness = factor(closeness, unique(js$closeness)))
  ggplot(f, aes(closeness, split, colour = series, group = series, shape = series)) +
    geom_line(linewidth = 0.9) + geom_point(size = 2.8) +
    scale_colour_manual(values = c("#1B1F24", "#2a78d6", "#8A8F98"), name = NULL) +
    scale_shape_manual(values = c(16, 17, 15), name = NULL) +
    scale_y_continuous(labels = scales::percent) +
    labs(title = "Judges agree more than independent coin flips would",
         subtitle = sprintf("Share of rounds where the three judges split, by how lopsided the round was.\nEstimated latent judge correlation = %.2f (95%% CI %.2f-%.2f).",
                            rho, rho_lo, rho_hi),
         x = "Model probability of the round's underdog (0 = one-sided, 0.5 = toss-up)", y = "Rounds with a split",
         caption = SOURCE_CAPTION) +
    theme_robbery()
}

plot_fight_calibration <- function(fc) {
  ggplot(fc, aes(pred, obs)) +
    geom_abline(linetype = "dashed", colour = pal[["grey"]]) +
    geom_point(aes(size = n), shape = 21, fill = "white", colour = pal[["ink"]], stroke = 1) +
    scale_size_area(max_size = 6, name = "Decisions") +
    scale_x_continuous(labels = scales::percent, limits = c(0, 1)) +
    scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
    coord_equal() +
    labs(title = "Fight-level calibration",
         subtitle = "Simulated P(red corner wins) vs. how often the red corner won\n(fights from March 2010, when UFCStats lists the red corner first).",
         x = "Simulated probability", y = "Observed share", caption = SOURCE_CAPTION) +
    theme_robbery()
}

# ---- Validation ----------------------------------------------------------------------------

plot_media_scatter <- function(ri, md, r, lo, hi, min_media = 5) {
  d <- ri |> filter(winner != "draw", coalesce(media_scored, 0) >= min_media)
  lab <- md |> group_by(type) |> slice_head(n = 4) |> ungroup() |>
    inner_join(d |> select(winner_name, loser_name, date, media_loser_share), by = c("winner_name", "loser_name", "date")) |>
    mutate(label = paste0(surname_of(winner_name), " def. ", surname_of(loser_name), " (", format(date, "%Y"), ")"))
  ggplot(d, aes(robbery_score, media_loser_share)) +
    geom_point(aes(size = media_scored), alpha = 0.18, colour = pal[["ink"]], stroke = 0) +
    geom_smooth(method = "loess", formula = y ~ x, se = TRUE, colour = pal[["red"]], fill = pal[["red"]], alpha = 0.15) +
    ggrepel::geom_text_repel(data = lab, aes(label = label), size = 2.8, min.segment.length = 0,
                             box.padding = 0.5, colour = pal[["ink"]]) +
    scale_size_area(max_size = 4, name = "Media scores") +
    scale_y_continuous(labels = scales::percent) +
    labs(title = "The Robbery Score tracks what the media saw",
         subtitle = sprintf("Decisions with >= %d media scorecards (n = %s). Pearson r = %.2f (95%% CI %.2f-%.2f).",
                            min_media, scales::comma(nrow(d)), r, lo, hi),
         x = "Robbery Score (model)", y = "Media scorecards favouring the official loser", caption = SOURCE_CAPTION) +
    theme_robbery()
}

# ---- Judges --------------------------------------------------------------------------------

plot_judge_agreement <- function(ja, min_rounds = 100) {
  f <- ja |> filter(rounds >= min_rounds) |>
    mutate(judge = forcats::fct_reorder(paste0(judge, " (", scales::comma(rounds), ")"), adj_agree))
  ggplot(f, aes(adj_agree, judge)) +
    geom_vline(xintercept = f$league_adj_agree[1], colour = pal[["grey"]], linetype = "dashed") +
    geom_errorbar(aes(xmin = adj_lo, xmax = adj_hi), width = 0, orientation = "y", colour = pal[["grey"]], linewidth = 0.7) +
    geom_point(size = 2.2, colour = pal[["ink"]]) +
    scale_x_continuous(labels = scales::percent_format(1)) +
    labs(title = "Judges agree with the stats at very similar rates",
         subtitle = paste0("Agreement on a typical 75/25 round, adjusted for how close each judge's rounds were and\n",
                           "shrunk toward the average (dashed). Judges with >= ", min_rounds, " rounds; 95% intervals."),
         x = "Adjusted agreement with the model's round winner", y = NULL, caption = SOURCE_CAPTION) +
    theme_robbery(base_size = 10)
}

plot_grappling <- function(jt, min_rounds = 100) {
  f <- jt |> filter(rounds >= min_rounds) |>
    mutate(judge = forcats::fct_reorder(paste0(judge, " (", scales::comma(rounds), ")"), grap_emphasis))
  ggplot(f, aes(grap_emphasis, judge)) +
    geom_vline(xintercept = 1, colour = pal[["grey"]], linetype = "dashed") +
    geom_errorbar(aes(xmin = grap_lo, xmax = grap_hi), width = 0, orientation = "y", colour = pal[["grey"]], linewidth = 0.7) +
    geom_point(size = 2.2, colour = pal[["ink"]]) +
    labs(title = "Some judges lean toward grappling, others toward striking",
         subtitle = paste0("Each judge's weight on grappling (takedowns, control, submissions) relative to striking,\n",
                           "vs. the league average (= 1). Judges with >= ", min_rounds, " rounds; approximate 95% intervals."),
         x = "Relative grappling emphasis (1 = league average)", y = NULL, caption = SOURCE_CAPTION) +
    theme_robbery(base_size = 10)
}

plot_corner_favourite <- function(fav) {
  pp <- \(b) 100 * (plogis(b) - 0.5)
  k <- qlogis(0.75)
  f <- bind_rows(
    fav |> filter(model == "corner_only", term == "(Intercept)") |> mutate(what = "Red corner (no market control)"),
    fav |> filter(model == "with_market", term == "(Intercept)") |> mutate(what = "Red corner, controlling for the betting line"),
    fav |> filter(model == "with_market", term == "mkt_logit") |> mutate(what = "Betting favourite at -300 vs. an even fight", est = est * k, se = se * k),
    fav |> filter(model == "close_rounds", term == "mkt_logit") |> mutate(what = "Favourite at -300, close rounds only", est = est * k, se = se * k)
  ) |> mutate(pt = pp(est), lo = pp(est - 1.96 * se), hi = pp(est + 1.96 * se), what = factor(what, rev(what)))
  ggplot(f, aes(pt, what)) +
    geom_vline(xintercept = 0, colour = pal[["grey"]]) +
    geom_errorbar(aes(xmin = lo, xmax = hi), width = 0, orientation = "y", colour = pal[["blue"]], linewidth = 0.9) +
    geom_point(size = 3, colour = pal[["blue"]]) +
    geom_text(aes(label = sprintf("%+.1f", pt)), vjust = -0.9, size = 3, colour = pal[["ink"]]) +
    labs(title = "Judges lean slightly toward the red corner and the betting favourite",
         subtitle = "Extra chance (percentage points) a judge gives a statistically even round to that fighter.\nFights from March 2010 with closing odds; mixed models with judge random intercepts; 95% intervals.",
         x = "Percentage points on a 50/50 round", y = NULL, caption = paste0(SOURCE_CAPTION, "; odds: BestFightOdds")) +
    theme_robbery()
}

# ---- 2017 criteria ---------------------------------------------------------------------------

plot_criteria_weights <- function(rates, labels, wald_p) {
  f <- rates |> filter(feature != "d_head_l") |>
    mutate(sc = if_else(feature == "d_sig_acc", 0.1, 1), across(c(head_equiv, lo, hi), \(x) x * sc),
           label = if_else(feature == "d_sig_acc", "Sig. strike accuracy (+10 pts)", labels[feature]),
           era = factor(era, names(era_cols))) |>
    group_by(feature) |> mutate(ord = mean(head_equiv)) |> ungroup() |>
    mutate(label = forcats::fct_reorder(label, ord))
  ggplot(f, aes(head_equiv, label, colour = era)) +
    geom_vline(xintercept = 0, colour = pal[["grey"]]) +
    geom_errorbar(aes(xmin = lo, xmax = hi), width = 0, orientation = "y", linewidth = 0.8,
                  position = position_dodge(width = 0.6)) +
    geom_point(size = 2.6, position = position_dodge(width = 0.6)) +
    scale_colour_manual(values = era_cols, name = NULL) +
    labs(title = "After 2017, knockdowns count for more and takedowns for less",
         subtitle = sprintf("Value of each edge in significant head strikes, before vs. after the update. Joint test of no change: p = %s.",
                            format.pval(wald_p, digits = 2, eps = 1e-4)),
         x = "Equivalent significant head strikes", y = NULL, caption = SOURCE_CAPTION) +
    theme_robbery()
}

plot_ten_eight <- function(te) {
  f <- te |> filter(rounds >= 100)
  ggplot(f, aes(year, rate)) +
    geom_vline(xintercept = 2016.5, colour = pal[["grey"]], linetype = "dashed") +
    annotate("text", x = 2016.6, y = max(f$rate) * 1.06, label = "2017 criteria update", hjust = 0, size = 3, colour = pal[["grey"]]) +
    geom_line(colour = pal[["red"]], linewidth = 0.9) + geom_point(colour = pal[["red"]], size = 2.2) +
    scale_y_continuous(labels = scales::percent_format(0.1), limits = c(0, NA)) +
    labs(title = "10-8 rounds jumped after the update, then faded",
         subtitle = "Share of judge-round scores that were 10-8 or wider (years with >= 100 judge-rounds; deductions removed).",
         x = NULL, y = "10-8 share", caption = SOURCE_CAPTION) +
    theme_robbery()
}
