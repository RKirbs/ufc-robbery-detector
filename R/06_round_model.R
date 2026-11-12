# 06_round_model.R: the round-level model (brief section 6a).
#
# Unit of analysis: one judge's score of one round. Outcome: which fighter that
# judge gave the round to (A or B). Features: A-minus-B differentials for that
# round only (no fight outcome, method or other-round information).
#
# Design choices (see NOTES.md):
#   - 10-10 rounds (0.5% of judge-rounds) are dropped from the winner model and
#     handled in the Phase 4 simulation; 10-8 rounds count as a win for the
#     fighter given the 10, and a separate model predicts P(10-8 | winner).
#   - Corner symmetry: training rows are mirrored (each round appears once from
#     each fighter's view, differentials flipped), and every prediction is
#     symmetrised: p(A) = [p(x) + 1 - p(-x)] / 2. So no model can learn
#     "red corner wins"; that's tested separately in the judge analysis.
#   - Option A (approved 2026-11-12): train only on rounds with judge round scores.

suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(purrr) })

# Test period for the time-based split: train on earlier years, test on these.
TEST_START <- as.Date("2020-01-01")
# Provisional date the 2017 ABC judging-criteria update took effect (verified
# and cited in Phase 5; used here only as an era flag in the 10-8 model).
CRITERIA_2017 <- as.Date("2017-01-01")

# Round features (all A-minus-B differentials; each flips sign under mirroring).
# Significant strikes enter by target (head/body/leg), which sum to sig. strikes
# landed. Clinch and ground strikes are added as *extra* terms, so their
# coefficients are the premium (or discount) over a distance strike to the same
# target. Distance is the reference position.
ROUND_FEATURES <- c("d_kd", "d_head_l", "d_body_l", "d_leg_l", "d_clinch_l", "d_ground_l",
                    "d_nonsig_l", "d_sig_acc", "d_td_l", "d_td_fail", "d_sub_att", "d_rev",
                    "d_ctrl_min")

FEATURE_LABELS <- c(
  d_kd = "Knockdowns", d_head_l = "Sig. head strikes", d_body_l = "Sig. body strikes",
  d_leg_l = "Sig. leg strikes", d_clinch_l = "Clinch premium (per sig. strike)",
  d_ground_l = "Ground premium (per sig. strike)", d_nonsig_l = "Non-significant strikes",
  d_sig_acc = "Sig. strike accuracy (share)", d_td_l = "Takedowns landed",
  d_td_fail = "Failed takedown attempts", d_sub_att = "Submission attempts",
  d_rev = "Reversals", d_ctrl_min = "Control time (minutes)", pace = "Round pace (total sig. strikes)"
)

MODEL_LABELS <- c(baseline = "Baseline: sig. strike leader", logistic = "Logistic",
                  glmnet = "Regularized logistic (glmnet)", xgboost = "Gradient boosting (xgboost)")

# ---- Data preparation -------------------------------------------------------

# Add model features to a table of A/B round stats. `pace` (total significant
# strikes by both fighters) is a symmetric context variable: it doesn't flip
# under mirroring, so it can only matter through interactions.
add_round_features <- function(df) {
  acc <- \(l, a) (l + 1) / (a + 2)   # smoothed accuracy, defined even with 0 attempts
  df |>
    mutate(
      d_sig_acc  = acc(sig_l_a, sig_a_a) - acc(sig_l_b, sig_a_b),
      d_nonsig_l = (tot_l_a - sig_l_a) - (tot_l_b - sig_l_b),
      d_td_fail  = (td_a_a - td_l_a) - (td_a_b - td_l_b),
      d_ctrl_min = d_ctrl_s / 60,
      pace       = sig_l_a + sig_l_b
    )
}

