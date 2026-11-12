# phase6_report.R: betting-market extension results. Reads built targets only.

suppressPackageStartupMessages({
  library(targets); library(dplyr); library(tidyr); library(ggplot2); library(purrr)
})
source("R/utils.R")
tar_load(c(bfo_raw, bfo_m, odds, odds_cov, fav_effects, decision_risk, robbery_market, corner, red_market))
hr <- \(x) cat("\n==== ", x, " ====\n", sep = "")
options(width = 220, pillar.sigfig = 3)
pp <- \(b) 100 * (plogis(b) - 0.5)

hr("1. Collection and linkage")
cat("Fighter pages parsed:", n_distinct(bfo_raw$page), "| matchup rows:", nrow(bfo_raw), "| unique matchups:", nrow(bfo_m), "\n")
cat("UFC decisions since 2007 with odds:", odds_cov$decisions[["with_odds"]], "of", odds_cov$decisions[["n"]],
    sprintf("(%.1f%%)", 100 * odds_cov$decisions[["with_odds"]] / odds_cov$decisions[["n"]]), "\n")
cat("All UFC fights since 2007 with odds:", odds_cov$all_fights[["with_odds"]], "of", odds_cov$all_fights[["n"]], "\n")
print(odds_cov$by_year, n = 30)
cat("Overround (vig) summary:\n"); print(summary(odds$overround))
cat("Link similarity summary:\n"); print(summary(odds$link_sim))
cat("\nMarket sanity check: favourites win about as often as priced?\n"); print(odds_cov$favourite_check)

hr("1b. Does the red corner beat its closing odds? (corner-known fights)")
print(red_market[c("n", "red_win", "red_mkt")]); print(red_market$coefs); print(red_market$by_side)

hr("2. Judges and the betting favourite (round level)")
cat("Judge-rounds:", fav_effects$n_rows, "| fights:", fav_effects$n_fights,
    "| share of fights where the red corner was the favourite:", round(fav_effects$red_fav_share, 3), "\n")
for (nm in c("corner_only", "with_market", "close_rounds", "full")) { cat("\n--", nm, "\n"); print(fav_effects[[nm]]) }
wm <- fav_effects$with_market
cat(sprintf("\nRed-corner shift on a 50/50 round: %.1f pts without market, %.1f pts with market control\n",
            pp(fav_effects$corner_only$est[1]), pp(wm$est[1])))
b <- wm$est[wm$term == "mkt_logit"]; s <- wm$se[wm$term == "mkt_logit"]
fav_pp <- \(b) 100 * (plogis(b * qlogis(0.75)) - 0.5)
cat(sprintf("Favourite at 75%% (-300) vs. even: judge lean on a 50/50 round = %.1f pts (95%% CI %.1f to %.1f)\n",
            fav_pp(b), fav_pp(b - 1.96 * s), fav_pp(b + 1.96 * s)))

hr("3. Does the market price decision risk?")
print(decision_risk)

hr("4. Robbery tier vs. the market")
print(robbery_market)

# ---- Figures ---------------------------------------------------------------------
f1 <- bind_rows(
  fav_effects$corner_only |> filter(term == "(Intercept)") |> mutate(what = "Red corner (same fights, no market control)"),
  fav_effects$with_market |> filter(term == "(Intercept)") |> mutate(what = "Red corner, controlling for the betting line"),
  fav_effects$with_market |> filter(term == "mkt_logit") |> mutate(what = "Favourite at -300 vs. even fight", est = est * qlogis(0.75), se = se * qlogis(0.75)),
  fav_effects$close_rounds |> filter(term == "mkt_logit") |> mutate(what = "Favourite at -300, close rounds only", est = est * qlogis(0.75), se = se * qlogis(0.75))
) |> mutate(pt = pp(est), lo = pp(est - 1.96 * se), hi = pp(est + 1.96 * se), what = factor(what, rev(what)))
p1 <- ggplot(f1, aes(pt, what)) +
  geom_vline(xintercept = 0, colour = pal[["grey"]]) +
  geom_errorbar(aes(xmin = lo, xmax = hi), width = 0, orientation = "y", colour = pal[["blue"]], linewidth = 0.9) +
  geom_point(size = 3, colour = pal[["blue"]]) +
  geom_text(aes(label = sprintf("%+.1f", pt)), vjust = -0.9, size = 3, colour = pal[["ink"]]) +
  labs(title = "Do judges lean toward the betting favourite?",
       subtitle = "Extra chance (percentage points) a judge gives a statistically even round to that fighter.\nMixed models with judge random intercepts; 95% intervals.",
       x = "Percentage points on a 50/50 round", y = NULL, caption = paste0(SOURCE_CAPTION, "; odds: BestFightOdds")) +
  theme_robbery()
save_fig(p1, "p6_favourite_effect", width = 9, height = 4.5)

f2 <- odds_cov$favourite_check
p2 <- ggplot(f2, aes(market, observed)) +
  geom_abline(linetype = "dashed", colour = pal[["grey"]]) +
  geom_point(aes(size = n), shape = 21, fill = "white", colour = pal[["ink"]], stroke = 1) +
  scale_x_continuous(labels = scales::percent, limits = c(0.5, 1)) +
  scale_y_continuous(labels = scales::percent, limits = c(0.5, 1)) +
  scale_size_area(max_size = 6, name = "Fights") +
  coord_equal() +
  labs(title = "Closing lines are well calibrated",
       subtitle = "De-vigged closing probability of the favourite vs. how often the favourite won (all UFC fights with odds).",
       x = "Market probability", y = "Observed win rate", caption = paste0(SOURCE_CAPTION, "; odds: BestFightOdds")) +
  theme_robbery()
save_fig(p2, "p6_market_calibration", width = 6.5, height = 6.5)
cat("\nFigures written to figures/\n")
