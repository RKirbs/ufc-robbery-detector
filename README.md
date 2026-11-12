# The UFC Robbery Detector

*Which UFC decisions did the statistics say the other fighter won?*

> 🚧 Work in progress. Data collection is underway (Phase 2). The full README, with the signature chart, headline findings and the live site link, is written in Phase 7.

## Data sources
- **UFCStats** round-by-round fight statistics, via the [Greco1899/scrape_ufc_stats](https://github.com/Greco1899/scrape_ufc_stats) mirror (pinned commit).
- **MMADecisions.com**: official judge round-by-round scorecards and media scorecards, collected with the site owner's permission.

## Framing note
"Robbery" here means strong disagreement between the official result and what round-by-round statistics predict. It is never an accusation of misconduct against any judge.

## Reproduce
```r
renv::restore()
targets::tar_make()
```
