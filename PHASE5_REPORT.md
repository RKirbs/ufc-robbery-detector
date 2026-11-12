# Phase 5: Validation, Judges, and the 2017 Criteria

**Date:** 2026-11-12
**Status:** CHECKPOINT. Waiting for approval, and for a decision on the optional Phase 6 (betting odds).

Every number below comes from `Rscript scripts/phase5_report.R`, run after `targets::tar_make()`. Figures are in `figures/p5_*.png`. Judge results describe **agreement with a statistical model**. They say nothing about any judge's competence or intent.

## 1. Validation

### 1.1 Media scorecards (the key test)
- **The Robbery Score correlates with the share of media scoring the fight for the official loser:**
  - Pearson r = **0.59** (95% bootstrap CI 0.56–0.62).
  - Spearman = 0.60 (0.58–0.62).
  - Based on 3,664 decisions with at least 5 media scores (`p5_media_scatter.png`).
- **Who the media majority sides with** (3,623 fights with a clear media majority):

  | | Agrees with the media majority |
  |---|---|
  | Official result | 89.8% |
  | Model's favorite | 87.7% |
  | (Model vs. official result) | 85.9% |

- So the stats-only model agrees with the media almost as often as the judges do. Where all three disagree is where the interesting cases are.

**The biggest disagreements between model and media** (full lists are in the report output):
- **The stats favor the loser, but the media sided with the winner.** Examples:
  - Alatengheili def. Danaa (2019): 0 of 10 media for the loser.
  - Vera def. Font (2022): 0 of 21.
  - Martins def. Whiteford (2016): 0 of 13.
  - Edwards def. Usman 2 (2023): 2 of 32.

  These are the most likely cases where **damage, power or effectiveness the stats don't record** decided the fight. They're the clearest illustration of the damage limitation.
- **The media favored the loser, but the stats backed the winner.** Examples:
  - Said Nurmagomedov def. Scoggins (2018): 17 of 17 media for the loser, model 97% for the winner. UFCStats has Nurmagomedov out-landing Scoggins 65–32.
  - Waterson def. Casey (2018): 16 of 17.
  - Julianna Peña def. Pennington (2024): 25 of 27.

  These are either things the stats miss (pressure, effective aggression, the quality of strikes) or occasional recording errors in the stat counts. **I suggest a manual spot-check of the top few against fight footage or other stat sources before the site calls out any of them.**

### 1.2 Round-level agreement (10,870 rounds scored by three judges)
| | Agreement |
|---|---|
| Model's round winner vs. the judges' majority | **84.7%** |
| … in rounds the judges scored unanimously | 91.1% |
| … in rounds the judges split | 62.1% |
| Model vs. an individual judge | 82.9% |
| *Benchmark:* one judge vs. the other two, when those two agree | 91.4% |
| Model vs. the other two judges, when they agree | 88.6% |

The model is close to, but a little below, how well one judge matches two others. Media members score whole fights, not rounds, so round-level agreement with the media can't be measured. That's a data limitation.

### 1.3 Face validity: widely debated decisions
| Decision | Robbery Score | Tier | Rank (of 4,049) | Media for loser |
|---|---|---|---|---|
| Pokrajac def. Maldonado (2012) | 0.998 | Robbery | 1 | 80% (n=5) |
| Garcia def. Phan (2010) | 0.992 | Robbery | 2 | 100% (n=5) |
| Iaquinta def. Masvidal (2015) | 0.973 | Robbery | 15 | 86% (n=14) |
| Machida def. Shogun (2009) | 0.958 | Robbery | 25 | 100% (n=5) |
| Sanchez def. Pearson (2014) | 0.947 | Robbery | 33 | 100% (n=14) |
| Bisping def. Hamill (2007) | 0.932 | Robbery | 49 | 0% (n=2) |
| Henderson def. Edgar 2 (2012) | 0.788 | Robbery | 176 | 78% (n=9) |
| Jones def. Reyes (2020) | 0.662 | Questionable | 332 | 67% (n=21) |
| Jackson def. Machida (2010) | 0.653 | Questionable | 344 | 71% (n=7) |
| St-Pierre def. Hendricks (2013) | 0.569 | Questionable | 468 | 100% (n=16) |
| Condit def. Diaz (2012) | 0.476 | Close | 643 | 14% (n=7) |
| Henderson def. Thomson (2014) | 0.142 | Clean | 1,661 | 81% (n=16) |
| Volkanovski def. Holloway 2 (2020) | 0.079 | Clean | 2,056 | 67% (n=27) |

- 11 of 13 fall in the top 16% of all decisions, and 7 are in the Robbery tier.
- The two misses are informative. In Volkanovski–Holloway 2 and Henderson–Thomson, the counted stats support the winner while most media didn't. That's the "stats can't see everything" limitation, not a bug.
- The bottom of the table (from Phase 4) is made up of clearly one-sided decisions, all with 0% media support for the loser.

### 1.4 Fight-level calibration
This is in Phase 4 (`p4_fight_calibration.png`). The simulation is reasonably calibrated, but red corners win more often than it predicts; that's quantified in section 2.3.

## 2. Judges
All judge-level results use judges with at least **100 rounds** (49 judges) and **shrinkage** (mixed models with judge random effects), and show 95% intervals.

### 2.1 Agreement with the model, adjusted for how close each judge's rounds were (`p5_judge_agreement.png`)
- On a typical round (the model favors one fighter 75/25), the league-average agreement is **74.7%**.
- The 49 judges range only from 73.6% to 77.0%. **Only 2 of 49 have intervals that exclude the average.**
- Once you adjust for how close each judge's rounds were, judges agree with the stats at very similar rates. Raw agreement rates differ more, mostly because some judges drew harder rounds.

