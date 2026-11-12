# build_readme.R: write README.md and the README signature chart from the
# committed data in data/final/, so no number in the README is typed by hand.
# Run after targets::tar_make():  Rscript scripts/build_readme.R

suppressPackageStartupMessages({ library(dplyr); library(readr); library(ggplot2); library(glue) })
source("R/utils.R"); source("R/11_site_plots.R")

rd <- function(name) read_csv(file.path("data/final", paste0(name, ".csv")), show_col_types = FALSE)
facts <- rd("facts"); fx <- function(k) facts$value[facts$key == k]
pct <- function(x, acc = 1) scales::percent(x, accuracy = acc)
num <- function(x, d = 1) formatC(x, format = "f", digits = d, big.mark = ",")
pts <- function(x) sprintf("%+.1f", x)

ri <- rd("robbery_index") |> filter(winner != "draw")
tb <- rd("tiers"); cr <- rd("criteria_rates"); fv <- rd("face_validity")
t1 <- ri |> slice_max(robbery_score, n = 1)
rounds <- rd("featured_rounds"); judges <- rd("featured_judges")
rob_n <- tb$n[tb$tier == "Robbery"]; rob_share <- tb$share[tb$tier == "Robbery"]
g <- \(f, e) cr$head_equiv[cr$feature == f & cr$era == e]
top5 <- ri |> arrange(desc(robbery_score)) |> head(5) |>
  mutate(line = sprintf("| %d | %s def. %s | %s | %.3f | %s |", row_number(), winner_name, loser_name,
                        format(date, "%Y"), robbery_score,
                        ifelse(coalesce(media_scored, 0) > 0, paste0(media_for_loser, " of ", media_scored), "–")))

# Signature chart for the README.
p <- plot_fight_breakdown(t1, filter(rounds, fight_url == t1$fight_url), filter(judges, fight_url == t1$fight_url))
save_fig(p, "signature_chart", width = 9, height = 8.5, dpi = 150)

