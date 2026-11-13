# 07_simulate.R: from round probabilities to fight outcomes (brief 6b) and the
# Robbery Index (brief 6c).
#
# 1. Round probabilities for every round of every decision. Fights whose
#    judges' scores were used to train the round model get *out-of-fold*
#    predictions (10-fold, grouped by fight), so a fight's own scorecards never
#    inform its own robbery score. Other fights use the model fit on all rounds.
# 2. Judges watch the same round, so their scores are correlated. We model each
#    judge's call as a latent normal: z_j = sqrt(rho) * u + sqrt(1 - rho) * e_j,
#    and the judge gives the round to A if z_j < qnorm(p). Each judge still
#    gives A the round with probability p, but the shared part u makes judges
#    agree more than independent coin flips would. rho is estimated by maximum
#    likelihood from how often the three real judges split on a round.
#    10-8 rounds get the same treatment with their own correlation rho8.
# 3. Simulate 10,000 sets of three scorecards per fight -> P(A), P(draw), P(B).
# 4. Robbery Score = 1 - P(declared winner wins the decision).

suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(purrr) })

N_SIMS <- 10000L
LIMITED_DATA_BEFORE <- as.Date("2008-01-01")
ROBBERY_TIERS <- c(Clean = 0, `Close / defensible` = 0.25, Questionable = 0.50, Robbery = 0.75)

# ---- Round inputs for every decision ------------------------------------------

add_diffs <- function(df) {
  mutate(df, across(all_of(paste0(DIFF_VARS, "_a")),
                    \(x) x - get(sub("_a$", "_b", cur_column())),
                    .names = "d_{sub('_a$', '', .col)}"))
}

# One row per round of every linked decision, with model features.
decision_rounds <- function(fight_table, rs_wide) {
  fight_table |>
    select(fight_url, decision_id, date, winner) |>
    inner_join(rs_wide, by = "fight_url") |>
    add_diffs() |>
    add_round_features() |>
    mutate(post_2017 = date >= CRITERIA_2017)
}

# Out-of-fold round probabilities (see header). `wf` is a finalized workflow.
oof_round_probs <- function(wf, model_ok, dec_rounds, final_fit, v = 10) {
  fights <- unique(model_ok$fight_url)
  folds <- tibble::tibble(fight_url = fights, fold = sample(rep(seq_len(v), length.out = length(fights))))
  oof <- map_dfr(seq_len(v), \(k) {
    tr <- semi_join(model_ok, filter(folds, fold != k), by = "fight_url")
    fit <- parsnip::fit(wf, mirror_rounds(tr) |> select(all_of(model_cols)))
    nd <- semi_join(dec_rounds, filter(folds, fold == k), by = "fight_url")
    tibble::tibble(fight_url = nd$fight_url, round = nd$round, p_a = predict_round(fit, nd), source = "out-of-fold")
  })
  rest <- filter(dec_rounds, !fight_url %in% fights)
  bind_rows(oof, tibble::tibble(fight_url = rest$fight_url, round = rest$round,
                                p_a = predict_round(final_fit, rest), source = "full-data fit"))
}

# ---- Judge correlation ----------------------------------------------------------

# Quadrature grid over the shared latent factor u ~ N(0, 1).
U_GRID <- local({
  u <- seq(-6, 6, length.out = 241)
  list(u = u, w = dnorm(u) / sum(dnorm(u)))
})

# P(k of 3 judges pick the event), k = 0..3, for event probabilities p and latent correlation rho.
p_k_of_3 <- function(p, rho) {
  a <- qnorm(pmin(pmax(p, 1e-4), 1 - 1e-4))
  q <- pnorm(outer(a, sqrt(rho) * U_GRID$u, "-") / sqrt(1 - rho))
  sapply(0:3, \(k) drop((choose(3, k) * q^k * (1 - q)^(3 - k)) %*% U_GRID$w))
}

fit_rho <- function(p, k) {
  nll <- \(r) -sum(log(p_k_of_3(p, r)[cbind(seq_along(k), k + 1)]))
  optimize(nll, c(0.001, 0.99))$minimum
}

