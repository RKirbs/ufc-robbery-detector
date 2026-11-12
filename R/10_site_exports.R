# 10_site_exports.R: write the small, committed datasets the Quarto site reads
# (data/final/). The site never touches raw data or the targets store, so anyone
# can re-render it from a fresh clone; `targets::tar_make()` regenerates these.

suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(purrr); library(stringr) })

FINAL_DIR <- "data/final"
N_FEATURED_ROBBERIES <- 6

# Judge cards re-ordered so the declared winner's total comes first.
cards_winner_first <- function(cards_a, winner) {
  map2_chr(cards_a, winner, \(cards, w) {
    if (is.na(cards) || w == "a" || w == "draw") return(cards)
    parts <- str_split(cards, "; ")[[1]]
    paste(str_replace(parts, "(\\d+)-(\\d+)$", "\\2-\\1"), collapse = "; ")
  })
}

export_robbery_index <- function(robbery_index, odds) {
  robbery_index |>
    left_join(odds |> select(fight_url, mkt_p_a), by = "fight_url") |>
    transmute(
      fight_url, date, year = as.integer(format(date, "%Y")), event, weightclass, title_fight,
      fighter_a, fighter_b, winner, winner_name, loser_name, decision_type,
      cards_winner_first = cards_winner_first(judge_cards_a, winner),
      p_a, p_b, p_draw, p_winner, p_loser, robbery_score, tier = as.character(tier),
      media_for_loser, media_scored, media_loser_share, limited_corroboration, why, ded_note,
      mkt_p_winner = case_when(winner == "a" ~ mkt_p_a, winner == "b" ~ 1 - mkt_p_a),
      sig_w, sig_l, n_rounds, rounds_model_loser
    )
}

# Fights featured on the lookup page: the top robberies plus widely debated
# decisions the model rates as close or clean (the "close but fair" contrast).
featured_fights <- function(robbery_index, face_valid) {
  top <- robbery_index |> filter(winner != "draw") |> slice_max(robbery_score, n = N_FEATURED_ROBBERIES) |>
    transmute(fight_url, group = "Top robbery")
  debated <- face_valid |>
    filter(robbery_score < 0.6) |>
    select(winner_name, loser_name, date) |>
    inner_join(robbery_index |> select(fight_url, winner_name, loser_name, date),
               by = c("winner_name", "loser_name", "date")) |>
    transmute(fight_url, group = "Widely debated decision")
  bind_rows(top, debated) |> distinct(fight_url, .keep_all = TRUE)
}

# Round-by-round stats (winner/loser view), model probabilities and each
# judge's official round scores for the featured fights.
featured_rounds <- function(feat, dec_rounds, round_probs) {
  dec_rounds |>
    semi_join(feat, by = "fight_url") |>
    inner_join(round_probs |> select(fight_url, round, p_a), by = c("fight_url", "round")) |>
    mutate(w = winner == "a") |>
    transmute(fight_url, round,
              p_loser_round = if_else(w, 1 - p_a, p_a),
              sig_w = if_else(w, sig_l_a, sig_l_b), sig_l = if_else(w, sig_l_b, sig_l_a),
              head_w = if_else(w, head_l_a, head_l_b), head_l = if_else(w, head_l_b, head_l_a),
              kd_w = if_else(w, kd_a, kd_b), kd_l = if_else(w, kd_b, kd_a),
              td_w = if_else(w, td_l_a, td_l_b), td_l = if_else(w, td_l_b, td_l_a),
              ctrl_w = if_else(w, ctrl_s_a, ctrl_s_b), ctrl_l = if_else(w, ctrl_s_b, ctrl_s_a),
              sub_w = if_else(w, sub_att_a, sub_att_b), sub_l = if_else(w, sub_att_b, sub_att_a))
}

