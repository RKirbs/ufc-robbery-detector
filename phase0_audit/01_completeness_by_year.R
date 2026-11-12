suppressPackageStartupMessages(library(tidyverse))
d <- commandArgs(TRUE)[1]
ev <- read_csv(file.path(d,"ufc_event_details.csv"), show_col_types=FALSE) |> mutate(EVENT=str_squish(EVENT), date=mdy(DATE), year=year(date))
res <- read_csv(file.path(d,"ufc_fight_results.csv"), show_col_types=FALSE) |> mutate(across(c(EVENT,BOUT,METHOD,DETAILS,OUTCOME), str_squish))
st <- read_csv(file.path(d,"ufc_fight_stats.csv"), show_col_types=FALSE) |> mutate(across(c(EVENT,BOUT), str_squish))
res <- res |> left_join(ev |> select(EVENT,date,year), by="EVENT")
cat("Unmatched event dates:", sum(is.na(res$date)), "\n")
cat("Freeze candidate (latest event):", format(max(ev$date)), "\n\n")
print(count(res, METHOD, sort=TRUE), n=20)
res <- res |> mutate(is_dec = str_detect(METHOD,"^Decision"),
  n_judges = str_count(DETAILS, "\\d+\\s*-\\s*\\d+"),
  sched_rounds = as.integer(str_extract(`TIME FORMAT`, "^\\d+")))
# per-fight round stats coverage
rs <- st |> filter(str_detect(ROUND,"Round")) |> group_by(EVENT,BOUT) |>
  summarise(n_rounds_stats = n_distinct(ROUND), n_rows=n(),
            ctrl_missing = mean(CTRL %in% c("--","---") | is.na(CTRL)),
            sig_missing = mean(is.na(`SIG.STR.`) | `SIG.STR.` %in% c("--","---")),
            head_missing = mean(is.na(HEAD) | HEAD %in% c("--","---")), .groups="drop")
dec <- res |> filter(is_dec) |> left_join(rs, by=c("EVENT","BOUT")) |>
  mutate(full_rounds = !is.na(n_rounds_stats) & n_rounds_stats==ROUND & n_rows==2*ROUND,
         complete = full_rounds & ctrl_missing==0 & sig_missing==0 & head_missing==0)
cat("\nDecisions with no stats at all:", sum(is.na(dec$n_rounds_stats)), "\n")
tab <- res |> group_by(year) |> summarise(events=n_distinct(EVENT), fights=n(), decisions=sum(is_dec), .groups="drop") |>
  left_join(dec |> group_by(year) |> summarise(
      dec_round_stats_pct = round(100*mean(full_rounds),1),
      dec_complete_pct = round(100*mean(complete),1),
      dec_3judge_pct = round(100*mean(n_judges==3),1),
      ctrl_missing_pct = round(100*mean(ctrl_missing,na.rm=TRUE),1),
      dec_rounds = sum(ROUND[complete]), split=sum(str_detect(METHOD,"Split")), majority=sum(str_detect(METHOD,"Majority")), .groups="drop"), by="year")
print(tab, n=50, width=200)
cat("\nOther outcomes (draws/NC):\n"); print(res |> filter(!OUTCOME %in% c("W/L","L/W")) |> count(OUTCOME, is_dec))
cat("\nTotals 2001+: decisions", sum(dec$is_dec & dec$year>=2001), " complete", sum(dec$complete & dec$year>=2001), " rounds", sum(dec$ROUND[dec$complete & dec$year>=2001]), "\n")
cat("\nExample DETAILS strings:\n"); print(head(dec$DETAILS[dec$year==2008],3)); print(head(dec$DETAILS[dec$n_judges!=3 & dec$year>2005],5))