readme <- glue('
# The UFC Robbery Detector

**Which UFC decisions did the statistics say went to the wrong fighter?** A model trained on {num(fx("n_judge_rounds"), 0)} real judges\' round scores, plus a simulation of correlated judges, scores every UFC decision since 2001.

**Live site:** https://rkirbs.github.io/ufc-robbery-detector/

![Round-by-round breakdown of the decision with the highest Robbery Score](figures/signature_chart.png)

## What "robbery" means

> A **robbery** is a decision in which the officially declared winner had a low probability of winning given the round-by-round statistics of the fight, as estimated by a model trained on how judges actually score rounds.

**Robbery Score = 1 − P(declared winner wins the decision | fight stats).** It measures *disagreement between the statistics and the result*. It is **never an accusation** of judge misconduct: statistics can\'t see damage, power, octagon control or aggression.

## Headline findings

- **1 in {round(1 / rob_share)} decisions is a statistical "robbery".** {num(rob_n, 0)} of {num(nrow(ri), 0)} decisions ({pct(rob_share, 0.1)}) score at least 0.75. {sum(fv$pct_rank >= 0.84)} of {nrow(fv)} widely debated decisions rank in the top 16%.
- **What judges reward:** a knockdown is worth about {num(fx("kd_head_equiv"), 0)} significant head strikes, a minute of control {num(fx("ctrl_head_equiv"), 1)}, and a takedown {num(fx("td_head_equiv"), 1)}. A missed takedown *costs* {num(abs(fx("tdfail_head_equiv")), 2)}.
- **The model agrees with the media almost as often as the judges do** ({pct(fx("model_agrees_media"))} vs. {pct(fx("official_agrees_media"))} agreement with the media majority). The Robbery Score correlates with media disagreement at r = {num(fx("media_r"), 2)}.
- **Judges lean slightly toward the red corner ({pts(fx("red_pts_full"))} pts on a 50/50 round) and the betting favourite ({pts(fx("fav_pts"))} pts for a −300 favourite).** Adjusted for round difficulty, individual judges agree with the stats at very similar rates.
- **The 2017 criteria changed what judges reward** (knockdown {num(g("d_kd", "Before 2017"), 0)} → {num(g("d_kd", "2017-2026"), 0)} head strikes; takedown {num(g("d_td_l", "Before 2017"), 1)} → {num(g("d_td_l", "2017-2026"), 1)}), **but not how often decisions go "wrong".**

| # | Decision | Year | Robbery Score | Media for loser |
|---|---|---|---|---|
{paste(top5$line, collapse = "\n")}

## Methods in brief

1. **Data.**
   - Round-by-round fight statistics from UFCStats, via the [Greco1899/scrape_ufc_stats](https://github.com/Greco1899/scrape_ufc_stats) mirror.
   - Every judge\'s round-by-round scorecard, plus media scorecards, from [MMADecisions](https://mmadecisions.com), collected with the owner\'s permission.
   - Closing betting lines from [BestFightOdds](https://www.bestfightodds.com).
   - In all: {num(fx("n_decisions"), 0)} decisions, {num(fx("n_media_scores"), 0)} media scores.
2. **Round model.**
   - Predicts which fighter a judge gives each round, from that round\'s A-minus-B stat differentials only.
   - Training rounds are mirrored, so the model can\'t learn "red corner wins".
   - Logistic, glmnet and xgboost models (tidymodels), compared with grouped cross-validation by fight, a 2020–2026 time-based test, log-loss, Brier score and calibration. Final model: xgboost.
3. **Simulation.**
   - 10,000 sets of three judges per fight.
   - Judges are correlated (latent correlation {num(fx("rho"), 2)}, estimated from how often real judges split), with modelled 10-8 and 10-10 rounds and point deductions.
   - Uses out-of-fold round probabilities, so no fight\'s own scorecards inform its own score.
4. **Validation.** Media scorecards, round-level agreement, face validity and calibration.
5. **Judges.** Mixed models with judge random effects (shrinkage), a minimum of 100 rounds per judge, and intervals throughout.

## Reproduce it

```r
renv::restore()          # exact package versions
targets::tar_make()      # parse cached data, fit models, simulate, export data/final/
```
```bash
quarto render analysis/  # build the site into docs/
Rscript scripts/build_readme.R
```

The slow, polite collectors live in `scripts/run_mmad_scrape.R` and `scripts/run_bfo_scrape.R`. They cache every page to `data/raw/`, which is gitignored. The UFCStats mirror is downloaded at build time.

## Repository structure

```
R/                 pipeline functions (01 UFCStats … 11 site plots, utils.R)
_targets.R         the pipeline
scripts/           collectors, checkpoint reports, README builder
analysis/          Quarto site source
docs/              rendered site (GitHub Pages)
data/final/        small committed datasets the site reads
figures/           PNG figures
NOTES.md           decision log, data quirks, open questions
PHASE*_REPORT.md   checkpoint reports
```

## Limitations

- **Statistics can\'t see everything.** Damage, power, a fighter being hurt without a knockdown, and octagon control are invisible to the counts.
- **Early data are thinner.** Scorecards before 2011 are sparse, and earlier stats were coded from video after the fact. Those entries are flagged "limited corroboration".
- **Corner order.** UFCStats lists the red corner first only from March 2010, so corner analyses start there.
- **Associations, not causes.** Every judge, era and betting-market comparison is observational.

## Data and credits

- **UFCStats.com** fight statistics, via the Greco1899 mirror (GPL-3.0; downloaded at build time, not redistributed).
- **MMADecisions.com** judge and media scorecards, used with permission.
- **BestFightOdds.com** historical odds.

Code is released under the MIT License.

## Author

Rob Kirby: Economics, Finance & Business Analytics · GitHub: [@rkirbs](https://github.com/rkirbs)
')
writeLines(readme, "README.md")
cat("README.md and figures/signature_chart.png written\n")
