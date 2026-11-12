# phase3_report.R: tables and figures for the Phase 3 checkpoint (round model).
# Reads built targets only; run after targets::tar_make().

suppressPackageStartupMessages({
  library(targets); library(dplyr); library(tidyr); library(ggplot2); library(purrr)
})
source("R/utils.R")
source("R/06_round_model.R")
tar_load(c(model_data, train_rounds, test_rounds, cv_results, round_tuned, test_results,
           test_calibration, rolling_results, logit_effects, shap_xgb, ten_eight_cv_res,
           ten_eight_model, ten_eight_data))
hr <- \(x) cat("\n==== ", x, " ====\n", sep = "")
options(width = 200, pillar.sigfig = 4)

# Model colours: reference categorical slots 1-3 (validated all-pairs safe);
# the baseline is neutral grey and dashed, so it never relies on colour alone.
model_cols_pal <- c(baseline = pal[["grey"]], logistic = "#2a78d6",
                    glmnet = "#eb6834", xgboost = "#1baf7a")
model_order <- c("baseline", "logistic", "glmnet", "xgboost")
short_lab <- c(baseline = "Baseline (sig. strike leader)", logistic = "Logistic",
               glmnet = "glmnet", xgboost = "xgboost")

hr("1. Data")
print(count(model_data, drop_reason))
cat("Train (", format(min(train_rounds$date)), "to", format(max(train_rounds$date)), "):",
    nrow(train_rounds), "judge-rounds,", n_distinct(train_rounds$fight_url), "fights\n")
cat("Test  (", format(min(test_rounds$date)), "to", format(max(test_rounds$date)), "):",
    nrow(test_rounds), "judge-rounds,", n_distinct(test_rounds$fight_url), "fights\n")
cat("Share of judge-rounds won by A (unmirrored train):", round(mean(train_rounds$y == "a"), 3), "\n")

hr("2. Grouped 5-fold CV on training years (mirrored rows; folds grouped by fight)")
print(cv_results |> select(model, .metric, mean, std_err) |>
        pivot_wider(names_from = .metric, values_from = c(mean, std_err)) |>
        arrange(mean_mn_log_loss))
cat("\nBest glmnet:\n"); print(tune::select_best(round_tuned$glmnet, metric = "mn_log_loss"))
cat("Best xgboost:\n"); print(tune::select_best(round_tuned$xgboost, metric = "mn_log_loss"))

hr("3. Time-based test (trained on 2006-2019, tested on 2020-2026); 95% CIs bootstrap over fights")
print(test_results |> mutate(model = factor(model, model_order)) |> arrange(model) |>
        select(model, n, log_loss, log_loss_lo, log_loss_hi, brier, accuracy, accuracy_lo, accuracy_hi,
               ll_gain_lo, ll_gain_hi))

hr("4. Rolling origin: train on all years before Y, test on Y (log-loss)")
print(rolling_results |> select(model, year, log_loss) |>
        pivot_wider(names_from = model, values_from = log_loss))
print(rolling_results |> select(model, year, accuracy) |>
        pivot_wider(names_from = model, values_from = accuracy))

hr("5. Calibration (test set): max |observed - predicted| over bins with n >= 100")
print(test_calibration |> filter(n >= 100) |> group_by(model) |>
        summarise(max_gap = max(abs(obs - pred)), mean_gap = weighted.mean(abs(obs - pred), n)))

hr("6. What judges reward: logistic regression on all rounds (clustered SEs by fight)")
print(logit_effects |> select(label, beta, se, z, p_alone, head_equiv, head_equiv_lo, head_equiv_hi))
cat("Rows:", logit_effects$n_rows[1], "| fights:", logit_effects$n_fights[1], "\n")

hr("7. xgboost SHAP: mean |SHAP| (log-odds), sample of 4,000 judge-rounds")
shap_imp <- tibble(feature = colnames(shap_xgb$S), mean_abs = colMeans(abs(shap_xgb$S))) |>
  arrange(desc(mean_abs)) |> mutate(share = mean_abs / sum(mean_abs))
print(shap_imp)

hr("8. 10-8 model")
cat("10-8 (or wider) share of judge-rounds with a winner:", round(mean(ten_eight_data$ten_eight), 4), "\n")
print(ten_eight_data |> group_by(post_2017) |> summarise(rate = mean(ten_eight), n = n()))
print(ten_eight_cv_res)
print(broom::tidy(ten_eight_model))

# ---- Figures --------------------------------------------------------------------

