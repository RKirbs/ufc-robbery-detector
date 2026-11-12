# Phase 2: Scrape, Clean, Link

**Date:** 2026-11-12
**Status:** CHECKPOINT. Waiting for approval before Phase 3 (round model).

Every number below comes from `Rscript scripts/phase2_report.R`, run after `targets::tar_make()`.

## 1. Collection
- **MMADecisions:** 4,123 UFC decision pages from 759 UFC events (2001-01-01 to 2026-11-07). All are cached in `data/raw/mmadecisions/`. Pages were fetched one at a time with 1.5–3 s pauses and an honest user agent. 3 transient timeouts were refetched on a rerun, so 0 pages are missing.
- **UFCStats** (Greco1899 mirror, pinned commit): 4,109 decisions in the window, all with complete round-by-round stats.

## 2. Record linkage

| | Fights | Notes |
|---|---|---|
| High confidence | 4,083 (99.0%) | Exact or near-exact names on both fighters, within ±1 day |
| Medium confidence | 26 (0.6%) | **All 26 hand-checked correct.** These are nicknames and aliases: Kimbo Slice = Kevin Ferguson, Jacaré = Ronaldo Souza, Cyborg = Cristiane Justino, Feijão = Rafael Cavalcante, Pitbull = Patricio Freire, Brianna Van Buren = Brianna Fortino, You Su Young = SuYoung You, and others |
| Unmatched | 14 (0.3%) | **All 14 are decisions later overturned** (mostly to no-contests, e.g. Silva vs. Diaz, Lesnar vs. Hunt, CM Punk vs. Jackson). UFCStats records them as "Overturned", so they're correctly excluded |

- **UFCStats decisions linked: 4,109 of 4,109 (100%).**
- **Winner check:** in all 4,109 links, MMADecisions' declared winner matches UFCStats.
- **Random sample of 12 high-confidence links:** all correct. The sample includes cases where the two sources date the same event a day apart (UFC events in Asia/Australia).
- The full non-high list is saved to `data/interim/links_for_review.csv`.

## 3. Coverage by year

| Years | Decisions | Full judge round scores | ≥1 media score | Media scores per fight |
|---|---|---|---|---|
| 2001–2005 | 70 | 0% | 13–37% | 0.1–0.4 |
| 2006–2007 | 114 | 3–4% | 60–86% | 0.8–1.8 |
| 2008–2010 | 280 | 14–27% | ~99% | ~3.8 |
| 2011–2012 | 305 | 67–75% | 100% | 6–7 |
| 2013–2019 | 1,625 | 84–95% | ~100% | 11–17 |
| 2020–2026 | 1,715 | 99–100% | ~100% | 11–17 |

**Totals:** 4,109 decisions; **3,448 with full judge round scores**; 4,020 with at least one media score (**51,355 media scores** in all). **Every** judge card has its total, even when round scores are missing.

## 4. Modeling tables
- **Judge × round table** (`data/interim/judge_rounds.parquet`): **33,482 judge-round scores** across 11,429 rounds in 3,623 fights. Each row has the A−B differentials for that round only: KD, sig. strikes landed/attempted, total strikes, TD landed/attempted, sub attempts, reversals, control time, and head/body/leg/distance/clinch/ground splits. No feature has missing values.
  - Score types: 10-9 95.8%, 10-8 3.7%, 10-10 0.5%, 10-7 0.03%.
  - 427 judges; **49 with ≥100 rounds**, 21 with ≥300. The largest samples are Sal D'Amato (3,572), Derek Cleary (2,291) and Chris Lee (2,071).
- **Fight table** (`data/interim/fight_table.parquet`): one row per decision with the result, each judge's card total oriented to fighter A, media counts for A / B / draw, and flags.

## 5. Consistency checks
- Judge round scores sum to the card total on **10,636 of 10,637** cards.
- The round count on the card matches the rounds fought on UFCStats on **10,575 of 10,594** cards. I'll drop the 19 mismatches and the 1 card that doesn't sum.
- 46 of 51,355 media picks can't be assigned to a fighter (for example, both fighters share a surname). These are dropped.
- 4 very old fights have placeholder judge totals ("1-0"). These are dropped from analyses that use totals.
- **Sanity check:** judges give the round to the fighter who landed more significant strikes in **77.1%** of rounds. That's sensible and shows what the naive baseline will look like.
- **Descriptive only:** red corner (fighter A) wins 56.8% of non-even judge rounds. This is *not* a finding, because red corners are usually the favourite or the champion. It gets tested properly in Phase 5, controlling for stats. *(Correction, 2026-11-12: UFCStats lists the **winner** first through UFC 110 (Feb 2010), and the red corner first only from March 21, 2010. Red-corner figures in this report that include earlier fights are therefore biased upward; see PHASE6_REPORT.md section 1. Corner-symmetric results are unaffected.)*

## 6. Design decision needed: partial round-score coverage before 2013
Judge **round** scores exist for 3,448 of 4,109 decisions (84%), and are thin before 2011. Robbery scores need only round **stats** as inputs, so every decision still gets one. The question is what the model is trained on:

- **Option A (recommended):** train the round model on the 33,482 judge-round scores (mostly 2011+). Apply it to all 4,109 decisions. Use card totals for the older fights as an out-of-sample check (does the model's predicted card match the judges' totals?).
- **Option B:** Option A, plus pulling the ~660 fights that have totals only into training through a likelihood over the round outcomes consistent with each total. This uses more of the early era for the judge analysis, but adds complexity for modest data gain.

The 2017 criteria comparison still works under either option: about 1,500 pre-2017 fights with round scores (2011–2016) against about 2,400 after.