# Build the modeling table from the judge x round table. Flags (and drops) the
# cards found faulty in Phase 2 and the 10-10 rounds.
prep_model_data <- function(judge_rounds, ufc_fights, mmad_parsed) {
  cards <- judge_rounds |>
    group_by(decision_id, judge_order, fight_url) |>
    summarise(n_rounds = n(), s1 = sum(score_f1), s2 = sum(score_f2), .groups = "drop") |>
    left_join(mmad_parsed$judge_totals |> select(decision_id, judge_order, total_f1, total_f2),
              by = c("decision_id", "judge_order")) |>
    left_join(ufc_fights |> select(fight_url, last_round), by = "fight_url") |>
    mutate(bad_count = n_rounds != last_round,
           bad_sum = coalesce(s1 != total_f1 | s2 != total_f2, FALSE))

  judge_rounds |>
    left_join(cards |> select(decision_id, judge_order, bad_count, bad_sum),
              by = c("decision_id", "judge_order")) |>
    add_round_features() |>
    mutate(
      drop_reason = case_when(
        bad_count ~ "round count differs from UFCStats",
        bad_sum ~ "round scores don't sum to card total",
        margin == 0 ~ "10-10 round",
        TRUE ~ NA_character_),
      y = factor(judge_winner, levels = c("a", "b")),
      year = as.integer(format(date, "%Y")),
      post_2017 = date >= CRITERIA_2017,
      split = if_else(date >= TEST_START, "test", "train")
    )
}

# Flip a round to the other fighter's view: negate every differential and swap
# the outcome. Symmetric context variables (pace) are unchanged.
mirror_features <- function(df) mutate(df, across(all_of(ROUND_FEATURES), \(x) -x))

mirror_rounds <- function(df) {
  flipped <- mirror_features(df) |>
    mutate(y = factor(if_else(y == "a", "b", "a"), levels = c("a", "b")))
  bind_rows(mutate(df, mirrored = FALSE), mutate(flipped, mirrored = TRUE))
}

# ---- Model specifications (tidymodels) --------------------------------------

model_cols <- c("y", "fight_url", ROUND_FEATURES, "pace")

make_workflows <- function(template) {
  base_rec <- recipes::recipe(y ~ ., data = template) |>
    recipes::update_role(fight_url, new_role = "group")

  # 1. Logistic regression on the main differentials (fully interpretable).
  logistic <- workflows::workflow(
    base_rec |> recipes::step_rm(pace),
    parsnip::logistic_reg() |> parsnip::set_engine("glm"))

  # 2. Regularized logistic regression with nonlinear terms and interactions.
  # Interactions must be odd functions of the differentials to survive
  # mirroring, so we use: signed square roots (diminishing returns to big
  # leads), knockdowns x |sig. strike gap|, and each differential x log(pace)
  # (does a 5-strike lead matter more in a slow round?).
  glmnet_rec <- base_rec |>
    recipes::step_mutate(
      ss_sig = sign(d_head_l + d_body_l + d_leg_l) * sqrt(abs(d_head_l + d_body_l + d_leg_l)),
      ss_ctrl = sign(d_ctrl_min) * sqrt(abs(d_ctrl_min)),
      ss_td = sign(d_td_l) * sqrt(abs(d_td_l)),
      kd_x_sig_gap = d_kd * abs(d_head_l + d_body_l + d_leg_l),
      lpace = log1p(pace)) |>
    recipes::step_interact(terms = ~ dplyr::starts_with("d_"):lpace, sep = "_x_") |>
    recipes::step_rm(pace, lpace) |>
    recipes::step_normalize(recipes::all_numeric_predictors())
  glmnet <- workflows::workflow(
    glmnet_rec,
    parsnip::logistic_reg(penalty = tune::tune(), mixture = tune::tune()) |>
      parsnip::set_engine("glmnet"))

  # 3. Gradient boosting on the differentials plus pace.
  xgboost <- workflows::workflow(
    base_rec,
    parsnip::boost_tree(trees = tune::tune(), tree_depth = tune::tune(), learn_rate = tune::tune(),
                        min_n = tune::tune(), sample_size = tune::tune()) |>
      parsnip::set_engine("xgboost", nthread = max(1L, parallel::detectCores() - 1L)) |>
      parsnip::set_mode("classification"))

  list(logistic = logistic, glmnet = glmnet, xgboost = xgboost)
}

round_metrics <- function() yardstick::metric_set(yardstick::mn_log_loss, yardstick::brier_class,
                                                   yardstick::accuracy)

# ---- Baseline -----------------------------------------------------------------