# Fig 1: test-set metrics with bootstrap CIs.
f1 <- test_results |>
  transmute(model, `Log-loss (lower is better)` = log_loss, ll_lo = log_loss_lo, ll_hi = log_loss_hi,
            `Brier score (lower is better)` = brier, b_lo = brier_lo, b_hi = brier_hi,
            `Accuracy (higher is better)` = accuracy, a_lo = accuracy_lo, a_hi = accuracy_hi) |>
  pivot_longer(c(`Log-loss (lower is better)`, `Brier score (lower is better)`, `Accuracy (higher is better)`),
               names_to = "metric", values_to = "value") |>
  mutate(lo = case_when(startsWith(metric, "Log") ~ ll_lo, startsWith(metric, "Brier") ~ b_lo, TRUE ~ a_lo),
         hi = case_when(startsWith(metric, "Log") ~ ll_hi, startsWith(metric, "Brier") ~ b_hi, TRUE ~ a_hi),
         model = factor(model, rev(model_order)),
         metric = factor(metric, c("Log-loss (lower is better)", "Brier score (lower is better)",
                                   "Accuracy (higher is better)")))
p1 <- ggplot(f1, aes(value, model, colour = model)) +
  geom_errorbar(aes(xmin = lo, xmax = hi), width = 0, linewidth = 0.8, orientation = "y") +
  geom_point(size = 3) +
  geom_text(aes(label = sprintf("%.3f", value)), vjust = -1, size = 3, colour = pal[["ink"]]) +
  facet_wrap(~metric, scales = "free_x") +
  scale_x_continuous(n.breaks = 4, expand = expansion(mult = 0.12)) +
  scale_colour_manual(values = model_cols_pal, guide = "none") +
  scale_y_discrete(labels = short_lab) +
  labs(title = "Round-model performance on held-out fights",
       subtitle = sprintf("Judge-round predictions on held-out fights, %s to %s (n = %s judge-rounds). Bars: 95%% bootstrap CI over fights.",
                          format(min(test_rounds$date), "%Y"), format(max(test_rounds$date), "%Y"),
                          format(nrow(test_rounds), big.mark = ",")),
       x = NULL, y = NULL, caption = SOURCE_CAPTION) +
  theme_robbery() +
  theme(panel.spacing.x = unit(2, "lines"))
save_fig(p1, "p3_model_comparison", width = 10, height = 4)

# Fig 2: calibration on the test set.
p2 <- test_calibration |>
  mutate(model = factor(model, model_order, labels = short_lab[model_order])) |>
  ggplot(aes(pred, obs)) +
  geom_abline(linetype = "dashed", colour = pal[["grey"]]) +
  geom_linerange(aes(ymin = lo, ymax = hi), colour = pal[["ink"]], linewidth = 0.5) +
  geom_point(aes(size = n), colour = pal[["ink"]], fill = "white", shape = 21, stroke = 1) +
  facet_wrap(~model, nrow = 1) +
  scale_size_area(max_size = 5, labels = scales::comma, name = "Judge-rounds in bin") +
  scale_x_continuous(labels = scales::percent, limits = c(0, 1)) +
  scale_y_continuous(labels = scales::percent, limits = c(0, 1)) +
  coord_equal() +
  labs(title = "Predicted vs. observed: how often judges actually gave the round to fighter A",
       subtitle = "Test set, 10 equal-width bins of predicted probability. On the dashed line = perfectly calibrated.",
       x = "Predicted probability", y = "Observed share", caption = SOURCE_CAPTION) +
  theme_robbery()
save_fig(p2, "p3_calibration", width = 11, height = 4.2)

# Fig 3: rolling-origin log-loss by year.
f3 <- rolling_results |> mutate(model = factor(model, model_order))
p3 <- ggplot(f3, aes(year, log_loss, colour = model, linetype = model == "baseline")) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2.2) +
  ggrepel::geom_text_repel(data = filter(f3, year == max(year)), aes(label = short_lab[as.character(model)]),
                           nudge_x = 0.4, hjust = 0, direction = "y", size = 3.2, segment.colour = NA,
                           show.legend = FALSE) +
  scale_colour_manual(values = model_cols_pal, labels = short_lab, name = NULL) +
  scale_linetype_manual(values = c(`FALSE` = "solid", `TRUE` = "dashed"), guide = "none") +
  scale_x_continuous(breaks = 2020:2026, expand = expansion(add = c(0.2, 2.2))) +
  labs(title = "Out-of-sample log-loss, year by year",
       subtitle = "Each year is predicted by models trained only on earlier years. Lower is better.",
       x = NULL, y = "Log-loss", caption = SOURCE_CAPTION) +
  theme_robbery()
