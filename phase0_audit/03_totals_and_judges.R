suppressPackageStartupMessages(library(tidyverse))
d <- commandArgs(TRUE)[1]
ev <- read_csv(file.path(d,"ufc_event_details.csv"), show_col_types=FALSE) |> mutate(EVENT=str_squish(EVENT), date=mdy(DATE))
res <- read_csv(file.path(d,"ufc_fight_results.csv"), show_col_types=FALSE) |> mutate(across(c(EVENT,BOUT,METHOD,DETAILS,OUTCOME), str_squish)) |>
  left_join(ev |> select(EVENT,date), by="EVENT")
cat("3 unmatched events, closest names in event list:\n"); print(ev |> filter(str_detect(EVENT,"Road to UFC|Lopes|Grasso")) |> select(EVENT,date) |> head(8))
dec <- res |> filter(str_detect(METHOD,"^Decision"), is.na(date) | date >= as.Date("2001-01-01"))
cat("\nDecisions 2001+ (incl. unmatched):", nrow(dec), " | W/L:", sum(dec$OUTCOME %in% c("W/L","L/W")), " draws:", sum(dec$OUTCOME=="D/D"), "\n")
cat("Rounds in those decisions:", sum(dec$ROUND), " | judge-fight scores:", sum(str_count(coalesce(dec$DETAILS,""),"\\d+\\s*-\\s*\\d+")), "\n")
j <- dec |> filter(!is.na(DETAILS)) |> mutate(x=str_split(DETAILS,"\\.(?=\\s*[A-Z])|\\.$")) |> unnest(x) |> mutate(x=str_squish(x)) |> filter(x!="") |>
  mutate(judge=str_squish(str_remove(x,"\\s*\\d+\\s*-\\s*\\d+.*$")), rounds=ROUND)
jj <- j |> group_by(judge) |> summarise(fights=n(), rounds=sum(rounds)) |> arrange(desc(fights))
cat("Distinct judges:", nrow(jj), " | judges with >=100 rounds:", sum(jj$rounds>=100), " | >=300 rounds:", sum(jj$rounds>=300), "\n"); print(head(jj,10))
cat("Suspicious judge strings:\n"); print(jj |> filter(str_detect(judge,"\\d|^$|\\.") | nchar(judge)<5) |> head())