# Rounds scored by exactly 3 judges, all of whom picked a winner (no 10-10s).
judge_round_triples <- function(model_data, round_probs) {
  model_data |>
    filter(is.na(drop_reason) | drop_reason == "10-10 round") |>
    group_by(fight_url, round) |>
    filter(n() == 3, all(margin > 0)) |>
    summarise(k_a = sum(judge_winner == "a"), k_108 = sum(margin >= 2),
              unanimous = k_a %in% c(0, 3), winner_side = if_else(k_a >= 2, "a", "b"),
              date = first(date), .groups = "drop") |>
    inner_join(round_probs |> select(fight_url, round, p_a), by = c("fight_url", "round"))
}

# Estimate rho (who wins the round) with a bootstrap CI over fights, and compare
# the observed split-round rate with what independence (rho = 0) would imply.
estimate_judge_corr <- function(triples, reps = 200) {
  rho <- fit_rho(triples$p_a, triples$k_a)
  by_fight <- split(seq_len(nrow(triples)), triples$fight_url)
  boot <- map_dbl(seq_len(reps), \(r) {
    i <- unlist(by_fight[sample(names(by_fight), replace = TRUE)], use.names = FALSE)
    fit_rho(triples$p_a[i], triples$k_a[i])
  })
  split_rate <- \(r) mean(1 - rowSums(p_k_of_3(triples$p_a, r)[, c(1, 4)]))
  tibble::tibble(rho = rho, rho_lo = quantile(boot, 0.025), rho_hi = quantile(boot, 0.975),
                 n_rounds = nrow(triples), n_fights = length(by_fight),
                 split_obs = mean(!triples$unanimous),
                 split_pred_rho = split_rate(rho), split_pred_indep = split_rate(0))
}

# ---- 10-8 and 10-10 probabilities -----------------------------------------------

# P(10-8 | that fighter wins the round), for each side of each round.
ten_eight_probs <- function(ten_eight_model, dec_rounds) {
  side <- \(w) {
    nd <- dec_rounds |>
      transmute(w_kd = w * d_kd, w_sig = w * (d_head_l + d_body_l + d_leg_l), w_ctrl = w * d_ctrl_min,
                w_td = w * d_td_l, w_sub = w * d_sub_att, w_ground = w * d_ground_l, post_2017)
    predict(ten_eight_model, nd, type = "response")
  }
  tibble::tibble(fight_url = dec_rounds$fight_url, round = dec_rounds$round,
                 q8_a = side(1), q8_b = side(-1))
}

# 10-8 correlation: among rounds where all three judges agreed on the winner,
# how often do several of them give the 10-8 together?
estimate_ten_eight_corr <- function(triples, q8) {
  t <- triples |> filter(unanimous) |>
    inner_join(q8, by = c("fight_url", "round")) |>
    mutate(q = if_else(winner_side == "a", q8_a, q8_b))
  tibble::tibble(rho8 = fit_rho(t$q, t$k_108), n_rounds = nrow(t),
                 rounds_any_108 = sum(t$k_108 > 0), rounds_all3_108 = sum(t$k_108 == 3))
}

# P(a judge scores the round 10-10), higher when the round is close.
fit_ten_ten <- function(model_data, round_probs) {
  d <- model_data |>
    filter(is.na(drop_reason) | drop_reason == "10-10 round") |>
    inner_join(round_probs |> select(fight_url, round, p_a), by = c("fight_url", "round")) |>
    mutate(is_even = as.numeric(margin == 0), closeness = abs(p_a - 0.5))
  glm(is_even ~ closeness + post_2017, family = binomial(), data = d)
}

# ---- Simulation -------------------------------------------------------------------

