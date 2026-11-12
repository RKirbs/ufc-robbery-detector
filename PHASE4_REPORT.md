# Phase 4: Simulation and Robbery Index

**Date:** 2026-11-12
**Status:** CHECKPOINT. Waiting for approval of the tier cutoffs before writing the narrative.

Every number below comes from `Rscript scripts/phase4_report.R`, run after `targets::tar_make()`. Figures are in `figures/p4_*.png`. The full top 100 is in `data/interim/top100_robberies.csv`.

## 1. How it works
1. **Round probabilities.** The final xgboost round model gives P(fighter A wins the round) for all 12,938 rounds of the 4,109 decisions.
   - For the 3,620 fights whose judges' scores were used in training, these are **out-of-fold** predictions (10-fold, grouped by fight), so no fight's own scorecards inform its own score.
   - The remaining 489 fights (1,512 rounds, mostly before 2011) use the model fit on all rounds.
2. **Correlated judges.** Each judge's round call is modeled as a shared "what everyone saw" factor plus individual noise, with latent correlation ρ estimated by maximum likelihood from how often the three real judges split.
3. **10-8 and 10-10 rounds.**
   - A 10-8 model (from Phase 3) gives each round's 10-8 chance, with its own between-judge correlation.
   - 10-10s use a small model: they're rare, more likely in close rounds, and almost gone since 2017.
4. **Point deductions** (new; see section 6) are applied to every simulated card.
5. **Simulation.** 10,000 sets of three scorecards per fight produce P(A wins), P(draw) and P(B wins). A fighter wins if at least 2 judges score for them; anything else is a draw.
6. **Robbery Score** = 1 − P(declared winner wins).

## 2. Judge correlation
| | Estimate |
|---|---|
| Latent correlation ρ (who wins the round) | **0.61** (95% bootstrap CI 0.58–0.63; 10,870 rounds, 3,447 fights) |
| Implied correlation between two judges' calls | 0.42 for a toss-up round, 0.33 for a 90/10 round |
| Share of rounds where judges split: observed | **22.0%** |
| … predicted with ρ = 0.61 | 22.2% |
| … predicted if judges were independent | 35.9% |
| 10-8 latent correlation ρ₈ | 0.60 (8,475 unanimous rounds; 676 with at least one 10-8, 131 with all three) |

Treating judges as independent would overstate split rounds by about 60% and make every close fight look more random than it is. The correlated model matches the observed split rate at every level of round closeness (`p4_judge_split_rates.png`).

## 3. Checks on the simulation
- **Direct fight-level model** (logistic regression on fight-total stat differentials, out-of-fold):
  - Its P(A wins) correlates with the simulation's at 0.965.
  - The simulation is slightly better: log-loss 0.323 vs. 0.338, accuracy 85.4% vs. 85.1%.
- **Rates:** predicted split-decision rate 21.6% vs. 20.2% actual. Predicted draw rate 1.5% vs. 1.5% actual.
- **Judge card totals (the Option A out-of-sample check):** the simulation predicts which fighter each single judge's card favors.

  | Group | Cards | Card winner matches | Correlation of predicted vs. actual card margin |
  |---|---|---|---|
  | Fights with round scores (out-of-fold) | 10,209 | 83.8% | 0.82 |
  | **Totals-only fights (never used in training)** | 1,935 | **85.2%** | 0.78 |

  The model works just as well on the older, never-trained-on fights.
- **Fight-level calibration** (`p4_fight_calibration.png`):
  - Fighter A (red corner) won 61.4% of decisions, but the simulation, which is corner-symmetric by design, averages 57.1%. So in the middle probability bands, red corners win about 6–11 points more often than the stats alone predict.
  - This is the red-corner / favorite question for Phase 5. It isn't a finding yet: red corners are usually favorites, champions or the more established fighter, and some of that edge may be things stats can't see.