featured_judges <- function(feat, mmad_judges_adj, links, robbery_index) {
  mmad_judges_adj |>
    mutate(round = suppressWarnings(as.integer(round))) |>
    filter(!is.na(round)) |>
    inner_join(links |> filter(confidence != "unmatched") |> select(decision_id, fight_url, f1_is_a), by = "decision_id") |>
    semi_join(feat, by = "fight_url") |>
    inner_join(robbery_index |> select(fight_url, winner), by = "fight_url") |>
    mutate(score_a = if_else(f1_is_a, score_f1_official, score_f2_official),
           score_b = if_else(f1_is_a, score_f2_official, score_f1_official),
           score_w = if_else(winner == "a", score_a, score_b),
           score_l = if_else(winner == "a", score_b, score_a)) |>
    select(fight_url, judge, judge_order, round, score_w, score_l)
}

# Scalar facts used inline in the narrative (key/value).
site_facts <- function(mmad_parsed, links, fight_table, model_data, model_ok, judge_corr, ten_eight_corr,
                       media_valid, round_agree, criteria_era, criteria_era_no2017, ten_eight_era,
                       robbery_time, fav_effects, red_market, odds_cov, mmad_deductions, logit_effects, corner) {
  pp <- \(b) 100 * (plogis(b) - 0.5)
  fe <- fav_effects$with_market
  mk <- fe$est[fe$term == "mkt_logit"]; mk_se <- fe$se[fe$term == "mkt_logit"]
  fav_pp <- \(b) 100 * (plogis(b * qlogis(0.75)) - 0.5)
  cf <- corner$full
  tibble::tribble(
    ~key, ~value,
    "n_mmad_pages", nrow(mmad_parsed$fight),
    "n_decisions", nrow(fight_table),
    "n_draws", sum(fight_table$winner == "draw"),
    "n_links_high", sum(links$confidence == "high"),
    "n_links_medium", sum(links$confidence == "medium"),
    "n_unmatched", sum(links$confidence == "unmatched"),
    "n_with_round_scores", sum(fight_table$has_round_scores %in% TRUE),
    "n_media_scores", sum(fight_table$n_media),
    "n_judge_rounds", nrow(model_ok),
    "n_model_fights", n_distinct(model_ok$fight_url),
    "n_ten_ten", sum(model_data$drop_reason == "10-10 round", na.rm = TRUE),
    "n_deductions", nrow(mmad_deductions),
    "n_deduction_fights", n_distinct(mmad_deductions$decision_id),
    "n_judges", n_distinct(model_ok$judge_id),
    "rho", judge_corr$rho, "rho_lo", judge_corr$rho_lo, "rho_hi", judge_corr$rho_hi,
    "split_obs", judge_corr$split_obs, "split_pred", judge_corr$split_pred_rho, "split_indep", judge_corr$split_pred_indep,
    "rho8", ten_eight_corr$rho8,
    "media_n", media_valid$n_fights, "media_r", media_valid$pearson,
    "media_r_lo", media_valid$pearson_lo, "media_r_hi", media_valid$pearson_hi,
    "media_rho", media_valid$spearman,
    "official_agrees_media", media_valid$official_agrees_media, "model_agrees_media", media_valid$model_agrees_media,
    "model_agrees_official", media_valid$model_agrees_official,
    "round_rounds", round_agree$rounds, "round_vs_majority", round_agree$model_vs_majority,
    "round_vs_majority_unan", round_agree$model_vs_majority_unanimous, "round_vs_majority_split", round_agree$model_vs_majority_split,
    "round_vs_individual", round_agree$model_vs_individual, "judge_vs_other_two", round_agree$judge_vs_other_two,
    "model_vs_other_two", round_agree$model_vs_other_two,
    "criteria_wald_chi2", criteria_era$wald_chi2, "criteria_wald_df", criteria_era$wald_df,
    "criteria_wald_p", criteria_era$wald_p, "criteria_wald_p_no2017", criteria_era_no2017$wald_p,
    "te_pre", ten_eight_era$pre_rate, "te_post", ten_eight_era$post_rate,
    "te_or_adj", ten_eight_era$adjusted_or, "te_or_adj_lo", ten_eight_era$adjusted_lo, "te_or_adj_hi", ten_eight_era$adjusted_hi,
    "rob_or", robbery_time$or_robbery[1], "rob_or_lo", robbery_time$or_robbery[2], "rob_or_hi", robbery_time$or_robbery[3],
    "q_or", robbery_time$or_q_or_worse[1], "q_or_lo", robbery_time$or_q_or_worse[2], "q_or_hi", robbery_time$or_q_or_worse[3],
    "rob_pre", robbery_time$pre_post$robbery[!robbery_time$pre_post$post],
    "rob_post", robbery_time$pre_post$robbery[robbery_time$pre_post$post],
    "red_pts_simple", pp(corner$simple$est[1]),
    "red_pts_full", pp(cf$est[cf$term == "(Intercept)"]),
    "red_pts_full_lo", pp(cf$est[cf$term == "(Intercept)"] - 1.96 * cf$se[cf$term == "(Intercept)"]),
    "red_pts_full_hi", pp(cf$est[cf$term == "(Intercept)"] + 1.96 * cf$se[cf$term == "(Intercept)"]),
    "red_pts_market", pp(fe$est[fe$term == "(Intercept)"]),
    "red_pts_nomarket", pp(fav_effects$corner_only$est[1]),
    "fav_pts", fav_pp(mk), "fav_pts_lo", fav_pp(mk - 1.96 * mk_se), "fav_pts_hi", fav_pp(mk + 1.96 * mk_se),
    "red_fav_share", fav_effects$red_fav_share,
    "red_mkt_win", red_market$red_win, "red_mkt_priced", red_market$red_mkt, "red_mkt_n", red_market$n,
    "odds_dec_n", odds_cov$decisions[["n"]], "odds_dec_with", odds_cov$decisions[["with_odds"]],
    "kd_head_equiv", logit_effects$head_equiv[logit_effects$feature == "d_kd"],
    "ctrl_head_equiv", logit_effects$head_equiv[logit_effects$feature == "d_ctrl_min"],
    "td_head_equiv", logit_effects$head_equiv[logit_effects$feature == "d_td_l"],
    "tdfail_head_equiv", logit_effects$head_equiv[logit_effects$feature == "d_td_fail"],
    "sub_head_equiv", logit_effects$head_equiv[logit_effects$feature == "d_sub_att"],
    "body_head_equiv", logit_effects$head_equiv[logit_effects$feature == "d_body_l"],
    "leg_head_equiv", logit_effects$head_equiv[logit_effects$feature == "d_leg_l"],
    "corner_known_from", as.numeric(CORNER_KNOWN_FROM),
    "criteria_date", as.numeric(CRITERIA_2017),
    "freeze_date", as.numeric(FREEZE_DATE)
  )
}

