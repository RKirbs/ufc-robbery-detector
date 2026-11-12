suppressPackageStartupMessages(library(tidyverse))
d <- commandArgs(TRUE)[1]
ev <- read_csv(file.path(d,"ufc_event_details.csv"), show_col_types=FALSE) |> mutate(EVENT=str_squish(EVENT), date=mdy(DATE), year=year(date))
res <- read_csv(file.path(d,"ufc_fight_results.csv"), show_col_types=FALSE) |> mutate(across(c(EVENT,BOUT,METHOD,DETAILS,OUTCOME), str_squish))
st <- read_csv(file.path(d,"ufc_fight_stats.csv"), show_col_types=FALSE) |> mutate(across(c(EVENT,BOUT), str_squish))
cat("Unmatched event names in results:\n"); print(setdiff(unique(res$EVENT), ev$EVENT))
cat("Events with NA date:", sum(is.na(ev$date)), "\n")
# join by URL-free fallback: event-level via fight_details? check dup event names
cat("Duplicate event names:", sum(duplicated(ev$EVENT)), "\n"); print(ev |> filter(EVENT %in% EVENT[duplicated(EVENT)]) |> select(EVENT,DATE))
res <- res |> left_join(ev |> distinct(EVENT,.keep_all=TRUE) |> select(EVENT,date,year), by="EVENT")
dec <- res |> filter(str_detect(METHOD,"^Decision")) |> mutate(n_judges=str_count(coalesce(DETAILS,""), "\\d+\\s*-\\s*\\d+"))
cat("\nJudge-score parse by year (decisions):\n")
print(dec |> group_by(year) |> summarise(n=n(), details_na=sum(is.na(DETAILS)), j3=sum(n_judges==3), other=sum(n_judges!=3 & !is.na(DETAILS))) |> filter(year<=2008 | other>0 | details_na>0), n=40)
cat("\nNon-3-judge DETAILS examples:\n"); print(dec |> filter(n_judges!=3) |> select(year,BOUT,METHOD,DETAILS) |> head(8), width=200)
# zero-padding check: rounds where both fighters 0 sig strikes attempted
num_of <- function(x) as.numeric(str_match(x,"of (\\d+)")[,2])
r <- st |> filter(str_detect(ROUND,"Round")) |> mutate(att=num_of(`SIG.STR.`)) |> group_by(EVENT,BOUT,ROUND) |> summarise(att=sum(att), .groups="drop") |>
  left_join(ev |> distinct(EVENT,.keep_all=TRUE) |> select(EVENT,year), by="EVENT")
cat("\nRounds with 0 total sig strike attempts (both fighters) and mean attempts/round, by year:\n")
print(r |> group_by(year) |> summarise(rounds=n(), zero_rounds=sum(att==0), mean_att=round(mean(att),1)) |> filter(year<=2010 | is.na(year)), n=30)
cat("\nReal example rows:\n")
x <- res |> filter(str_detect(BOUT,"Jones") & str_detect(BOUT,"Reyes"))
print(glimpse(x))
print(st |> filter(BOUT==x$BOUT[1]) |> select(-EVENT), width=250)