# Simulate n sets of three judges' cards for one fight. Inputs are per-round
# vectors: p (P(A wins round)), q8a/q8b (P(10-8 | A / B wins)), p10 (P(10-10)).
simulate_fight <- function(p, q8a, q8b, p10, rho, rho8, ded_a = 0, ded_b = 0, n = N_SIMS, judges = 3) {
  R <- length(p)
  thr <- matrix(qnorm(pmin(pmax(p, 1e-6), 1 - 1e-6)), n, R, byrow = TRUE)
  t8a <- matrix(qnorm(q8a), n, R, byrow = TRUE)
  t8b <- matrix(qnorm(q8b), n, R, byrow = TRUE)
  e10 <- matrix(p10, n, R, byrow = TRUE)
  u <- matrix(rnorm(n * R), n, R)
  u8 <- matrix(rnorm(n * R), n, R)
  cards <- sapply(seq_len(judges), \(j) {
    a_wins <- sqrt(rho) * u + sqrt(1 - rho) * rnorm(n * R) < thr
    z8 <- sqrt(rho8) * u8 + sqrt(1 - rho8) * rnorm(n * R)
    big <- z8 < ifelse(a_wins, t8a, t8b)
    even <- matrix(runif(n * R), n, R) < e10
    pts <- ifelse(even, 0, ifelse(a_wins, 1, -1) * (1 + big))
    rowSums(pts) - ded_a + ded_b     # this judge's card margin, A minus B, after deductions
  })
  n_a <- rowSums(cards > 0)
  n_b <- rowSums(cards < 0)
  res <- ifelse(n_a >= 2, "a", ifelse(n_b >= 2, "b", "draw"))
  tibble::tibble(p_a = mean(res == "a"), p_draw = mean(res == "draw"), p_b = mean(res == "b"),
                 p_split = mean((n_a >= 1 & n_b >= 1)),
                 p_card_a = mean(cards > 0), p_card_even = mean(cards == 0),
                 exp_card_margin = mean(cards))
}

simulate_all <- function(dec_rounds, round_probs, q8, ten_ten_model, rho, rho8, deductions, n = N_SIMS) {
  d <- dec_rounds |>
    select(fight_url, round, post_2017) |>
    inner_join(round_probs |> select(fight_url, round, p_a), by = c("fight_url", "round")) |>
    inner_join(q8, by = c("fight_url", "round")) |>
    mutate(closeness = abs(p_a - 0.5),
           p10 = predict(ten_ten_model, pick(closeness, post_2017), type = "response")) |>
    left_join(deductions |> select(fight_url, ded_a, ded_b), by = "fight_url") |>
    mutate(ded_a = coalesce(ded_a, 0L), ded_b = coalesce(ded_b, 0L)) |>
    arrange(fight_url, round)
  d |>
    group_by(fight_url) |>
    group_modify(\(x, k) simulate_fight(x$p_a, x$q8_a, x$q8_b, x$p10, rho, rho8,
                                        ded_a = x$ded_a[1], ded_b = x$ded_b[1], n = n)) |>
    ungroup()
}

# ---- Robbery Index -----------------------------------------------------------------

robbery_tier <- function(score) {
  cut(score, breaks = c(ROBBERY_TIERS, Inf), labels = names(ROBBERY_TIERS), right = FALSE)
}

# Per-fight stat summary oriented to the declared winner (W) and loser (L),
# used for the one-line explanation.
fight_stat_summary <- function(dec_rounds, round_probs) {
  dec_rounds |>
    filter(winner != "draw") |>
    inner_join(round_probs |> select(fight_url, round, p_a), by = c("fight_url", "round")) |>
    mutate(s = if_else(winner == "a", 1, -1),         # +1 when A is the declared winner
           sig_w = if_else(s > 0, sig_l_a, sig_l_b), sig_l = if_else(s > 0, sig_l_b, sig_l_a),
           head_w = if_else(s > 0, head_l_a, head_l_b), head_l = if_else(s > 0, head_l_b, head_l_a),
           kd_w = if_else(s > 0, kd_a, kd_b), kd_l = if_else(s > 0, kd_b, kd_a),
           td_w = if_else(s > 0, td_l_a, td_l_b), td_l = if_else(s > 0, td_l_b, td_l_a),
           ctrl_w = if_else(s > 0, ctrl_s_a, ctrl_s_b), ctrl_l = if_else(s > 0, ctrl_s_b, ctrl_s_a),
           sub_w = if_else(s > 0, sub_att_a, sub_att_b), sub_l = if_else(s > 0, sub_att_b, sub_att_a),
           p_loser_round = if_else(s > 0, 1 - p_a, p_a)) |>
    group_by(fight_url) |>
    summarise(n_rounds = n(),
              rounds_model_loser = sum(p_loser_round > 0.5),
              rounds_sig_loser = sum(sig_l > sig_w),
              across(c(sig_w, sig_l, head_w, head_l, kd_w, kd_l, td_w, td_l, ctrl_w, ctrl_l, sub_w, sub_l), sum),
              round_probs_loser = paste(sprintf("%.0f%%", 100 * p_loser_round), collapse = " / "),
              .groups = "drop")
}