### 2.2 Grappling vs. striking emphasis (`p5_judge_grappling.png`)
- Each judge gets a multiplier on the striking part and on the grappling part of the round model (random slopes).
- **10 of 49 judges have intervals that exclude the league average.** About 2–3 would be expected by chance, so there's some real variation in emphasis.
- The estimates range from about 0.72× to 1.27× the league-average grappling emphasis. The intervals are wide; the chart shows them.

### 2.3 Systematic patterns, controlling for round stats (`p5_red_corner.png`)
**Red corner** (UFCStats lists the red-corner fighter first; we rely on that convention):
- On a round the stats call 50/50, judges give it to the red corner **4.5 points** more often (simple model, CIs clustered by fight).
- Adding experience and record controls makes it **5.6 points** (95% CI about 4.4–6.8).
- **The lean has shrunk:** +8.0 points in 2006–2016, +3.0 points in 2017–2026.
- Judges differ only modestly: 4 of 49 have a lean whose interval excludes the average.
- *Caution:* red corners are usually the favorite, the champion or the more established fighter. Without betting odds (Phase 6) we can't tell "red corner" apart from "favorite" or from things stats can't see.

**Record:**
- Judges lean toward the fighter with the better prior UFC record beyond what the round stats show. A 30-point gap in prior win rate is worth about 4 points on a 50/50 round.
- More prior UFC fights doesn't help; the coefficient is slightly negative.
- This could be reputation, or better fighters doing things the stats can't capture.

**Title fights:**
- No significant extra red-corner lean in title fights: +1.8 points, CI −1.3 to +4.9.
- The red corner is the champion's corner in title fights, so this is our champion proxy.

**Late-round recency:**
- The model's edge in the final round doesn't predict the official result beyond the full simulation (p = 0.14).
- Under round-by-round 10-point-must scoring there's little room for recency anyway.
- The first round shows a weak negative effect (p = 0.01). It counts slightly *less* than the model assumes. That's worth noting, but it isn't strong.

**Betting favorite:** this needs odds data, so it's in Phase 6.

## 3. The 2017 judging-criteria update
**Source check:**
- The ABC approved the revised criteria at its August 2016 conference (the Unified Rules show them as amended August 3, 2016), with an effective date of **January 1, 2017**. State commissions adopted them on their own timelines.
- Sources: Bloody Elbow (2017-01-02 and 2018-02-01), BJPenn.com, Uproxx, ABC MMA Officials Handbook.
- We use 2017-01-01 as the break and recheck without 2017 (the transition year).

### 3.1 Did the weights change? Yes, in the direction the new criteria describe (`p5_criteria_weights.png`)
- A joint test that no weight changed is rejected: χ² = 36.2 on 13 df, **p = 0.0006**. It's the same without 2017 (p = 0.0006).
- In head-strike equivalents, before 2017 → after:

  | Edge | Before 2017 | After |
  |---|---|---|
  | Knockdown | 9.2 | **14.6** (z = 2.3) |
  | Submission attempt | 3.9 | 5.5 |
  | Takedown | 2.7 | **1.9** (z = −3.1) |
  | Ground strike | — | small premium appears (z = 2.7) |
  | Leg strike | 0.69 | 0.56 |
  | Control time per minute | 2.7 | 3.2 (not significant) |

- This fits the criteria's emphasis on effective, impactful striking and grappling, with a takedown alone counting for less.

### 3.2 10-8 rounds (`p5_ten_eight_by_year.png`)
- The raw rate is 2.4% before 2017 and 3.8% after (OR 1.60, 95% CI 1.28–1.99).
- **Adjusted for round stats**, the post-2017 odds of a 10-8 are **2.4×** higher (CI 1.9–3.1).
- The year-by-year picture is more interesting than a single before/after number: 10-8s **peaked at about 5–6% in 2017–2020, then fell back to about 1.5–2% by 2025–2026.**
- Note: 2006–2010 have thin round-score coverage, and the near-zero rates in 2009–2010 may partly reflect that.

### 3.3 Robbery rates over time (`p5_robbery_by_year.png`)
- 2011–2016 vs. 2017–2026: Robbery tier 6.2% vs. 5.3% (OR 0.84, CI 0.62–1.12). Questionable-or-worse 13.8% vs. 15.7% (OR 1.16, CI 0.95–1.42).
- **No clear change.**
- These are associations. Fighter styles, the mix of commissions, the venue and the pool of judges all changed over the same period.

## 4. Data checks done this phase
- **Face-validity matcher bug:** a variable-name clash meant only 7 of 13 debated decisions matched. Fixed, and one fight-year corrected.
- **Said Nurmagomedov vs. Scoggins:** the media picks are oriented correctly and UFCStats really records a 65–32 strike count for Nurmagomedov. It stays on the list as a genuine model-vs-media disagreement, flagged for a manual check.
- **The "limited corroboration" flag** (before 2008, or fewer than 3 media scores) is now on the Robbery Index, as approved.

## 5. Questions for you
1. **Phase 6 (betting odds):** do you want it? It would allow the betting-favorite test and separate "red corner" from "favorite". It needs a scrape of historical closing odds (likely BestFightOdds, about 30–45 minutes). I'd first check its robots.txt and terms, and stop if scraping isn't allowed.
2. **Manual spot-check:** do you want to eyeball the top 3–5 "media vs. stats" disagreements (such as Scoggins vs. Nurmagomedov) before the site names them, or should the site present them with the standard caveat?
