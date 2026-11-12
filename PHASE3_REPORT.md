# Phase 3: Round Model

**Date:** 2026-11-12
**Status:** CHECKPOINT. Waiting for approval before Phase 4 (simulation and Robbery Index).

Every number below comes from `Rscript scripts/phase3_report.R`, run after `targets::tar_make()`. Figures are in `figures/p3_*.png`.

## 1. Setup
- **Unit:** one judge's score of one round. **Outcome:** the fighter that judge gave the round to.
- **Data (Option A):** 33,306 judge-rounds in 3,620 fights, from 2006 to 2026. Dropped:
  - 163 judge-rounds scored 10-10 (0.5%). These are set aside here and modeled in the Phase 4 simulation.
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
  - (b) A **time-based test**: train on 2006–2019 (17,044 judge-rounds, 1,911 fights), test on 2020–2026 (16,262 judge-rounds, 1,709 fights).
  - (c) A **rolling-origin** test: each year from 2020 to 2026 is predicted by models trained only on earlier years.

  Confidence intervals come from bootstrapping over fights.

## 2. Results (time-based test, 2020–2026)

| Model | Log-loss | Brier | Accuracy | Worst calibration bin |
|---|---|---|---|---|
| Baseline: significant-strike leader wins | 0.551 | 0.183 | 75.2% | 5.2 pts |
| Logistic | 0.383 | 0.122 | 82.8% | 8.4 pts |
| glmnet (regularized, with interactions) | **0.376** | **0.121** | **83.1%** | 10.0 pts |
| xgboost | 0.380 | 0.122 | 82.6% | **5.4 pts** |

- All three models beat the baseline by a wide margin. The log-loss improvement over the baseline is 0.16 to 0.19 (95% CI) for every model.
- The three models are close to each other:
  - glmnet beats xgboost on log-loss by 0.004 (95% CI 0.001 to 0.007), about 1%.
  - Logistic is 0.003 worse than xgboost (CI −0.000 to 0.007).
- Grouped CV on the training years gives the same ordering (log-loss: glmnet 0.365, logistic 0.369, xgboost 0.372, baseline 0.539).
- The rolling-origin results are stable from year to year: log-loss is 0.35–0.40 for the models and 0.52–0.56 for the baseline (`p3_logloss_by_year.png`).

**Calibration** (`p3_calibration.png`):
- The two linear models are slightly S-shaped. When they predict about 55%, judges give the round to that fighter about 64–65% of the time, and the tails run a little overconfident.
- xgboost tracks the diagonal more closely.
- The SHAP plots show why. Judges' reward for a strike lead **flattens out at about +20 significant head strikes**, because by then the round is already won. A linear model can't flatten out.

### Recommendation: use xgboost as the final round model
The brief says to pick on log-loss *and* calibration:
- xgboost gives up 1% of log-loss to glmnet but has half the worst-bin calibration error.
- Calibration matters more here, because Phase 4 combines round probabilities across rounds and judges, so a systematic error in close rounds adds up. Close rounds are exactly where disputed decisions come from.

I'll also compute the Robbery Score with glmnet as a **sensitivity check** in Phase 4 (their round predictions correlate at 0.99), and report how far the leaderboard moves.

## 3. What judges reward (logistic model, all 33,306 judge-rounds; SEs clustered by fight)
Exchange rate in significant **head** strikes (`p3_what_judges_reward.png`):

| Edge | Worth (head strikes) | 95% CI |
|---|---|---|
| Knockdown | 12.4 | 10.5–14.3 |
| Submission attempt | 4.8 | 4.1–5.5 |
| Minute of control time | 3.1 | 2.8–3.4 |
| Takedown landed | 2.2 | 1.9–2.6 |
| Reversal | 1.3 | 0.3–2.3 |
| Body strike | 0.74 | 0.66–0.81 |
| Leg strike | 0.58 | 0.52–0.65 |
| Ground-strike premium | +0.36 | 0.20–0.51 |
| Non-significant strike | 0.15 | 0.12–0.18 |
| Clinch-strike premium | +0.10 | −0.00–0.21 |
| **Failed takedown attempt** | **−0.66** | −0.81 to −0.51 |

**Main takeaways (associations, not causal claims):**
- Not all significant strikes count the same. A head strike counts for more than a body strike (about 0.74 of a head strike), which counts for more than a leg strike (about 0.58).
- A knockdown is worth about a dozen head strikes.
- Grappling is rewarded heavily: a takedown is worth about 2 head strikes and a minute of control about 3.
- Shooting and missing a takedown costs a fighter on the cards, by about two-thirds of a head strike per miss.

In xgboost SHAP importance, head strikes come first (30%), then control time (18%), body strikes (11%) and leg strikes (8%). Knockdowns rank low on average importance only because they're rare; when one happens it's decisive.

## 4. 10-8 model (for the Phase 4 simulation)
- 3.7% of judge-rounds with a winner are 10-8 or wider.
- The model is a logistic regression on differentials oriented to the judge's winner (knockdowns, strikes, control, submission attempts, ground strikes), plus a post-2017 era flag.
- Grouped-CV log-loss is 0.109, against 0.159 for a constant rate; AUC 0.89.
- Descriptive: the raw 10-8 rate is 2.8% before 2017 and 4.1% after. The formal test is in Phase 5, which also needs the 2017 effective date verified and cited (provisionally 2017-01-01).

## 5. Leakage and data checks
- Head + body + leg always equals significant strikes landed, as does distance + clinch + ground (0 exceptions). Non-significant strikes are never negative.
- Features come only from the scored round's row. Fight outcome, method and decision type aren't model inputs.
- The time-based test never uses a test-year round in training. Grouped CV keeps all judges, all rounds and both mirrored copies of a fight in the same fold.

## 6. Questions for you
1. **Final model:** xgboost (my recommendation, for calibration) or glmnet (best log-loss)? I'd keep the other one as a Phase 4 sensitivity check either way.
2. Anything to add to the "what judges reward" analysis before I move on? For example, a version that doesn't split strikes by target, for a simpler headline.