# Naive baseline: the fighter who landed more significant strikes wins the round.
# To give it a log-loss, it predicts the training share q of rounds the leader
# wins (and 0.5 when strikes are level).
baseline_fit <- function(train) {
  s <- train |> mutate(sig = d_head_l + d_body_l + d_leg_l) |> filter(sig != 0)
  list(q = mean((s$sig > 0) == (s$y == "a")))
}
baseline_predict <- function(fit, new) {
  sig <- new$d_head_l + new$d_body_l + new$d_leg_l
  case_when(sig > 0 ~ fit$q, sig < 0 ~ 1 - fit$q, TRUE ~ 0.5)
}

# ---- Tuning with grouped CV (never split a fight across folds) ----------------

make_folds <- function(train_mirrored, v = 5) {
  rsample::group_vfold_cv(train_mirrored, group = fight_url, v = v)
}

tune_round_models <- function(wfs, folds) {
  ctrl <- tune::control_grid(save_pred = FALSE, verbose = FALSE)
  m <- round_metrics()
  logistic <- tune::fit_resamples(wfs$logistic, folds, metrics = m)
  glmnet <- tune::tune_grid(
    wfs$glmnet, folds, metrics = m, control = ctrl,
    grid = tidyr::crossing(penalty = 10^seq(-5, -1, length.out = 25), mixture = c(0, 0.5, 1)))
  xgb_grid <- dials::grid_space_filling(
    dials::trees(c(200L, 1200L)), dials::tree_depth(c(2L, 6L)),
    dials::learn_rate(c(-2.3, -1)), dials::min_n(c(5L, 80L)),
    dials::sample_prop(c(0.5, 1)), size = 16)
  names(xgb_grid)[names(xgb_grid) == "sample_prop"] <- "sample_size"
  xgboost <- tune::tune_grid(wfs$xgboost, folds, metrics = m, control = ctrl, grid = xgb_grid)
  list(logistic = logistic, glmnet = glmnet, xgboost = xgboost)
}

# Baseline metrics on the same folds (for a like-for-like CV comparison).
cv_baseline <- function(folds) {
  map_dfr(folds$splits, \(s) {
    fit <- baseline_fit(rsample::analysis(s))
    a <- rsample::assessment(s)
    score_probs(a$y, baseline_predict(fit, a))
  }) |>
    summarise(across(everything(), mean))
}

# Finalize: plug the best (lowest CV log-loss) hyperparameters into each workflow.
finalize_round_workflows <- function(wfs, tuned) {
  list(
    logistic = wfs$logistic,
    glmnet = tune::finalize_workflow(wfs$glmnet, tune::select_best(tuned$glmnet, metric = "mn_log_loss")),
    xgboost = tune::finalize_workflow(wfs$xgboost, tune::select_best(tuned$xgboost, metric = "mn_log_loss"))
  )
}

cv_summary <- function(tuned, base_cv) {
  best <- imap_dfr(tuned, \(t, nm) {
    cm <- tune::collect_metrics(t)
    if (nm != "logistic") {
      cfg <- tune::select_best(t, metric = "mn_log_loss")$.config
      cm <- filter(cm, .config == cfg)
    }
    cm |> select(.metric, mean, std_err) |> mutate(model = nm)
  })
  bind_rows(
    best,
    tibble::tibble(model = "baseline", .metric = c("mn_log_loss", "brier_class", "accuracy"),
                   mean = c(base_cv$log_loss, base_cv$brier, base_cv$accuracy), std_err = NA_real_)
  )
}

# ---- Fitting and symmetric prediction ----------------------------------------

fit_round_workflows <- function(final_wfs, train) {
  tr <- mirror_rounds(train) |> select(all_of(model_cols))
  list(
    baseline = baseline_fit(train),
    logistic = parsnip::fit(final_wfs$logistic, tr),
    glmnet = parsnip::fit(final_wfs$glmnet, tr),
    xgboost = parsnip::fit(final_wfs$xgboost, tr)
  )
}

# P(judge gives the round to A), symmetrised so that swapping the fighters
# gives exactly 1 - p.
predict_round <- function(fit, new) {
  if (is.list(fit) && !inherits(fit, "workflow")) return(baseline_predict(fit, new))
  p1 <- predict(fit, new, type = "prob")$.pred_a
  p2 <- predict(fit, mirror_features(new), type = "prob")$.pred_a
  (p1 + 1 - p2) / 2
}

