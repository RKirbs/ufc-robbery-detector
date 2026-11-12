# Phase 3: Round Model

**Date:** 2026-11-12
**Status:** Approved by Rob on 2026-11-12. The final round model is xgboost, and the full breakdown of what judges reward is kept.

> **Update, 2026-11-12 (Phase 4 data fix):** MMADecisions round scores include point deductions. That turned 138 judge-rounds into fake "10-10"s (a 10-9 with a point taken from the round's winner reads 9-9) and inflated the number of 10-8s. Deducted points are now added back before modeling, and every number below has been recomputed. The conclusions didn't change.

Every number below comes from `Rscript scripts/phase3_report.R`, run after `targets::tar_make()`. Figures are in `figures/p3_*.png`.

## 1. Setup
- **Unit:** one judge's score of one round. **Outcome:** the fighter that judge gave the round to.
- **Data (Option A):** 33,444 judge-rounds in 3,620 fights, from 2006 to 2026. Dropped:
  - 25 genuine 10-10 judge-rounds (0.07%). These are set aside here and modeled in the Phase 4 simulation.
  - 13 judge-rounds from the faulty cards found in Phase 2.
- **Features:** A − B differentials for the round being scored only, so nothing leaks in from the fight result, the method or other rounds:
  - knockdowns;
  - significant strikes by target (head, body, leg), plus a clinch premium and a ground premium (distance strikes are the reference);
  - non-significant strikes;
  - significant-strike accuracy;
  - takedowns landed and failed takedown attempts;
  - submission attempts and reversals;
  - control time.

  xgboost also sees round pace (total significant strikes by both fighters).
- **Corner symmetry:**
  - The training rows are mirrored, so every round appears once from each fighter's side.
  - Every prediction is symmetrised: swapping the fighters gives exactly 1 − p (checked numerically).
  - So no model can learn "red corner wins". In the raw data the red corner wins 58% of judge-rounds. That gets tested in Phase 5, controlling for stats.
- **Validation:**
  - (a) Grouped 5-fold cross-validation by fight on the training years, used for tuning.
  - (b) A **time-based test**: train on 2006–2019 (17,096 judge-rounds, 1,911 fights), test on 2020–2026 (16,348 judge-rounds, 1,709 fights).
  - (c) A **rolling-origin** test: each year from 2020 to 2026 is predicted by models trained only on earlier years.

  Confidence intervals come from bootstrapping over fights.

## 2. Results (time-based test, 2020–2026)

| Model | Log-loss | Brier | Accuracy | Worst calibration bin |
|---|---|---|---|---|
| Baseline: significant-strike leader wins | 0.551 | 0.183 | 75.2% | 5.2 pts |
| Logistic | 0.383 | 0.122 | 82.8% | 8.4 pts |
| glmnet (regularized, with interactions) | **0.376** | **0.121** | **83.1%** | 9.4 pts |
| xgboost | 0.381 | 0.123 | 82.5% | **6.3 pts** |

- All three models beat the baseline by a wide margin. The log-loss improvement over the baseline is 0.16 to 0.19 (95% CI) for every model.
- The three models are close to each other:
  - glmnet beats xgboost on log-loss by 0.005 (95% CI 0.002 to 0.007), about 1%.
  - Logistic is 0.003 worse than xgboost (CI −0.000 to 0.007).
- Grouped CV on the training years gives the same ordering (log-loss: glmnet 0.365, logistic 0.368, xgboost 0.371, baseline 0.539).
- The rolling-origin results are stable from year to year: log-loss is 0.35–0.40 for the models and 0.52–0.56 for the baseline (`p3_logloss_by_year.png`).

**Calibration** (`p3_calibration.png`):
- The two linear models are slightly S-shaped. When they predict about 55%, judges give the round to that fighter about 64–65% of the time, and the tails run a little overconfident.
- xgboost tracks the diagonal more closely.
- The SHAP plots show why. Judges' reward for a strike lead **flattens out at about +20 significant head strikes**, because by then the round is already won. A linear model can't flatten out.

### Decision: xgboost is the final round model (approved)
The brief says to pick on log-loss *and* calibration:
- xgboost gives up about 1% of log-loss to glmnet but has a much smaller worst-bin calibration error (6.3 vs. 9.4 points).
- Calibration matters more here, because Phase 4 combines round probabilities across rounds and judges, so a systematic error in close rounds adds up. Close rounds are exactly where disputed decisions come from.

I'll also compute the Robbery Score with glmnet as a **sensitivity check** in Phase 4 (their round predictions correlate at 0.99), and report how far the leaderboard moves.

## 3. What judges reward (logistic model, all 33,444 judge-rounds; SEs clustered by fight)
Exchange rate in significant **head** strikes (`p3_what_judges_reward.png`):

| Edge | Worth (head strikes) | 95% CI |
|---|---|---|
| Knockdown | 12.4 | 10.4–14.3 |
| Submission attempt | 4.8 | 4.1–5.5 |
| Minute of control time | 3.1 | 2.8–3.4 |
| Takedown landed | 2.2 | 1.9–2.6 |
| Reversal | 1.3 | 0.3–2.3 |
| Body strike | 0.75 | 0.68–0.82 |
| Leg strike | 0.59 | 0.52–0.66 |
| Ground-strike premium | +0.37 | 0.22–0.53 |
| Non-significant strike | 0.15 | 0.12–0.18 |
| Clinch-strike premium | +0.11 | 0.00–0.21 |
| **Failed takedown attempt** | **−0.67** | −0.82 to −0.52 |

**Main takeaways (associations, not causal claims):**
- Not all significant strikes count the same. A head strike counts for more than a body strike (about 0.75 of a head strike), which counts for more than a leg strike (about 0.59).
- A knockdown is worth about a dozen head strikes.
- Grappling is rewarded heavily: a takedown is worth about 2 head strikes and a minute of control about 3.
- Shooting and missing a takedown costs a fighter on the cards, by about two-thirds of a head strike per miss.

In xgboost SHAP importance, head strikes come first (30%), then control time (18%), body strikes (11%) and leg strikes (8%). Knockdowns rank low on average importance only because they're rare; when one happens it's decisive.

## 4. 10-8 model (for the Phase 4 simulation)
- 3.4% of judge-rounds with a winner are 10-8 or wider.
- The model is a logistic regression on differentials oriented to the judge's winner (knockdowns, strikes, control, submission attempts, ground strikes), plus a post-2017 era flag.
- Grouped-CV log-loss is 0.093, against 0.147 for a constant rate; AUC 0.92.
- Descriptive: the raw 10-8 rate is 2.4% before 2017 and 3.8% after. The formal test is in Phase 5, which also needs the 2017 effective date verified and cited (provisionally 2017-01-01).

## 5. Leakage and data checks
- Head + body + leg always equals significant strikes landed, as does distance + clinch + ground (0 exceptions). Non-significant strikes are never negative.
- Features come only from the scored round's row. Fight outcome, method and decision type aren't model inputs.
- The time-based test never uses a test-year round in training. Grouped CV keeps all judges, all rounds and both mirrored copies of a fight in the same fold.

## 6. Decisions (Rob, 2026-11-12)
- Final model: xgboost ("whatever model you think is best"), with glmnet as a Phase 4 sensitivity check.
- Keep the detailed, every-factor version of "what judges reward".