# Write every table the site needs; returns the file paths (a format = "file" target).
write_site_exports <- function(tables) {
  dir.create(FINAL_DIR, showWarnings = FALSE, recursive = TRUE)
  imap_chr(tables, \(df, nm) {
    path <- file.path(FINAL_DIR, paste0(nm, ".csv"))
    readr::write_csv(df, path, na = "")
    path
  }) |> unname()
}

# Judge split rates by round closeness (observed vs. correlated vs. independent).
judge_split_table <- function(triples, rho) {
  triples |>
    mutate(closeness = cut(pmin(p_a, 1 - p_a), c(0, 0.05, 0.1, 0.2, 0.3, 0.4, 0.5), include.lowest = TRUE)) |>
    group_by(closeness) |>
    summarise(n = n(), observed = mean(!unanimous),
              correlated = mean(1 - rowSums(p_k_of_3(p_a, rho)[, c(1, 4)])),
              independent = mean(1 - rowSums(p_k_of_3(p_a, 0)[, c(1, 4)])), .groups = "drop") |>
    mutate(closeness = as.character(closeness))
}

fight_calibration_table <- function(robbery_index) {
  robbery_index |> filter(winner != "draw", date >= CORNER_KNOWN_FROM) |>
    mutate(bin = cut(p_a, seq(0, 1, 0.1), include.lowest = TRUE)) |>
    group_by(bin) |> summarise(n = n(), pred = mean(p_a), obs = mean(winner == "a"), .groups = "drop") |>
    mutate(bin = as.character(bin))
}

