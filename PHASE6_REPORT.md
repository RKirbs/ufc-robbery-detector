# Phase 6: Betting-Market Extension

**Date:** 2026-11-12
**Status:** Done. Phase 7 (the Quarto site) comes next; Rob approved continuing.

Every number below comes from `Rscript scripts/phase6_report.R`, run after `targets::tar_make()`. Figures are in `figures/p6_*.png`.

## 1. Data bug found and fixed: UFCStats fighter order
- While checking the odds data I found that **fighter A won 100% of UFC fights from 2001 through UFC 110 (Feb 20, 2010)**. For those years UFCStats lists the **winner** first, not the red corner. From UFC Live: Vera vs. Jones (Mar 21, 2010) on, fighter A wins 54–63% of fights each year, consistent with the red corner. Only 1 of 641 later events has fighter A winning every fight, which is about the 1.5 you'd expect by chance.
- **Unaffected:** everything corner-symmetric, which is the core of the project. That covers the round model (mirrored training, symmetric predictions), the simulation and Robbery Scores, media validation, judge agreement and tendencies, and the 2017 analysis.
- **Corrected:** everything where "fighter A = red corner" matters now uses only fights from 2010-03-21 on (`CORNER_KNOWN_FROM` in `R/utils.R`). The recency test was made corner-symmetric (no intercept), so its fit is the same whichever fighter is listed first.
- **What changed:**

  | Result | Before | After |
  |---|---|---|
  | Phase 5 red-corner lean on a 50/50 round | +5.6 pts | +4.7 pts |
  | … 2010–2016 | +8.0 pts (labelled 2006–2016) | +6.4 pts |
  | … 2017–2026 | +3.0 pts | +3.0 pts (unchanged) |
  | Phase 4: red corner wins vs. simulation | 61.4% vs. 57.1% | 57.7% vs. 54.4% |
  | Red corner vs. the closing odds | about +5 pts | about +2 pts |

  Correction notes have been added to the Phase 2–5 reports.

## 2. Collection and linkage
- **Source:** BestFightOdds fighter pages. robots.txt allows everything except `/cnadm/`, and the terms of service contain only a warranty disclaimer; copies of both are in `phase0_audit/`.
- **Why fighter pages:** event pages only show today's sportsbooks. Fighter pages list every fight with the opening line and the closing range across books.
- **Collection:** 1,029 fighter pages, chosen by greedy set cover so every UFC decision since 2007 is covered. Fetched at 1.5–3 s per request with an honest user agent and cached (0 errors).
- **Market probability:** the implied probability at the middle of each side's closing range, rescaled so both sides sum to 1. The median bookmaker margin (overround) is 1.04.
- **Linkage:** event date ±1 day plus both fighter names (median name similarity 1.00).
  - **3,776 of 3,987 UFC decisions since 2007 (94.7%)** have closing odds. Coverage is 93–98% in every year except 2007, when BestFightOdds started (48%).
  - 6,924 of 8,310 UFC fights of any kind since 2007 have odds.
- **Sanity check** (`p6_market_calibration.png`): closing lines are well calibrated. Favorites priced at 55% won 55%, and at 65% won 65%. Heavy favorites win a little more often than priced (75% → 78%, 83% → 88%), the well-known favorite–longshot pattern.

## 3. Do judges lean toward the betting favorite? (`p6_favourite_effect.png`)
**Data:** round-level mixed models with judge random intercepts, on corner-known fights with odds (31,319 judge-rounds, 3,358 fights). The red corner was the betting favorite in 61.7% of them.

| On a round the stats call 50/50 … | Extra chance (pts) |
|---|---|
| Red corner, no market control | +4.9 |
| **Red corner, controlling for the betting line** | **+3.7** (95% CI about 2.6–4.8) |
| **Favorite at −300 (75%) vs. an even fight** | **+6.5** (95% CI 5.2–7.8) |
| Favorite at −300, close rounds only | +7.8 |

- **Judges lean toward the betting favorite** beyond what the round stats show, and slightly more so in close rounds.
- About a quarter of the red-corner lean is really a favorite lean; the rest remains after controlling for the line.
- With the line included, the earlier "better prior record" effect disappears (0.05, not significant), so that was the market's view of fighter quality. Experience and title fights add nothing.
- **Interpretation (neutral):** the market prices things the stats can't see, such as power, durability, fight IQ and reputation. Part of this "favorite lean" may be judges seeing the same unmeasured quality the market sees, rather than bias. These are associations, not evidence of intent.

## 4. Does the market price decision risk?
**Test:** does a fighter's **card premium** predict their result beyond the closing line? The premium is the shrunken average, over their *earlier* UFC decisions, of (official result − model probability). In other words, how much more often they won on the cards than the stats said.

| Sample | Premium coefficient | SE | Fights |
|---|---|---|---|
| All fights with odds (from 2010-03) | −0.50 | 0.26 | 6,390 |
| Fights that went to decision | −0.06 | 0.34 | 3,522 |
| **Fights that ended early** | **−1.05** | 0.39 | 2,868 |

- Fighters whose records include more favorable decisions than the stats supported do **not** beat their odds. If anything they **underperform them, and only in fights that end early**: about −2.8 points per standard deviation of the premium. That's consistent with the market slightly **overrating records padded by generous decisions**.
- When their fights go to the cards, they perform about as the market expects.
- Caution: this is one exploratory test, and the all-fights estimate is marginal (p ≈ 0.05). Treat it as suggestive.

## 5. Two more market facts
- **Red corner vs. the closing odds** (corner-known fights): red corners won 57.5% against 55.4% priced. With a symmetric control for the favorite–longshot curve, the red-corner edge is about +2 points (log-odds 0.080, SE 0.028).
  - It appears in **decisions** (+0.12), not in finishes (+0.04, not significant). That's consistent with the judges' red-corner lean flowing through to results.
- **Robberies and favorites:** in the Robbery tier the official winner was the betting favorite in 48% of fights, against 70% in Clean decisions. So statistical robberies don't systematically go to the favorite; they happen in fights the market saw as even (mean winner probability 0.50).

## 6. Notes for the site
- The favorite and red-corner results go on `judges.qmd`. The decision-risk finding goes in a short "Betting markets" section, labelled exploratory.
- The odds source and access check are documented in Methodology.