predict_all_models <- function(fits, new) {
  imap_dfr(fits, \(f, nm) new |>
             select(decision_id, judge_order, judge_id, fight_url, round, year, y) |>
             mutate(model = nm, p_a = predict_round(f, new)))
}

# ---- Scoring ------------------------------------------------------------------

score_probs <- function(y, p) {
  ya <- as.numeric(y == "a")
  pc <- pmin(pmax(p, 1e-6), 1 - 1e-6)
  tibble::tibble(log_loss = -mean(ya * log(pc) + (1 - ya) * log(1 - pc)),
                 brier = mean((p - ya)^2),
                 accuracy = mean((p > 0.5) == (ya == 1)),   # p = 0.5 counts as a B pick
                 n = length(y))
}

# Test-set metrics per model with 95% CIs from a bootstrap over fights (rounds
# from the same fight are resampled together, as are the three judges).
test_metrics <- function(preds, reps = 500) {
  point <- preds |> group_by(model) |> group_modify(\(d, k) score_probs(d$y, d$p_a)) |> ungroup()
  fights <- unique(preds$fight_url)
  by_fight <- split(seq_len(nrow(preds)), preds$fight_url)
  boot <- map_dfr(seq_len(reps), \(r) {
    idx <- unlist(by_fight[sample(fights, replace = TRUE)], use.names = FALSE)
    preds[idx, ] |> group_by(model) |> group_modify(\(d, k) score_probs(d$y, d$p_a)) |>
      ungroup() |> mutate(rep = r)
  })
  ci <- boot |> group_by(model) |>
    summarise(across(c(log_loss, brier, accuracy),
                     list(lo = \(x) quantile(x, 0.025), hi = \(x) quantile(x, 0.975))), .groups = "drop")
  # Improvement over the baseline, paired within each bootstrap draw.
  gain <- boot |> select(rep, model, log_loss) |>
    pivot_wider(names_from = model, values_from = log_loss) |>
    mutate(across(-c(rep, baseline), \(x) baseline - x)) |>
    select(-baseline) |>
    pivot_longer(-rep, names_to = "model", values_to = "ll_gain") |>
    group_by(model) |>
    summarise(ll_gain_lo = quantile(ll_gain, 0.025), ll_gain_hi = quantile(ll_gain, 0.975), .groups = "drop")
  point |> left_join(ci, by = "model") |> left_join(gain, by = "model")
}

# Binned calibration: mean predicted vs observed share, with Wilson intervals.
calibration_table <- function(preds, bins = 10) {
  preds |>
    mutate(bin = cut(p_a, breaks = seq(0, 1, length.out = bins + 1), include.lowest = TRUE)) |>
    group_by(model, bin) |>
    summarise(pred = mean(p_a), n = n(), k = sum(y == "a"), .groups = "drop") |>
    mutate(obs = k / n,
           z = 1.96,
           lo = (obs + z^2 / (2 * n) - z * sqrt(obs * (1 - obs) / n + z^2 / (4 * n^2))) / (1 + z^2 / n),
           hi = (obs + z^2 / (2 * n) + z * sqrt(obs * (1 - obs) / n + z^2 / (4 * n^2))) / (1 + z^2 / n))
}

# Rolling-origin evaluation: for each test year, train on every earlier year
# (hyperparameters fixed at their tuned values) and score that year.
rolling_preds <- function(final_wfs, model_data, years = 2020:2026) {
  map_dfr(years, \(yr) {
    fits <- fit_round_workflows(final_wfs, filter(model_data, year < yr))
    predict_all_models(fits, filter(model_data, year == yr))
  })
}

# ---- Interpretation: what do judges reward? ------------------------------------

