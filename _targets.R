# _targets.R: the reproducible pipeline. Run with targets::tar_make().
#
# The slow MMADecisions download lives in scripts/run_mmad_scrape.R and writes
# cached HTML to data/raw/mmadecisions/. This pipeline only parses that cache,
# so rebuilding never re-contacts the site.

library(targets)
library(tarchetypes)

tar_option_set(packages = c("dplyr", "tidyr", "purrr", "stringr", "readr",
                            "tibble", "rvest", "arrow", "lubridate",
                            "recipes", "parsnip", "workflows", "tune", "yardstick", "rsample"))

# Load every function file in R/ (utils first, then numbered stages).
for (f in c("R/utils.R", sort(setdiff(list.files("R", "\\.R$", full.names = TRUE), "R/utils.R")))) source(f)

list(
  # ---- Stage 1: UFCStats (Greco1899 mirror) ---------------------------------
  tar_target(greco_paths, get_greco_files(), format = "file"),
  tar_target(greco, read_greco(greco_paths)),

  # ---- Stage 2: MMADecisions (parse cached pages) ----------------------------
  tar_target(mmad_files,
             list.files(file.path(MMAD_RAW, "decisions"), "\\.html$", full.names = TRUE),
             cue = tar_cue(mode = "always")),
  tar_target(mmad_parsed, parse_all_decisions(mmad_files)),
  tar_target(mmad_deductions, mmad_parse_deductions(mmad_files)),
  # Judges' round scores with deducted points added back (official scores kept).
  tar_target(mmad_judges_adj, restore_deductions(mmad_parsed$judges, mmad_deductions, mmad_parsed$fight)),
  tar_target(mmad_fights_file, write_parquet_target(mmad_parsed$fight,  "data/interim/mmad_fights.parquet"),  format = "file"),
  tar_target(mmad_judges_file, write_parquet_target(mmad_parsed$judges, "data/interim/mmad_judge_rounds.parquet"), format = "file"),
  tar_target(mmad_media_file,  write_parquet_target(mmad_parsed$media,  "data/interim/mmad_media.parquet"),  format = "file"),
  tar_target(mmad_totals_file, write_parquet_target(mmad_parsed$judge_totals, "data/interim/mmad_judge_totals.parquet"), format = "file"),

  # ---- Stage 3: clean UFCStats into fights + round stats ---------------------
  tar_target(ufc_fights, clean_greco_fights(greco) |>
               filter(date >= START_DATE, date <= FREEZE_DATE)),
  tar_target(round_stats, clean_greco_round_stats(greco, ufc_fights)),
  tar_target(rs_wide, round_stats_wide(round_stats)),

  # ---- Stage 4: record linkage ----------------------------------------------
  tar_target(links, link_mmad_ufcstats(mmad_parsed$fight, ufc_fights)),
  tar_target(link_report, linkage_report(links, mmad_parsed$fight)),

  # ---- Stage 5: judge x round modeling table --------------------------------
  tar_target(judge_rounds, build_judge_rounds(mmad_judges_adj, links, rs_wide, ufc_fights)),
  tar_target(judge_rounds_file,
             write_parquet_target(judge_rounds, "data/interim/judge_rounds.parquet"), format = "file"),
  tar_target(fight_table, build_fight_table(mmad_parsed, links, ufc_fights)),
  tar_target(fight_table_file,
             write_parquet_target(fight_table, "data/interim/fight_table.parquet"), format = "file"),

  # ---- Stage 6: round model (Phase 3) ---------------------------------------
  # Faulty cards and 10-10 rounds are flagged in model_data and dropped here.
  tar_target(model_data, prep_model_data(judge_rounds, ufc_fights, mmad_parsed)),
  tar_target(model_ok, filter(model_data, is.na(drop_reason))),
  tar_target(train_rounds, filter(model_ok, split == "train")),   # before TEST_START
  tar_target(test_rounds, filter(model_ok, split == "test")),
  tar_target(train_mirrored, mirror_rounds(train_rounds) |> select(all_of(model_cols))),
  tar_target(round_wfs, make_workflows(train_mirrored)),
  # Grouped CV by fight: both mirrored copies and all judges/rounds of a fight
  # stay in the same fold.
  tar_target(cv_folds, make_folds(train_mirrored, v = 5)),
  tar_target(round_tuned, tune_round_models(round_wfs, cv_folds)),
  tar_target(cv_results, cv_summary(round_tuned, cv_baseline(cv_folds))),
  tar_target(round_wfs_final, finalize_round_workflows(round_wfs, round_tuned)),
  # Time-based test: fit on the training years, score the test years.
  tar_target(train_fits, fit_round_workflows(round_wfs_final, train_rounds)),
  tar_target(test_preds, predict_all_models(train_fits, test_rounds)),
  tar_target(test_results, test_metrics(test_preds, reps = 500)),
  tar_target(test_calibration, calibration_table(test_preds)),
  # Rolling origin: train on all years before Y, test on Y.
  tar_target(rolling, rolling_preds(round_wfs_final, model_ok)),
  tar_target(rolling_results, rolling |> group_by(model, year) |>
               group_modify(\(d, k) score_probs(d$y, d$p_a)) |> ungroup()),
  # Interpretation and final fits on all rounds.
  tar_target(logit_effects, logistic_effects(model_ok)),
  tar_target(final_fits, fit_round_workflows(round_wfs_final, model_ok)),
  tar_target(shap_xgb, xgb_shap(final_fits$xgboost, model_ok, n = 4000)),
  # 10-8 model (P(10-8 | judge's winner)).
  tar_target(ten_eight_data, prep_ten_eight(model_data)),
  tar_target(ten_eight_cv_res, ten_eight_cv(ten_eight_data)),
  tar_target(ten_eight_model, fit_ten_eight(ten_eight_data)),

  # ---- Stage 7: simulation + Robbery Index (Phase 4) ---------------------------
  tar_target(dec_rounds, decision_rounds(fight_table, rs_wide)),
  # Out-of-fold round probabilities for fights the model trained on.
  tar_target(round_probs, oof_round_probs(round_wfs_final$xgboost, model_ok, dec_rounds, final_fits$xgboost)),
  tar_target(triples, judge_round_triples(model_data, round_probs)),
  tar_target(judge_corr, estimate_judge_corr(triples)),
  tar_target(q8, ten_eight_probs(ten_eight_model, dec_rounds)),
  tar_target(ten_eight_corr, estimate_ten_eight_corr(triples, q8)),
  tar_target(ten_ten_model, fit_ten_ten(model_data, round_probs)),
  tar_target(deductions_fight, fight_deductions(mmad_deductions, mmad_parsed$fight, links)),
  tar_target(sims, simulate_all(dec_rounds, round_probs, q8, ten_ten_model,
                                judge_corr$rho, ten_eight_corr$rho8, deductions_fight)),
  tar_target(stat_summary, fight_stat_summary(dec_rounds, round_probs)),
  tar_target(robbery_index, build_robbery_index(fight_table, sims, stat_summary, deductions_fight)),
  tar_target(robbery_index_file,
             write_parquet_target(robbery_index, "data/interim/robbery_index.parquet"), format = "file"),
  # Sensitivity: the same pipeline with glmnet round probabilities.
  tar_target(round_probs_glmnet,
             oof_round_probs(round_wfs_final$glmnet, model_ok, dec_rounds, final_fits$glmnet)),
  tar_target(judge_corr_glmnet, estimate_judge_corr(judge_round_triples(model_data, round_probs_glmnet), reps = 50)),
  tar_target(sims_glmnet, simulate_all(dec_rounds, round_probs_glmnet, q8, ten_ten_model,
                                       judge_corr_glmnet$rho, ten_eight_corr$rho8, deductions_fight)),
  # Sanity checks: a direct fight-level model, and judges' card totals.
  tar_target(fight_direct, fight_level_check(dec_rounds, fight_table)),
  tar_target(card_check, card_total_check(mmad_parsed, links, sims, fight_table)),

  # ---- Stage 8: validation, judges, 2017 criteria (Phase 5) ----------------------
  tar_target(media_valid, media_validation(robbery_index)),
  tar_target(media_disagree, media_disagreements(robbery_index)),
  tar_target(round_agree, round_agreement(model_data, round_probs)),
  tar_target(face_valid, face_validity(robbery_index)),
  tar_target(fighter_exp, fighter_experience(greco)),
  tar_target(judge_table, judge_round_table(model_data, round_probs, fighter_exp)),
  tar_target(judge_agree, judge_agreement(judge_table)),
  tar_target(judge_tend, judge_tendencies(judge_table, logit_effects)),
  tar_target(corner, corner_effects(judge_table)),
  tar_target(recency, recency_test(robbery_index, round_probs)),
  tar_target(criteria_era, criteria_era_model(model_data)),
  tar_target(criteria_era_no2017, criteria_era_model(model_data, drop_2017 = TRUE)),
  tar_target(ten_eight_era, ten_eight_trend(ten_eight_data)),
  tar_target(robbery_time, robbery_trend(robbery_index)),

  # ---- Stage 9: betting odds (Phase 6) ---------------------------------------------
  # Cached BestFightOdds fighter pages (fetched by scripts/run_bfo_scrape.R).
  tar_target(bfo_files, list.files(file.path(BFO_RAW, "fighters"), "\\.html$", full.names = TRUE),
             cue = tar_cue(mode = "always")),
  tar_target(bfo_raw, bfo_parse_all(bfo_files)),
  tar_target(bfo_m, bfo_matchups(bfo_raw)),
  tar_target(odds, link_odds(bfo_m, ufc_fights)),
  tar_target(odds_file, write_parquet_target(odds, "data/interim/odds.parquet"), format = "file"),
  tar_target(odds_cov, odds_coverage(odds, fight_table, ufc_fights)),
  tar_target(fav_effects, favourite_effects(judge_table, odds)),
  tar_target(decision_risk, decision_risk_test(ufc_fights, odds, robbery_index)),
  tar_target(robbery_market, robbery_vs_market(robbery_index, odds)),
  tar_target(red_market, red_vs_market(ufc_fights, odds))
)