coverage_table <- function(fight_table) {
  fight_table |> mutate(year = as.integer(format(date, "%Y"))) |>
    group_by(year) |>
    summarise(decisions = n(), round_scores = mean(has_round_scores %in% TRUE),
              media_any = mean(n_media > 0), media_mean = mean(n_media), .groups = "drop")
}

# Assemble every site table in one place (called from _targets.R).
build_site_tables <- function(robbery_index, odds, feat, dec_rounds, round_probs, mmad_judges_adj, links,
                              facts, fight_table, test_results, cv_results, rolling_results, test_calibration,
                              logit_effects, shap_xgb, triples, judge_corr, media_disagree, face_valid,
                              judge_agree, judge_tend, corner, recency, fav_effects, red_market, decision_risk,
                              robbery_market, criteria_era, ten_eight_era, robbery_time, odds_cov) {
  imp <- tibble::tibble(feature = colnames(shap_xgb$S), mean_abs = colMeans(abs(shap_xgb$S))) |>
    arrange(desc(mean_abs))
  top4 <- head(imp$feature, 4)
  ri_nd <- filter(robbery_index, winner != "draw")
  list(
    robbery_index = export_robbery_index(robbery_index, odds),
    featured_fights = feat,
    featured_rounds = featured_rounds(feat, dec_rounds, round_probs),
    featured_judges = featured_judges(feat, mmad_judges_adj, links, robbery_index),
    facts = facts,
    coverage = coverage_table(fight_table),
    model_test = test_results,
    model_cv = cv_results |> select(model, .metric, mean, std_err),
    model_rolling = rolling_results,
    model_calibration = test_calibration |> mutate(bin = as.character(bin)),
    logit_effects = logit_effects,
    shap_importance = imp,
    shap_dependence = map_dfr(top4, \(f) tibble::tibble(feature = f, value = shap_xgb$X[[f]], shap = shap_xgb$S[, f])),
    judge_split = judge_split_table(triples, judge_corr$rho),
    fight_calibration = fight_calibration_table(robbery_index),
    tiers = ri_nd |> count(tier) |> mutate(tier = as.character(tier), share = n / sum(n)),
    media_by_tier = ri_nd |> filter(coalesce(media_scored, 0L) >= MIN_MEDIA) |>
      group_by(tier) |> summarise(n = n(), media_majority_loser = mean(media_for_loser > media_scored / 2),
                                  mean_media_loser_share = mean(media_loser_share), .groups = "drop") |>
      mutate(tier = as.character(tier)),
    media_disagree = bind_rows(model_not_media = media_disagree$model_not_media,
                               media_not_model = media_disagree$media_not_model, .id = "type") |>
      select(type, date, event, winner_name, loser_name, decision_type, robbery_score, media_for_loser, media_scored, why),
    face_validity = face_valid |> mutate(tier = as.character(tier)),
    judge_agreement = judge_agree,
    judge_tendencies = as.data.frame(judge_tend),
    corner_effects = bind_rows(corner$simple |> mutate(model = "simple"), corner$full |> mutate(model = "full"),
                               corner$by_era |> mutate(model = "by_era")),
    recency = recency,
    fav_effects = bind_rows(fav_effects[c("corner_only", "with_market", "close_rounds", "full")], .id = "model"),
    red_market = red_market$by_side,
    decision_risk = decision_risk,
    robbery_market = robbery_market |> mutate(tier = as.character(tier)),
    criteria_rates = criteria_era$rates,
    criteria_interactions = criteria_era$interactions,
    ten_eight_by_year = ten_eight_era$by_year,
    robbery_by_year = robbery_time$by_year,
    odds_by_year = odds_cov$by_year,
    market_calibration = odds_cov$favourite_check |> mutate(bin = as.character(bin))
  )
}