# Logistic regression on all rounds (no mirroring needed: a no-intercept
# logistic on differentials is already corner-symmetric). Standard errors are
# clustered by fight, because the 3 judges and all rounds of a fight share data.
logistic_effects <- function(model_data, unit_feature = "d_head_l") {
  d <- model_data |> mutate(ya = as.numeric(y == "a"))
  f <- reformulate(ROUND_FEATURES, response = "ya", intercept = FALSE)
  m <- glm(f, family = binomial(), data = d)
  V <- sandwich::vcovCL(m, cluster = ~fight_url)
  b <- coef(m); se <- sqrt(diag(V))
  bu <- b[[unit_feature]]
  # "Exchange rate": how many significant head strikes one unit is worth,
  # with a delta-method CI from the clustered covariance.
  rate <- b / bu
  rate_se <- map_dbl(names(b), \(nm) {
    g <- setNames(rep(0, length(b)), names(b))
    g[nm] <- g[nm] + 1 / bu
    g[unit_feature] <- g[unit_feature] - b[[nm]] / bu^2
    sqrt(drop(t(g) %*% V %*% g))
  })
  tibble::tibble(feature = names(b), label = FEATURE_LABELS[names(b)], beta = b, se = se,
                 lo = b - 1.96 * se, hi = b + 1.96 * se, z = b / se,
                 p_alone = plogis(b),     # P(win) if this were the only difference, by 1 unit
                 head_equiv = rate, head_equiv_lo = rate - 1.96 * rate_se,
                 head_equiv_hi = rate + 1.96 * rate_se,
                 n_rows = nobs(m), n_fights = n_distinct(d$fight_url))
}

# SHAP values for the xgboost fit on a sample of rounds, oriented so positive
# values push toward fighter A. Which outcome level the booster predicts
# depends on the parsnip/xgboost version, so we check it against the
# workflow's own P(A) rather than assuming.
xgb_shap <- function(xgb_wf, new, n = 4000) {
  s <- dplyr::slice_sample(new, n = min(n, nrow(new)))
  X <- recipes::bake(workflows::extract_recipe(xgb_wf), new_data = s,
                     recipes::all_predictors()) |> as.data.frame()
  booster <- workflows::extract_fit_engine(xgb_wf)
  p_engine <- predict(booster, xgboost::xgb.DMatrix(as.matrix(X)))
  p_a <- predict(xgb_wf, s, type = "prob")$.pred_a
  sv <- shapviz::shapviz(booster, X_pred = as.matrix(X), X = X)
  if (isTRUE(all.equal(p_engine, 1 - p_a, tolerance = 1e-5))) {
    sv$S <- -sv$S
    sv$baseline <- -sv$baseline
  } else {
    stopifnot(isTRUE(all.equal(p_engine, p_a, tolerance = 1e-5)))
  }
  sv
}

# ---- 10-8 model ---------------------------------------------------------------

# Given that a judge gave a round to a fighter, how likely is it a 10-8 (or wider)?
# Features are oriented to the judge's winner. Includes an era flag because the
# 2017 criteria explicitly clarified when 10-8s should be given.
prep_ten_eight <- function(model_data) {
  model_data |>
    filter(is.na(drop_reason)) |>
    mutate(w = if_else(y == "a", 1, -1),
           w_kd = w * d_kd, w_sig = w * (d_head_l + d_body_l + d_leg_l),
           w_ctrl = w * d_ctrl_min, w_td = w * d_td_l, w_sub = w * d_sub_att,
           w_ground = w * d_ground_l,
           ten_eight = as.numeric(margin >= 2))
}

TEN_EIGHT_FORMULA <- ten_eight ~ w_kd + w_sig + I(pmax(w_sig, 0)^2 / 100) + w_ctrl + w_td +
  w_sub + w_ground + post_2017

ten_eight_cv <- function(te, v = 5) {
  folds <- rsample::group_vfold_cv(te, group = fight_url, v = v)
  map_dfr(folds$splits, \(s) {
    a <- rsample::analysis(s); b <- rsample::assessment(s)
    m <- glm(TEN_EIGHT_FORMULA, family = binomial(), data = a)
    p <- predict(m, b, type = "response"); p0 <- mean(a$ten_eight)
    ll <- \(p) -mean(b$ten_eight * log(p) + (1 - b$ten_eight) * log(1 - p))
    tibble::tibble(log_loss_model = ll(p), log_loss_const = ll(p0),
                   auc = as.numeric(yardstick::roc_auc_vec(factor(b$ten_eight, levels = c(1, 0)), p)))
  }) |> summarise(across(everything(), mean))
}

fit_ten_eight <- function(te) glm(TEN_EIGHT_FORMULA, family = binomial(), data = te)
