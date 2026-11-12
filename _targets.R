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
  tar_target(judge_rounds, build_judge_rounds(mmad_parsed$judges, links, rs_wide, ufc_fights)),
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
  tar_target(ten_eight_model, fit_ten_eight(ten_eight_data))
)
