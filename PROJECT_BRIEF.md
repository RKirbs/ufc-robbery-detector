# Project Brief

The original project proposal, saved here word for word so later work can refer back to it.

---

# Claude Code Project Prompt: "The UFC Robbery Detector"

You are helping me (Rob Kirby, senior Economics / Finance / Business Analytics student) build a complete, portfolio-quality MMA analytics project in **R**, published as a **Quarto website** and pushed to **GitHub**. Read this entire prompt before writing any code. Work in the phases below, and **stop at each checkpoint** to show me results and wait for my approval before continuing.

---

## 1. Project Concept

A **"robbery"** in MMA is a decision where the judges award the win to the fighter who, by most reasonable measures, lost the fight.

The project will:
1. Define a robbery formally and measurably at the start of the report.
2. Build a model that predicts how judges score **rounds** from round-by-round fight statistics.
3. Use that model to estimate, for every UFC decision, the probability that the declared winner *should* have won.
4. Rank every decision from cleanest to most controversial: **the Robbery Leaderboard**.
5. Validate the model against independent media scorecards.
6. Analyze **judges**: who disagrees with the stats most, and whether judges show systematic tendencies (favoring betting favorites, champions, the red corner, etc.).
7. Test whether the **2017 judging criteria update** changed what judges reward.
8. Publish everything as a clean, reproducible GitHub repo with a Quarto site (GitHub Pages).

