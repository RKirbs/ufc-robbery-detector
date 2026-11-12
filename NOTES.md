# NOTES: decision log, data quirks, open questions

## Decision log
- **2026-11-11. Freeze date: 2026-11-07** (UFC Fight Night: Cortes Acosta vs. Walker, the latest completed event in the data on the audit date).
- **2026-11-11. Start date: 2001-01-01.** This is the first full year after the UFC adopted the Unified Rules (UFC 28, Nov 2000); control time is recorded from 2000 and judge totals mostly from 2001. Rob didn't object to the Phase 0 recommendation. Plan a sensitivity check that starts in 2005.
- **2026-11-11. UFCStats source: the Greco1899/scrape_ufc_stats mirror,** pinned to commit `c742842f29466758fedc3906dbad28d6d320a8da` (approved by Rob). UFCStats.com itself serves a JavaScript proof-of-work bot challenge, which we don't bypass. The mirror is GPL-3.0, so we download it at build time and don't commit its files.
- **2026-11-11. MMADecisions: permission granted.** Its robots.txt disallows generic bots (`User-agent: * / Disallow: /`). Rob contacted the site owner, who said the data may be used and collected from the site (they won't send an export). We scrape politely and slowly with an honest user agent and cache every page. *Rob: keep a copy of that message with the project records.*
- **2026-11-11. MMADecisions supplies both the model outcome and the validation set:** judge round-by-round scores and media scorecards. This restores the original design in the brief (sections 6a and 7).
- **2026-11-11. Tooling:** Quarto 1.11.9 is installed at `~/opt/quarto-1.11.9`, with no admin rights needed. The project `.Renviron` sets `QUARTO_PATH`. A shell PATH entry was not added (Rob can add it; see the README).

## Data quirks
- 3 event names differ between the Greco results and events files ("Noche UFC" vs. "UFC Fight Night", and "UFC - Road to UFC 4.6"). Join on URLs.
- Judge names have spelling/case variants in UFCStats (for example "Sal D'amato"); 43 decisions have an empty judge-name token. MMADecisions has stable judge IDs, so prefer those.
- The UFCStats `DETAILS` judge totals seem to be oriented to the *first-listed* fighter, which isn't always the winner (Suarez vs. Jandiroba shows 27-30 for the winner). Don't rely on them; use the MMADecisions cards.
- Judge totals are missing in UFCStats for 1995–2000 and partly missing for 2001–2002.
- Control time is missing for every decision before 1999 and for about half in 1999.
- MMADecisions dates can differ from UFCStats by a day for events outside the Americas, so match events within ±1 day.
- On MMADecisions, fighter 1 (listed on top) is the declared winner; score columns are (fighter 1, fighter 2).

- **MMADecisions round-score coverage is partial before about 2013.** Older pages show "-" for every round but still give each judge's card total. Missing share among the first 1,000 pages: 100% for 2001–05, about 94% for 2006–07, 75% for 2008, about 61% for 2009–10, 29% for 2011, 20% for 2012, about 10% from 2013 on. Totals are present for every card. Twelve very old cards show placeholder totals ("1-0", "0-0"); exclude them.
- 2 MMADecisions decisions (Eye vs. Kaufman 2013, Siver vs. Gamburyan 2013) were later overturned to no-contests; UFCStats records them as "Overturned", so they correctly don't link.
- Aliases resolved by the "medium" link tier (all hand-checked correct in the first 1,000 pages): Kimbo Slice = Kevin Ferguson; John Macapa = John Teixeira; Bubba McDaniel = Robert McDaniel; Kevin Souza = Edimilson Souza; William Patolino = William Macario.

- **2026-11-12. Phase 2 complete:** 4,123 MMADecisions pages; 4,109 of 4,109 UFCStats decisions linked; winner agrees in all 4,109; 33,482 judge-round scores. See PHASE2_REPORT.md.
- 14 MMADecisions decisions were later overturned (mostly to no-contests after failed drug tests, e.g. Silva vs. Diaz, Lesnar vs. Hunt, Price vs. Cerrone). They're excluded because UFCStats marks them "Overturned".
- UFCStats lists Maheshate by a single name. The matcher's mononym rule handles him.
- Drop at modeling time: the 19 judge cards whose round count differs from UFCStats, the 1 card whose round scores don't sum to its total, and the 4 fights with placeholder totals.
- `vip` has been removed from CRAN; use `shapviz` and xgboost's built-in feature importance instead.

- **2026-11-12. Modeling design: Option A (approved by Rob).** The round model is trained only on rounds with judge round scores (33,482 judge-rounds, mostly 2011+). It's applied to all 4,109 decisions. For totals-only fights (mostly pre-2011), the judges' card totals are used only as an out-of-sample check, not for training.

- **2026-11-12. Round model choices (Phase 3):**
  - 10-10 rounds (163 judge-rounds) are dropped from the winner model and handled in the Phase 4 simulation; 10-8 rounds count as wins, and a separate model predicts P(10-8 | winner).
  - Training rows are mirrored and predictions symmetrised, p = [p(x) + 1 − p(−x)] / 2.
  - Significant strikes enter by target. Clinch and ground enter as premiums over distance, because target and position each sum to the significant-strike total.
  - Accuracy is smoothed as (landed + 1) / (attempted + 2).
  - Time split: train 2006–2019, test 2020–2026, plus rolling-origin tests and grouped 5-fold CV by fight.
  - `CRITERIA_2017 = 2017-01-01` is provisional; verify and cite it in Phase 5.
- **2026-11-12. Phase 3 result:**
  - All three models beat the baseline (test log-loss about 0.38 against 0.55).
  - glmnet has the best log-loss, but xgboost is best calibrated, because linear models can't capture judges' diminishing returns past about +20 head strikes.
  - Recommended final model: xgboost, with glmnet as a sensitivity check. **Awaiting Rob's approval.**
- Check for Phase 4: the robbery scores for fights whose judges were in the training data should use out-of-fold round predictions (grouped by fight). Otherwise the model has partly learned those very cards, which would understate disagreement.

- **2026-11-12. Rob approved Phase 3:** xgboost is the final round model (glmnet as a sensitivity check); keep the every-factor breakdown of what judges reward.
- **2026-11-12. Data bug fixed: point deductions.** MMADecisions round scores include deductions (109 deductions in 105 fights, parsed from the "X was deducted N point(s) in round R" text).
  - Before the fix, 138 of 163 apparent 10-10 judge-rounds were really 10-9s with the winner deducted, and some 10-8s were 10-9s with the loser deducted.
  - Deducted points are now added back for modeling (official scores kept in `score_f*_official`). 3 cards where restoring would give 11-9 keep their official score.
  - The simulation subtracts deductions from simulated cards. Phase 3 was rerun; its conclusions are unchanged.
- **2026-11-12. Simulation design (Phase 4):**
  - Judge calls are latent normals with a shared round factor: ρ = 0.61 (CI 0.58–0.63) by maximum likelihood on split rates. 10-8s use the same approach with ρ₈ = 0.60.
  - 10-10s come from a logistic model on round closeness and era.
  - Out-of-fold round probabilities (10-fold, grouped by fight) for every fight the round model trained on.
  - 10,000 simulated sets of three cards per fight; a fighter wins with at least 2 cards.
- **Observation for Phase 5:** red corners won 61.4% of decisions vs. 57.1% simulated (the model is corner-symmetric). Test this in the judge analysis; don't call it a finding yet.
- **Phase 4 checkpoint:** proposed tiers are the brief's 0.25 / 0.50 / 0.75 (225 robbery-tier fights, 5.6%). Recommendation: don't tune cutoffs on media (media are the Phase 5 validation set). Awaiting Rob.
- Data caveat: pre-2008 stats were coded from video after the fact, and some early fights have 0–2 media scores. Proposal: flag them as "limited corroboration" on the leaderboard.

## Open questions
- Use the BestFightOdds odds extension (Phase 6)? Ask before scraping (about 30–45 min).