## 4. Robbery Score distribution (4,049 decisions; the 60 draws are reported separately)
Quantiles: median 0.083, 75th percentile 0.31, 90th 0.61, 95th 0.77, 99th 0.94.

**Proposed tiers (the brief's cutoffs, unchanged):**

| Tier | Score | Decisions | Share | Media majority scored it for the official loser* |
|---|---|---|---|---|
| Clean | < 0.25 | 2,841 | 70.2% | 2.0% |
| Close / defensible | 0.25–0.50 | 618 | 15.3% | 14.6% |
| Questionable | 0.50–0.75 | 365 | 9.0% | 33.3% |
| **Robbery** | ≥ 0.75 | **225** | **5.6%** | 47.4% |

\*Among fights with at least 5 media scores. The correlation between the Robbery Score and the share of media scoring for the loser is 0.59.

- By decision type: split decisions average 0.41 (38% Questionable or Robbery), majority decisions 0.32, unanimous 0.14 (8%).
- **Recommendation: keep the brief's cutoffs.**
  - Media agreement rises steadily across them (2% → 15% → 33% → 47%), which is what a meaningful scale should do.
  - Tuning the cutoffs *to* the media data would contaminate the Phase 5 validation, which uses the media as the independent test.
- **Alternative:** a stricter Robbery tier at ≥ 0.90 would hold 72 fights, and in the top band (≥ 0.95) 72% had a media majority for the loser. The tradeoff is fewer, more defensible "robberies" against a less useful middle tier.

**Sensitivity to the round model (glmnet instead of xgboost):** Spearman correlation 0.987, 91% of fights land in the same tier, and 22 of the top 25 are the same (`p4_sensitivity_glmnet.png`).

## 5. Top 25: largest disagreements between the stats and the official result
These are statistical disagreements, not accusations: the stats can't see damage, octagon control or aggression. The "why" line gives the loser's statistical case, followed by the winner's strongest counterpoints.

| # | Date | Official winner | Loser | Decision | Score | Media for loser | Why the model disagrees |
|---|---|---|---|---|---|---|---|
| 1 | 2012-05-15 | Igor Pokrajac | Fabio Maldonado | Unanimous | 0.998 | 80% (n=5) | Model favored Maldonado in 3 of 3 rounds; Maldonado out-landed Pokrajac 98-36 in sig. strikes (ahead in 3 of 3); Pokrajac had 1 takedown to 0; Pokrajac had 3:20 more control time. |
| 2 | 2010-12-04 | Leonard Garcia | Nam Phan | Split | 0.992 | 100% (n=5) | Model favored Phan in 3 of 3 rounds; Phan out-landed Garcia 102-64 in sig. strikes (ahead in 3 of 3); Garcia had 2 takedowns to 0; Phan had 1:45 more control time. |
| 3 | 2018-02-03 | Sergio Moraes | Tim Means | Split | 0.990 | 93% (n=14) | Model favored Means in 3 of 3 rounds; Means out-landed Moraes 129-87 in sig. strikes (ahead in 3 of 3); Means scored 1 knockdown; Means had 1:21 more control time. |
| 4 | 2018-03-17 | Tom Duquesnoy | Terrion Ware | Unanimous | 0.989 | 31% (n=16) | Model favored Ware in 3 of 3 rounds; Ware out-landed Duquesnoy 85-67 in sig. strikes (ahead in 3 of 3); Ware had 1:22 more control time. |
| 5 | 2014-06-28 | Gian Villante | Sean O'Connell | Split | 0.987 | 38% (n=8) | Model favored O'Connell in 3 of 3 rounds; O'Connell out-landed Villante 109-93 in sig. strikes (ahead in 3 of 3); O'Connell scored 1 knockdown; O'Connell had 4:04 more control time. |
| 6 | 2021-08-28 | Wellington Turman | Sam Alvey | Split | 0.986 | 23% (n=13) | Model favored Alvey in 2 of 3 rounds; Turman out-landed Alvey 69-68 in sig. strikes (ahead in 1 of 3); Turman had 2 takedowns to 0; Turman had 1:00 more control time; point deduction: Wellington Turman -2 (rd 3). |
| 7 | 2006-04-15 | Sean Sherk | Nick Diaz | Unanimous | 0.984 | 0% (n=2) | Model favored Diaz in 3 of 3 rounds; Diaz out-landed Sherk 57-39 in sig. strikes (ahead in 3 of 3); Sherk had 2 takedowns to 1; Sherk had 2:20 more control time. |
| 8 | 2015-05-16 | Phillipe Nover | Yui Chul Nam | Split | 0.983 | 92% (n=12) | Model favored Nam in 2 of 3 rounds; Nam out-landed Nover 29-12 in sig. strikes (ahead in 2 of 3); Nover had 6 takedowns to 2. |
| 9 | 2022-02-26 | Priscila Cachoeira | Ji Yeon Kim | Unanimous | 0.983 | 93% (n=15) | Model favored Kim in 3 of 3 rounds; Kim out-landed Cachoeira 170-102 in sig. strikes (ahead in 3 of 3); Cachoeira had 1 takedown to 0. |
| 10 | 2018-12-15 | Drakkar Klose | King Green | Unanimous | 0.983 | 79% (n=14) | Model favored Green in 3 of 3 rounds; Green out-landed Klose 92-58 in sig. strikes (ahead in 3 of 3); Green had 2:46 more control time. |
| 11 | 2009-06-20 | Melvin Guillard | Gleison Tibau | Split | 0.982 | 100% (n=3) | Model favored Tibau in 3 of 3 rounds; Tibau out-landed Guillard 14-13 in sig. strikes (ahead in 1 of 3); Tibau had 8:21 more control time. |
| 12 | 2020-11-21 | Nicolas Dalby | Daniel Rodriguez | Unanimous | 0.982 | 45% (n=20) | Model favored Rodriguez in 3 of 3 rounds; Rodriguez out-landed Dalby 83-50 in sig. strikes (ahead in 3 of 3). |
| 13 | 2019-08-31 | Alatengheili | Batgerel Danaa | Unanimous | 0.978 | 0% (n=10) | Model favored Danaa in 3 of 3 rounds; Danaa out-landed Alatengheili 85-36 in sig. strikes (ahead in 3 of 3); Alatengheili had 3 takedowns to 0; Alatengheili had 2:46 more control time; point deduction: Danaa Batgerel -1 (rd 3). |
| 14 | 2005-11-19 | Jeremy Horn | Trevor Prangley | Unanimous | 0.974 | – | Model favored Prangley in 3 of 3 rounds; Prangley out-landed Horn 38-38 in sig. strikes (ahead in 1 of 3); Horn landed more head strikes (19-17); Prangley had 7:24 more control time. |
| 15 | 2015-04-04 | Al Iaquinta | Jorge Masvidal | Split | 0.973 | 86% (n=14) | Model favored Masvidal in 3 of 3 rounds; Masvidal out-landed Iaquinta 83-55 in sig. strikes (ahead in 3 of 3). |
| 16 | 2019-02-02 | Thiago Alves | Max Griffin | Split | 0.973 | 89% (n=18) | Model favored Griffin in 3 of 3 rounds; Griffin out-landed Alves 112-83 in sig. strikes (ahead in 2 of 3); Griffin scored 1 knockdown; Griffin had 2:27 more control time. |
| 17 | 2014-08-23 | Milana Dudieva | Elizabeth Phillips | Split | 0.973 | 86% (n=7) | Model favored Phillips in 3 of 3 rounds; Phillips out-landed Dudieva 25-11 in sig. strikes (ahead in 3 of 3); Dudieva had 2 takedowns to 0; Phillips had 4:57 more control time. |
| 18 | 2023-10-07 | Vanessa Demopoulos | Kanako Murata | Unanimous | 0.973 | 93% (n=14) | Model favored Murata in 2 of 3 rounds; Murata out-landed Demopoulos 34-31 in sig. strikes (ahead in 1 of 3); Murata had 9:28 more control time. |
| 19 | 2019-07-13 | Benito Lopez | Vince Morales | Unanimous | 0.970 | 100% (n=11) | Model favored Morales in 3 of 3 rounds; Morales out-landed Lopez 64-54 in sig. strikes (ahead in 1 of 3); Morales scored 1 knockdown. |
| 20 | 2014-01-15 | John Moraga | Dustin Ortiz | Split | 0.969 | 100% (n=9) | Model favored Ortiz in 2 of 3 rounds; Moraga out-landed Ortiz 43-35 in sig. strikes (ahead in 1 of 3); Moraga landed more head strikes (25-22); Ortiz had 5:21 more control time. |
| 21 | 2020-08-01 | Nate Maness | Johnny Munoz | Unanimous | 0.966 | 33% (n=15) | Model favored Munoz in 3 of 3 rounds; Munoz out-landed Maness 49-21 in sig. strikes (ahead in 3 of 3); Munoz had 8:13 more control time; point deduction: Johnny Munoz -1 (rd 3). |
| 22 | 2017-10-28 | Deiveson Figueiredo | Jarred Brooks | Split | 0.962 | 57% (n=14) | Model favored Brooks in 2 of 3 rounds; Brooks out-landed Figueiredo 30-19 in sig. strikes (ahead in 2 of 3); Brooks had 6:22 more control time. |
| 23 | 2024-03-16 | Christian Rodriguez | Isaac Dulgarian | Split | 0.961 | 82% (n=11) | Model favored Dulgarian in 2 of 3 rounds; Rodriguez out-landed Dulgarian 48-22 in sig. strikes (ahead in 2 of 3); Rodriguez landed more head strikes (43-17); Dulgarian had 6:03 more control time. |
| 24 | 2016-03-19 | Ross Pearson | Chad Laprise | Split | 0.960 | 31% (n=16) | Model favored Laprise in 3 of 3 rounds; Laprise out-landed Pearson 78-52 in sig. strikes (ahead in 3 of 3). |
| 25 | 2009-10-24 | Lyoto Machida | Mauricio Rua | Unanimous | 0.958 | 100% (n=5) | Model favored Rua in 5 of 5 rounds; Rua out-landed Machida 80-35 in sig. strikes (ahead in 5 of 5); Rua had 2:21 more control time. |


**Face validity:**
- Several decisions widely regarded as disputed appear: Pokrajac vs. Maldonado (#1), Garcia vs. Phan (#2), Iaquinta vs. Masvidal (#15), Machida vs. Shogun 1 (#25).
- Some top entries have **low media support for the loser**: Duquesnoy vs. Ware (31%), Villante vs. O'Connell (38%), Turman vs. Alvey (23%) and Alatengheili vs. Danaa (0 of 10). These are cases where people watching the fight saw something the stats don't capture, likely damage, power or effectiveness. They're exactly the "model vs. media" disagreements Phase 5 will list and discuss.
- **Early-era caution:** Sherk vs. Diaz (2006) and Horn vs. Prangley (2005) have only 0–2 media scores. Stats for those years were coded from video after the fact. 9 of the 225 robbery-tier fights are from before 2008, and 10 have fewer than 3 media scores. I suggest the leaderboard flags these as "limited corroboration" rather than dropping them.

## 6. Data bug found and fixed: point deductions
- MMADecisions' round scores **include point deductions**: 109 deductions in 105 fights, such as "X was deducted 1 point in round 3: Grabbing the fence".
- Before this fix:
  - A 10-9 round with a point taken from its winner read as a 9-9, a fake "10-10". **138 of the 163 "10-10" judge-rounds were really this**; only 25 were genuine.
  - A deduction from the round's loser inflated 10-9s into 10-8s.
  - The simulation didn't know that a fight could be decided by a deduction.
- **Fix:**
  - Deducted points are added back to each judge's round score before modeling, so the outcome is the judge's own call on the round. The official scores are kept, and 3 cards that evidently didn't apply the deduction keep their official scores.
  - The simulation subtracts the deductions from every simulated card.
  - The "why" line mentions the deduction.
- Phase 3 was rerun. Its conclusions are unchanged, and PHASE3_REPORT.md has been updated.

## 7. Your question: does the model account for damage?
**Partly, through proxies; it can't see damage directly.**
- **Captured:**
  - Knockdowns, worth about 12 head strikes each.
  - Head strikes, weighted more than body or leg strikes.
  - Ground strikes, which carry a premium.
  - Submission attempts (near-finishes).
  - The model learned these weights from how judges actually score, so whatever share of damage shows up in these stats is already priced in.
- **Not captured:**
  - Visible damage (cuts, swelling), strike power, and a fighter being hurt or wobbled without a knockdown.
  - Volume of low-impact strikes vs. a few hard ones; UFCStats counts a jab and a power punch the same.
  - There's no free round-by-round damage dataset to add.
- **How the project handles it:**
  1. The site will say this plainly. The brief already lists it as a limitation.
  2. Every leaderboard entry shows the media scorecards. Media members watched the fight, so when they side with the judges against the stats (like Alatengheili vs. Danaa, 0 of 10 for the loser), that's a strong sign damage or effectiveness the stats miss decided it.
  3. The "why" line names the winner's damage proxies (knockdowns, head strikes) so readers can see the counter-case.
  4. Phase 5 validates the Robbery Score against the media scores and lists the biggest model-vs-media disagreements, which is where damage-driven decisions should show up.

## 8. Bottom 25: results the stats support most clearly
All of these have a Robbery Score of 0.000 and 0% media support for the loser.

| # | Date | Official winner | Loser | Decision | Score | Media for loser | Why the model disagrees |
|---|---|---|---|---|---|---|---|
| 1 | 2021-01-16 | Max Holloway | Calvin Kattar | Unanimous | 0.000 | 0% (n=24) | Holloway out-landed Kattar 445-133 in sig. strikes |
| 2 | 2024-05-18 | Lerone Murphy | Edson Barboza | Unanimous | 0.000 | 0% (n=14) | Murphy out-landed Barboza 220-79 in sig. strikes |
| 3 | 2023-08-19 | Zhang Weili | Amanda Lemos | Unanimous | 0.000 | 0% (n=20) | Weili out-landed Lemos 163-24 in sig. strikes |
| 4 | 2024-06-08 | Punahele Soriano | Miguel Baeza | Unanimous | 0.000 | 0% (n=11) | Soriano out-landed Baeza 144-7 in sig. strikes |
| 5 | 2023-01-21 | Jessica Andrade | Lauren Murphy | Unanimous | 0.000 | 0% (n=24) | Andrade out-landed Murphy 231-100 in sig. strikes |
| 6 | 2014-04-16 | Sarah Kaufman | Leslie Smith | Unanimous | 0.000 | 0% (n=11) | Kaufman out-landed Smith 202-79 in sig. strikes |
| 7 | 2019-10-12 | Joanna Jedrzejczyk | Michelle Waterson-Gomez | Unanimous | 0.000 | 0% (n=17) | Jedrzejczyk out-landed Waterson-Gomez 180-58 in sig. strikes |
| 8 | 2017-09-09 | Ricky Glenn | Gavin Tucker | Unanimous | 0.000 | 0% (n=14) | Glenn out-landed Tucker 142-23 in sig. strikes |
| 9 | 2011-03-03 | Cyrille Diabate | Steve Cantwell | Unanimous | 0.000 | 0% (n=6) | Diabate out-landed Cantwell 146-28 in sig. strikes |
| 10 | 2014-03-01 | Vaughan Lee | Nam Phan | Unanimous | 0.000 | 0% (n=11) | Lee out-landed Phan 142-24 in sig. strikes |
| 11 | 2019-03-02 | Kamaru Usman | Tyron Woodley | Unanimous | 0.000 | 0% (n=26) | Usman out-landed Woodley 141-34 in sig. strikes |
| 12 | 2006-03-04 | Rich Franklin | David Loiseau | Unanimous | 0.000 | 0% (n=2) | Franklin out-landed Loiseau 127-21 in sig. strikes |
| 13 | 2012-12-08 | Dennis Siver | Nam Phan | Unanimous | 0.000 | 0% (n=10) | Siver out-landed Phan 128-24 in sig. strikes |
| 14 | 2013-02-23 | Court McGee | Josh Neer | Unanimous | 0.000 | 0% (n=13) | McGee out-landed Neer 166-63 in sig. strikes |
| 15 | 2019-08-03 | Colby Covington | Robbie Lawler | Unanimous | 0.000 | 0% (n=19) | Covington out-landed Lawler 179-78 in sig. strikes |
| 16 | 2023-06-10 | Amanda Nunes | Irene Aldana | Unanimous | 0.000 | 0% (n=26) | Nunes out-landed Aldana 142-41 in sig. strikes |
| 17 | 2017-09-22 | Jessica Andrade | Claudia Gadelha | Unanimous | 0.000 | 0% (n=15) | Andrade out-landed Gadelha 141-42 in sig. strikes |
| 18 | 2008-08-09 | Georges St-Pierre | Jon Fitch | Unanimous | 0.000 | 0% (n=6) | St-Pierre out-landed Fitch 131-37 in sig. strikes |
| 19 | 2012-12-08 | Benson Henderson | Nate Diaz | Unanimous | 0.000 | 0% (n=11) | Henderson out-landed Diaz 124-30 in sig. strikes |
| 20 | 2018-04-07 | Khabib Nurmagomedov | Al Iaquinta | Unanimous | 0.000 | 0% (n=20) | Nurmagomedov out-landed Iaquinta 134-41 in sig. strikes |
| 21 | 2018-07-22 | Aleksandar Rakic | Justin Ledet | Unanimous | 0.000 | 0% (n=17) | Rakic out-landed Ledet 104-12 in sig. strikes |
| 22 | 2012-06-01 | Max Holloway | Pat Schilling | Unanimous | 0.000 | 0% (n=6) | Holloway out-landed Schilling 118-27 in sig. strikes |
| 23 | 2010-08-07 | Junior Dos Santos | Roy Nelson | Unanimous | 0.000 | 0% (n=6) | Santos out-landed Nelson 130-40 in sig. strikes |
| 24 | 2013-08-31 | Tim Elliott | Louis Gaudinot | Unanimous | 0.000 | 0% (n=14) | Elliott out-landed Gaudinot 116-28 in sig. strikes |
| 25 | 2016-09-17 | Evan Dunham | Ricky Glenn | Unanimous | 0.000 | 0% (n=13) | Dunham out-landed Glenn 144-58 in sig. strikes |


## 9. Draws (reported separately)
- 60 draws. The model's average P(draw) for these fights is 8.6%, against a 1.5% baseline, so it does recognize them as unusually close.
- In the typical draw, the model gives the stronger side a 72% chance of winning.

## 10. Questions for you
1. **Tier cutoffs:** keep the brief's 0.25 / 0.50 / 0.75 (my recommendation), or use a stricter Robbery tier (≥ 0.90, 72 fights)?
2. **Thin-data entries** (pre-2008 fights, or fewer than 3 media scores): flag them as "limited corroboration" on the leaderboard (recommended), or leave them off it?
