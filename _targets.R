# _targets.R: the reproducible pipeline. Run with targets::tar_make().
#
# The slow MMADecisions download lives in scripts/run_mmad_scrape.R and writes
# cached HTML to data/raw/mmadecisions/. This pipeline only parses that cache,
# so rebuilding never re-contacts the site.

library(targets)
library(tarchetypes)

tar_option_set(packages = c("dplyr", "tidyr", "purrr", "stringr", "readr",
                            "tibble", "rvest", "arrow", "lubridate"))

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
             write_parquet_target(fight_table, "data/interim/fight_table.parquet"), format = "file")
)