save_fig(p3, "p3_logloss_by_year", width = 9, height = 5)

# Fig 4: what judges reward, as an exchange rate in significant head strikes.
unit_scale <- c(d_sig_acc = 0.1)   # show accuracy per +10 percentage points
f4 <- logit_effects |>
  filter(feature != "d_head_l") |>
  mutate(sc = coalesce(unit_scale[feature], 1),
         across(c(head_equiv, head_equiv_lo, head_equiv_hi), \(x) x * sc),
         label = if_else(feature == "d_sig_acc", "Sig. strike accuracy (+10 pts)", label),
         label = paste0(label, if_else(feature %in% c("d_kd", "d_td_l", "d_sub_att", "d_rev"), " (each)", "")),
         clear = head_equiv_lo > 0 | head_equiv_hi < 0,
         label = forcats::fct_reorder(label, head_equiv))
p4 <- ggplot(f4, aes(head_equiv, label, colour = clear)) +
  geom_vline(xintercept = 0, colour = pal[["grey"]]) +
  geom_vline(xintercept = 1, colour = pal[["grey"]], linetype = "dotted") +
  geom_errorbar(aes(xmin = head_equiv_lo, xmax = head_equiv_hi), width = 0, linewidth = 0.8, orientation = "y") +
  geom_point(size = 3) +
  geom_text(aes(label = sprintf("%.1f", head_equiv)), vjust = -0.9, size = 3, colour = pal[["ink"]]) +
  scale_colour_manual(values = c(`TRUE` = pal[["ink"]], `FALSE` = pal[["grey"]]),
                      labels = c(`TRUE` = "Clearly different from zero", `FALSE` = "CI includes zero"), name = NULL) +
  labs(title = "What judges reward, in significant head strikes",
       subtitle = paste0("How many extra significant head strikes the same edge is worth on a judge's card (dotted line = 1 strike).\n",
                         "Logistic model on ", format(logit_effects$n_rows[1], big.mark = ","), " judge-rounds; 95% CIs clustered by fight."),
       x = "Equivalent significant head strikes", y = NULL, caption = SOURCE_CAPTION) +
  theme_robbery()
save_fig(p4, "p3_what_judges_reward", width = 9, height = 6)

# Fig 5: xgboost SHAP importance.
f5 <- shap_imp |> mutate(label = forcats::fct_reorder(coalesce(FEATURE_LABELS[feature], feature), mean_abs))
p5 <- ggplot(f5, aes(mean_abs, label)) +
  geom_col(fill = model_cols_pal[["xgboost"]], width = 0.7) +
  geom_text(aes(label = scales::percent(share, accuracy = 1)), hjust = -0.2, size = 3, colour = pal[["ink"]]) +
  scale_x_continuous(expand = expansion(mult = c(0, 0.12))) +
  labs(title = "Gradient boosting: which stats move the prediction most",
       subtitle = "Mean absolute SHAP value (log-odds) over 4,000 judge-rounds; label = share of total.",
       x = "Mean |SHAP|", y = NULL, caption = SOURCE_CAPTION) +
  theme_robbery()
save_fig(p5, "p3_shap_importance", width = 8.5, height = 5.5)

# Fig 6: SHAP dependence for the four biggest drivers.
top4 <- head(shap_imp$feature, 4)
f6 <- map_dfr(top4, \(f) tibble(feature = f, value = shap_xgb$X[[f]], shap = shap_xgb$S[, f])) |>
  mutate(feature = factor(feature, top4, labels = coalesce(FEATURE_LABELS[top4], top4)))
p6 <- ggplot(f6, aes(value, shap)) +
  geom_hline(yintercept = 0, colour = pal[["grey"]]) +
  geom_point(alpha = 0.15, size = 1, colour = model_cols_pal[["xgboost"]]) +
  facet_wrap(~feature, scales = "free_x") +
  labs(title = "How the boosted model's push toward fighter A changes with each stat",
       subtitle = "Each dot is a judge-round. x: A minus B differential; y: SHAP contribution (log-odds toward A).",
       x = "Differential (A minus B)", y = "SHAP (log-odds)", caption = SOURCE_CAPTION) +
  theme_robbery()
save_fig(p6, "p3_shap_dependence", width = 9, height = 6)

cat("\nFigures written to figures/\n")