surname_of <- function(x) stringr::word(x, -1)
fmt_mss <- function(s) sprintf("%d:%02d", as.integer(abs(s) %/% 60), as.integer(round(abs(s) %% 60)))

# One-line, data-driven explanation. It gives the loser's statistical case and
# then the winner's best counter-argument (knockdowns, head strikes, grappling),
# so readers can see what the stats may be missing.
explain_fight <- function(winner_name, loser_name, s) {
  W <- surname_of(winner_name); L <- surname_of(loser_name)
  # Ties get their own wording, so an even count is never described as one fighter out-landing the other.
  strikes <- ifelse(
    s$sig_l == s$sig_w,
    sprintf("%s and %s were even at %d-%d in sig. strikes (%s ahead in %d of %d rounds)",
            L, W, s$sig_l, s$sig_w, L, s$rounds_sig_loser, s$n_rounds),
    sprintf("%s out-landed %s %d-%d in sig. strikes (ahead in %d of %d)",
            ifelse(s$sig_l > s$sig_w, L, W), ifelse(s$sig_l > s$sig_w, W, L),
            pmax(s$sig_l, s$sig_w), pmin(s$sig_l, s$sig_w),
            ifelse(s$sig_l > s$sig_w, s$rounds_sig_loser, s$n_rounds - s$rounds_sig_loser), s$n_rounds))
  lead <- sprintf("Model favored %s in %d of %d rounds; %s", L, s$rounds_model_loser, s$n_rounds, strikes)
  counter <- pmap_chr(list(W, L, s$kd_w, s$kd_l, s$head_w, s$head_l, s$td_w, s$td_l, s$ctrl_w, s$ctrl_l),
    \(W, L, kdw, kdl, hw, hl, tdw, tdl, cw, cl) {
      parts <- c(
        if (isTRUE(kdw > kdl)) sprintf("%s scored %d knockdown%s", W, kdw, if (kdw > 1) "s" else ""),
        if (isTRUE(kdl > kdw)) sprintf("%s scored %d knockdown%s", L, kdl, if (kdl > 1) "s" else ""),
        if (isTRUE(hw > hl)) sprintf("%s landed more head strikes (%d-%d)", W, hw, hl),
        if (isTRUE(tdw > tdl)) sprintf("%s had %d takedown%s to %d", W, tdw, if (tdw != 1) "s" else "", tdl),
        if (isTRUE(cw - cl >= 60)) sprintf("%s had %s more control time", W, fmt_mss(cw - cl)),
        if (isTRUE(cl - cw >= 60)) sprintf("%s had %s more control time", L, fmt_mss(cl - cw))
      )
      if (length(parts) == 0) "" else paste0("; ", paste(parts, collapse = "; "))
    })
  paste0(lead, counter, ".")
}

