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

## Open questions
- **Modeling design given partial round scores (decide at the Phase 2 checkpoint):** train the round model on rounds that have judge round scores (mostly 2008+), and use card totals for older fights (a likelihood over round assignments consistent with each total) or for validation only. Robbery scores can still be computed for every fight, because the model only needs round stats as inputs.
- Use the BestFightOdds odds extension (Phase 6)? Ask before scraping (about 30–45 min).
