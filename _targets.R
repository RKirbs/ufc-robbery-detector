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
  tar_target(mmad_media_file,  write_parquet_target(mmad_parsed$media,  "data/interim/mmad_media.parquet"),  format = "file")
)
