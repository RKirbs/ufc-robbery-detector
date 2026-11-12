# Phase 0: Data Audit

**Audit date:** 2026-11-11
**Status:** CHECKPOINT. Waiting for approval of the data plan before Phase 1.

Scripts that produced every number here: `phase0_audit/*.R` (run against the Greco1899 CSVs, commit of 2026-11-08).

---

## 1. Source access check

| Source | robots.txt | What an automated request gets | Verdict |
|---|---|---|---|
| **UFCStats.com** | None (404) | A JavaScript proof-of-work "Checking your browser…" page instead of the content (saved in `phase0_audit/ufcstats_bot_challenge_2026-11-11.html`) | **Blocked.** Getting past it means solving a bot challenge in code, which the project's rules forbid. |
| **MMADecisions.com** | `User-agent: *` → `Disallow: /`. Only named search engines are allowed (saved in `phase0_audit/mmadecisions_robots_2026-11-11.txt`) | Normal HTML | **Disallowed by robots.txt. Not scraped.** |
| **BestFightOdds.com** | `Allow: /` (only `/cnadm/` is blocked) | Normal HTML | **OK.** No scraping clause found in its Terms of Service. |
| **Greco1899/scrape_ufc_stats** (GitHub) | n/a (public repo) | CSV files, refreshed daily by the maintainer's own UFCStats scraper | **OK. Proposed replacement for UFCStats.** GPL-3.0 licence. |

Searched for, and **not found**: a free, public dataset of judge-by-judge **round** scores, or of media scorecards. Paid options exist (UFCalendar API, from $19/month with a 1,000-request/month free tier; an Apify UFCStats scraper at about $18 per 1,000 records). I did not verify either, and both cost money.

## 2. What the Greco1899 data contains (it mirrors UFCStats)

- `ufc_event_details.csv`: 796 events, the latest being **UFC Fight Night: Cortes Acosta vs. Walker, 2026-11-07** (the proposed freeze date).
- `ufc_fight_results.csv`: 9,015 fights with result, method, rounds, referee and `DETAILS`. For decisions, `DETAILS` lists **each judge's name and total score for the whole fight**, but **not round by round**.
- `ufc_fight_stats.csv`: 42,356 rows with **round-by-round stats per fighter**: KD, sig. strikes landed/attempted, total strikes, TD, sub attempts, reversals, control time, head/body/leg and distance/clinch/ground splits.
- `ufc_fighter_details.csv`, `ufc_fighter_tott.csv`: fighter names, nicknames, height, reach, stance and date of birth.

### Real example rows: Jon Jones vs. Dominick Reyes, UFC 247 (2020-02-08)

```
METHOD:  Decision - Unanimous   TIME FORMAT: 5 Rnd (5-5-5-5-5)
DETAILS: Marcos Rosales 47 - 48. Chris Lee 47 - 48. Joe Soliz 46 - 49.

ROUND    FIGHTER         KD  SIG.STR.  TOTAL STR.  TD      CTRL  HEAD     BODY    LEG
Round 1  Jon Jones       0   17 of 27  17 of 27    0 of 2  0:00  1 of 5   6 of 8  10 of 14
Round 1  Dominick Reyes  0   23 of 59  23 of 59    0 of 0  0:00  7 of 33  11 of 14 5 of 12
Round 2  Jon Jones       0   22 of 37  22 of 37    0 of 0  0:00  8 of 19  5 of 7   9 of 11
Round 2  Dominick Reyes  0   33 of 68  33 of 68    0 of 0  0:00  11 of 46 12 of 12 10 of 10
...
```
(The judges' totals are written from the perspective of the first-listed fighter in the scraped file, so the scorer's orientation must be parsed carefully in Phase 2.)

## 3. Completeness by year (decisions only)

| Year | Events | Fights | Decisions | Decisions with full round stats | Control time missing | Judge totals present |
|---|---|---|---|---|---|---|
| 1995–1998 | 17 | 149 | 24 | 96% | **100%** | 0% |
| 1999 | 6 | 44 | 11 | 100% | 55% | 0% |
| 2000 | 6 | 43 | 17 | 100% | 0% | 6% |
| 2001 | 5 | 40 | 12 | 100% | 0% | 75% |
| 2002 | 7 | 53 | 15 | 100% | 0% | 87% |
| 2003–2005 | 20 | 160 | 43 | 100% | 0% | 100% |
| 2006 | 18 | 158 | 52 | 100% | 0% | 100% |
| 2010 | 24 | 253 | 124 | 100% | 0% | 100% |
| 2015 | 41 | 473 | 221 | 100% | 0% | 100% |
| 2020 | 41 | 456 | 226 | 100% | 0% | 100% |
| 2025 | 42 | 520 | 256 | 100% | 0% | 100% |
| 2026 (to Nov 7) | 39 | 494 | 209 | 100% | 0% | 100% |

(The full year-by-year table is printed by `phase0_audit/01_completeness_by_year.R`.) No decision round after 1995 is zero-padded: every round has real strike attempts.

**Totals from 2001-01-01 to the freeze date:** 4,121 decisions (4,060 with a winner and 61 draws), **12,976 rounds**, about **12,350 judge-fight scores**, and 53 judges who scored ≥ 100 rounds (before name cleaning).

## 4. Data quirks found

- 3 events are named differently in the results file and the events file (for example "UFC Fight Night: Lopes vs. Silva" vs. "Noche UFC: Lopes vs. Silva"). Fix: join on fight and event URLs, not names.
- Judge names have spelling variants (for example "Sal D'amato"), and 43 decisions have an unparseable or empty judge name. These need a normalisation table in Phase 2.
- 2 decisions have no round stats at all.

## 5. Recommended start date

**2001-01-01.** The UFC adopted the Unified Rules at UFC 28 (November 2000), control time is recorded from 2000 onward, and judge totals are mostly present from 2001 and complete from 2003. Because samples before 2005 are tiny (10–19 decisions a year), report a sensitivity check that starts in 2005.

## 6. Estimated download time

- Greco1899 CSVs: about 12 MB, under a minute. No scraping needed.
- BestFightOdds (only if Phase 6 is approved): about 500–700 event pages at 2–3 s each, so roughly **30–45 minutes**. I'll ask before running it.

## 7. Decisions needed (see the chat for the full trade-offs)

1. Use Greco1899 as the UFCStats source?
2. How to replace round-by-round judge scores (the outcome of the core model).
3. How to replace media scorecards (the key validation).
4. Start date.