**Framing rule (important):** "robbery" in this project means *strong disagreement between the official result and what the statistics predict*. It is never an accusation of corruption or misconduct against any judge. Statistics cannot see everything judges see (damage that doesn't show up in strike counts, octagon control, aggression), so the report must state this limitation clearly. Judge analysis is reported as **agreement/disagreement rates with uncertainty**, never as accusations. Use neutral language throughout.

---

## 2. Scope and Time Window

- **Promotion:** UFC only.
- **Fights:** every fight that ended in a **decision** (unanimous, split, majority). Exclude draws from the main model but report them separately. Exclude no-contests and finishes from the robbery analysis (but finishes can be used for descriptive context).
- **Start date:** the earliest date from which UFCStats.com has **reliable round-by-round statistics**. Determine this in Phase 0 (likely early-to-mid 2000s). Don't guess; show me per-year data completeness.
- **End date:** the most recent completed UFC event before the project starts. Record this **freeze date** in `NOTES.md` and the methodology page so results are reproducible.

---

## 3. Data Sources (verify first, don't assume)

1. **UFCStats.com:** events, fights, results, method, rounds, and **round-by-round stats** per fighter: knockdowns, significant strikes landed/attempted (head, body, leg; distance, clinch, ground), total strikes, takedowns landed/attempted, submission attempts, reversals, control time. Also fighter records and the red/blue corner.
2. **MMADecisions.com:** official **judge-by-judge, round-by-round scorecards** (judge names and their 10-9 / 10-8 scores per round) and **media member scorecards**. Media scores are the key external validation source.
3. **BestFightOdds.com (optional, Phase 6):** historical closing moneyline odds, used to test whether judges lean toward betting favorites.
4. **Wikipedia title-history tables (optional):** to flag title fights and defending champions.

**Scraping rules:**
- Check each site's `robots.txt` and terms before scraping. If a site disallows scraping or blocks automated requests, **stop and tell me**. Do not use header spoofing or any technique to get around bot protection.
- Be polite: 1–3 second pauses between requests, retries with backoff, and **cache every raw HTML page** to `data/raw/` so nothing is downloaded twice.
- If a source is unavailable, propose alternatives (e.g., existing public Kaggle UFC datasets, community GitHub scrapes) and wait for my approval.

**Record linkage:** the three sources name fighters and events differently. Build a careful matching step (normalize names, accents, nicknames; match on event date + both fighters). Report the match rate and hand-review a sample of unmatched or low-confidence matches.

---

## 4. Tech Stack and Repo Standards

- **R** with: `tidyverse`, `rvest` + `httr2` (scraping), `polite` (robots.txt-aware scraping), `data.table` or `arrow`, `tidymodels` (modeling framework), `glmnet`, `xgboost`, `probably` (calibration), `vip` and/or `shapviz` (interpretability), `lme4` or `brms` (judge random effects), `ggplot2`, `ggrepel`, `patchwork`, `gt`, `reactable`, `quarto`.
- **`renv`** for reproducible package versions.
- **`targets`** pipeline so the whole project rebuilds with one command.
- Store raw/intermediate data as **Parquet**. Don't commit raw HTML or large intermediates (`.gitignore` them). Commit scraping/build scripts plus small final datasets so the site renders and others can reproduce.
- Short comments on every function explaining *what* and *why*. No monolithic scripts.

**Target repo structure:**
```
ufc-robbery-detector/
├── README.md
├── LICENSE                (MIT)
├── .gitignore
├── renv.lock
├── _targets.R
├── NOTES.md               (decision log, data quirks, open questions)
├── R/
│   ├── 01_scrape_ufcstats.R
│   ├── 02_scrape_mmadecisions.R
│   ├── 03_scrape_odds.R            (optional)
│   ├── 04_link_records.R
│   ├── 05_build_round_data.R
│   ├── 06_round_model.R
│   ├── 07_fight_simulation.R
│   ├── 08_robbery_index.R
│   ├── 09_validation.R
│   ├── 10_judges.R
│   ├── 11_criteria_2017.R
│   └── utils.R
├── data/
│   ├── raw/               (gitignored)
│   ├── interim/           (gitignored)
│   └── final/             (committed: small CSVs)
├── analysis/              (Quarto site source)
│   ├── _quarto.yml
│   ├── index.qmd          (landing page + definition + headline findings)
│   ├── methodology.qmd
│   ├── leaderboard.qmd    (searchable robbery leaderboard)
│   ├── fight-lookup.qmd   (round-by-round breakdown of notable fights)
│   ├── judges.qmd
│   ├── criteria-2017.qmd
│   └── validation.qmd
├── figures/
└── docs/                  (rendered site for GitHub Pages)
```

---

## 5. Defining a Robbery (top of index.qmd)

> A **robbery** is a decision in which the officially declared winner had a low probability of winning given the round-by-round statistics of the fight, as estimated by a model trained on how judges actually score rounds.

**Robbery Score** for each decision = **1 − P(declared winner wins the decision | fight stats)**.
- 0 = the stats unanimously support the result.
- Near 1 = the stats strongly favored the fighter who lost.

Define tiers (tune cutoffs after seeing the distribution, and show me at the checkpoint):
- **Clean** (score < 0.25)
- **Close / defensible** (0.25–0.50): a coin-flip fight either way.
- **Questionable** (0.50–0.75)
- **Robbery** (> 0.75)

---

## 6. Modeling

### 6a. Round-level model (the core)
Unit of analysis: **one judge's score of one round**. Outcome: which fighter that judge gave the round to (handle 10-8 rounds; treat 10-10 rounds separately or drop them, and document the choice).

Features, all as **differentials between the two fighters** for that round:
- Knockdowns
- Significant strikes landed (and accuracy), split by target (head/body/leg) and position (distance/clinch/ground)
- Total strikes landed
- Takedowns landed and attempted
- Submission attempts
- Reversals
- Control time (seconds)

**Corner symmetry (important):** UFCStats lists the red corner first, and red corner fighters are usually the favorite/champion. To avoid the model learning "red corner wins," **mirror every round** (include it once from each fighter's perspective, with differentials flipped) or randomize fighter order. Then *separately* test for a red-corner effect in the judges analysis.

**Leakage check:** only use stats from the round being scored. No fight outcome, method, or later-round information in round features.

Models (use `tidymodels`):
1. **Logistic regression** (baseline, fully interpretable: coefficients show what judges reward).
2. **Regularized logistic regression** (`glmnet`) with interactions (e.g., knockdowns × strikes).
3. **Gradient boosting** (`xgboost`).

Validation: **time-based** splits (train on earlier years, test on later years) plus grouped cross-validation by **fight** (never split rounds of the same fight across train and test). Report accuracy, log-loss, Brier score, and a calibration plot for each model against a naive baseline ("the fighter who landed more significant strikes wins the round"). Pick the final model on log-loss and calibration, not just accuracy.

Interpretability: coefficient table for the logistic model and SHAP/importance plots for xgboost. **What do judges actually reward?** This is one of the headline findings.

### 6b. Fight-level probability (simulation)
Convert round probabilities into a probability of winning the decision:
- For each fight, simulate many (e.g., 10,000) sets of **three judges' scorecards** using the round-level probabilities, including a modeled 10-8 rate.
- Account for the fact that judges' scores on the same round are correlated (they watch the same fight). Estimate that correlation from the data and include it in the simulation, rather than treating judges as independent.
- Output: P(fighter A wins), P(draw), P(fighter B wins).
- Compare against a simpler direct fight-level model as a sanity check.

### 6c. Robbery Index
Compute the Robbery Score for every decision, assign tiers, and produce the **all-time leaderboard** with: event, date, fighters, official result (with each judge's scorecard), model probabilities, robbery score, % of media scorecards that favored the loser, and a one-line data-driven explanation of *why* the model disagrees (e.g., "Loser won the significant strike differential in all 3 rounds, +41 total").

---

## 7. Validation (validation.qmd)

1. **Media scorecards (key test):** correlate the Robbery Score with the share of media members who scored the fight for the official loser. A good model should strongly agree with media consensus. Report correlation with confidence intervals and a scatterplot, and list the biggest disagreements between the model and the media (these are interesting in their own right).
2. **Round-level agreement:** how often does the model's predicted round winner match the majority of judges? Of media members?
3. **Face validity:** check that famously disputed decisions show up near the top and clearly one-sided decisions sit at the bottom. If something obviously wrong appears, check for a data bug before calling it a finding.
4. **Calibration** of fight-level probabilities: among fights the model gave a 70% chance, does the favored fighter win about 70% of the time?

---

## 8. Judge Analysis (judges.qmd)

All judge results must use **minimum sample sizes** (e.g., ≥ 100 rounds scored) and **shrinkage** (mixed-effects model with judge random effects, or empirical Bayes) so small samples don't produce extreme rankings. Always show uncertainty intervals.

1. **Agreement rate:** how often each judge agrees with the model's predicted round winner, adjusted for how close the rounds they judged were (judges who get many close rounds will naturally "disagree" more).
2. **Judge tendencies** via a mixed model: do individual judges systematically weight grappling/control time vs. striking more than average?
3. **Systematic biases (league-wide and by judge), controlling for round stats:**
   - **Betting favorite** effect (requires odds data): do judges lean toward the pre-fight favorite in close rounds?
   - **Champion / title fight** effect.
   - **Red corner** effect.
   - **Late-round recency:** does the final round carry extra weight in how a fight is scored overall?
4. Report findings neutrally: "Judge X agrees with the statistical model less often than average," never "Judge X is bad/biased/corrupt."

---

## 9. The 2017 Judging Criteria Update (criteria-2017.qmd)

In 2017 the Association of Boxing Commissions updated MMA judging criteria to emphasize **effective striking/grappling** first, with effective aggressiveness and octagon control as secondary tiebreakers, and clarified when 10-8 rounds should be given. Verify the exact effective date and details with a quick source check and cite it.

- Fit the round model with **era interactions** (pre vs. post criteria change) to test whether the weights judges give to control time, takedowns, and strikes shifted.
- Test whether the **10-8 round rate** changed.
- Test whether robbery rates changed over time (plot the robbery-tier share by year).
- Keep the interpretation careful: other things also changed over this period (fighter styles, the athletic commissions involved), so describe these as associations and discuss alternatives.

---

## 10. Optional Extension: Betting Markets (Phase 6)

If odds data is obtainable:
- Do judges favor the betting favorite in close fights (see section 8)?
- Does the market price **decision risk**? For example, are fighters who tend to "win on the cards" despite losing stats systematically under- or over-valued?

---

## 11. Visual Standards

- One consistent `ggplot2` theme in `R/utils.R`, clean and minimal, readable at phone width.
- **Signature chart:** for a featured robbery, a round-by-round breakdown showing each fighter's stats per round alongside how each judge and the model scored each round.
- Additional key charts: the robbery score distribution, "what judges reward" coefficient chart, robbery rate by year with the 2017 change annotated, media-vs-model scatterplot.
- Every chart has a title, a subtitle stating the takeaway, labeled axes with units, and a source caption ("Data: UFCStats, MMADecisions; analysis by Rob Kirby").
- Save all figures to `figures/` as PNG and embed in Quarto.

---

## 12. Report Narrative

The site should read like strong data journalism / an analyst portfolio piece, not a code dump:
1. **Landing page:** hook, the robbery definition, the signature chart for the #1 robbery, 3–5 headline findings, links to each section.
2. **Methodology:** sources, linkage, the round model, the simulation, the robbery score, limitations (stats can't see damage or octagon control; incomplete early data; scorecard availability; correlated judges).
3. **Leaderboard:** searchable/sortable `reactable` table of every decision, plus `gt` tables of the **Top 25 robberies** and a short write-up of the top 10.
4. **Fight lookup:** detailed round-by-round breakdowns of ~10 notable fights (top robberies plus a few famous "close but fair" decisions).
5. Judges → 2017 Criteria → Validation.
6. Code folded by default (`code-fold: true`).

---

## 13. README.md

Include: title + one-line pitch, the signature chart, the robbery definition, headline findings, link to the live GitHub Pages site, methods summary, data sources + credits, the framing note on judges, exact reproduction steps (`renv::restore()`, then `targets::tar_make()`), repo structure, limitations, and author contact.

---

## 14. Phases and Checkpoints

**Phase 0: Data Audit (CHECKPOINT)**
Check `robots.txt`/terms and availability for every source. Report: per-year completeness of round-level stats on UFCStats, judge scorecard and media scorecard coverage on MMADecisions, estimated number of decision fights and rounds, estimated scrape time, and real example rows from each source. Recommend the start year. **Wait for approval.**

**Phase 1: Project scaffold**
Repo structure, `renv`, `targets`, `.gitignore`, `utils.R` theme, `NOTES.md`, git init and first commit.

**Phase 2: Scrape, clean, link (CHECKPOINT)**
Scrape and cache everything. Build the round-level and fight-level tables. Report record-linkage match rates and a hand-checked sample. **Wait for approval.**

**Phase 3: Round model (CHECKPOINT)**
Train and evaluate all three models. Show the baseline comparison, calibration plots, and the "what judges reward" results. **Wait for approval.**

**Phase 4: Simulation + Robbery Index (CHECKPOINT)**
Show the judge-correlation estimate, the robbery score distribution, proposed tier cutoffs, and the top/bottom 25. **Wait for approval before writing the narrative.**

**Phase 5: Validation + judges + 2017 criteria (CHECKPOINT)**
Show results. **Wait for approval.**

**Phase 6: Optional betting extension** (ask me first whether to do it)

**Phase 7: Quarto site + README**
Render locally, check every page, and fix broken charts or tables. (Quarto must be installed; tell me if it isn't.)

**Phase 8: GitHub (CHECKPOINT)**
Make clean, meaningful commits throughout. At the end, help me create the GitHub repo (`ufc-robbery-detector`), push, and enable GitHub Pages from `/docs`. **Ask me before pushing anything or creating the remote repo.**

---

## 15. Working Rules

- Ask me before any long download or scrape (> 15 minutes) or anything that costs money.
- If a data limitation forces a design change, explain the tradeoff and propose options rather than silently changing the method.
- Never hard-code results into the narrative. Every number in the report is computed inline from the data.
- When a result looks surprising, check for a data bug before calling it a finding.
- Keep `NOTES.md` updated with decisions, data quirks, and open questions.