build_robbery_index <- function(fight_table, sims, stat_summary, deductions) {
  fight_table |>
    inner_join(sims, by = "fight_url") |>
    left_join(deductions, by = "fight_url") |>
    left_join(stat_summary, by = "fight_url") |>
    mutate(
      winner_name = case_when(winner == "a" ~ fighter_a, winner == "b" ~ fighter_b),
      loser_name  = case_when(winner == "a" ~ fighter_b, winner == "b" ~ fighter_a),
      p_winner = case_when(winner == "a" ~ p_a, winner == "b" ~ p_b),
      p_loser  = case_when(winner == "a" ~ p_b, winner == "b" ~ p_a),
      robbery_score = 1 - p_winner,
      tier = robbery_tier(robbery_score),
      media_scored = media_a + media_b + media_draw,
      media_for_loser = case_when(winner == "a" ~ media_b, winner == "b" ~ media_a),
      media_loser_share = if_else(media_scored > 0, media_for_loser / media_scored, NA_real_),
      # Thin data: early-era stats were coded from video years later, and few media scored these fights.
      limited_corroboration = date < LIMITED_DATA_BEFORE | coalesce(media_scored, 0L) < 3L
    ) |>
    mutate(why = if_else(winner == "draw", NA_character_,
                         explain_fight(winner_name, loser_name, pick(everything()))),
           why = if_else(!is.na(why) & !is.na(ded_note),
                         paste0(sub("\\.$", "", why), "; point deduction: ", ded_note, "."), why))
}

# ---- Direct fight-level model (sanity check) ----------------------------------------

# Logistic regression on fight-total differentials, no intercept (corner-
# symmetric), with out-of-fold predictions so it can be compared fairly.
fight_level_check <- function(dec_rounds, fight_table, v = 10) {
  feats <- setdiff(ROUND_FEATURES, "d_sig_acc")
  ft <- dec_rounds |>
    group_by(fight_url) |>
    summarise(across(all_of(feats), sum), d_sig_acc = mean(d_sig_acc), n_rounds = n(), .groups = "drop") |>
    mutate(across(c(all_of(feats), d_sig_acc), \(x) x / n_rounds)) |>     # per-round averages
    inner_join(fight_table |> filter(winner != "draw") |> select(fight_url, winner), by = "fight_url") |>
    mutate(ya = as.numeric(winner == "a"))
  f <- reformulate(c(feats, "d_sig_acc"), response = "ya", intercept = FALSE)
  fold <- sample(rep(seq_len(v), length.out = nrow(ft)))
  ft$p_direct <- NA_real_
  for (k in seq_len(v)) {
    m <- glm(f, family = binomial(), data = ft[fold != k, ])
    ft$p_direct[fold == k] <- predict(m, ft[fold == k, ], type = "response")
  }
  select(ft, fight_url, winner, p_direct)
}

score_fight_probs <- function(p_winner) {
  pc <- pmin(pmax(p_winner, 1e-6), 1 - 1e-6)
  tibble::tibble(log_loss = -mean(log(pc)), brier = mean((1 - p_winner)^2),
                 accuracy = mean(p_winner > 0.5), n = length(p_winner))
}

# ---- Totals-only check (Option A) ----------------------------------------------------

# For every judge card with a total, compare the judge's actual card winner with
# the simulated probability that a single judge's card favours A. Split by
# whether the fight had round scores (in training, out-of-fold) or totals only
# (never used in training at all).
card_total_check <- function(mmad_parsed, links, sims, fight_table) {
  mmad_parsed$judge_totals |>
    inner_join(links |> filter(confidence != "unmatched") |> select(decision_id, fight_url, f1_is_a),
               by = "decision_id") |>
    inner_join(fight_table |> filter(!placeholder_totals %in% TRUE) |>
                 select(fight_url, date, has_round_scores), by = "fight_url") |>
    inner_join(sims |> select(fight_url, p_card_a, p_card_even, exp_card_margin), by = "fight_url") |>
    mutate(total_a = if_else(f1_is_a, total_f1, total_f2), total_b = if_else(f1_is_a, total_f2, total_f1),
           margin_a = total_a - total_b,
           card_side = case_when(margin_a > 0 ~ "a", margin_a < 0 ~ "b", TRUE ~ "even"),
           group = if_else(has_round_scores %in% TRUE, "Round scores (out-of-fold)", "Totals only (never trained on)"))
}
