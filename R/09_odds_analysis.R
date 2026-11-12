# 09_odds_analysis.R: betting-market extension (brief section 10).
#
# 1. Link BestFightOdds lines to UFC fights (date +/- 1 day, both names).
# 2. Market probability = de-vigged closing line: each side's implied
#    probability at the middle of its closing range, rescaled so both sides sum to 1.
# 3. Judges vs. the favourite: controlling for round stats, do judges lean
#    toward the betting favourite? Does the red-corner lean survive that control?
# 4. Does the market price "decision risk"? Fighters who have historically won
#    on the cards more than the stats predicted: are they under- or over-valued?

suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(purrr); library(stringr) })

parse_bfo_date <- function(x) as.Date(str_replace(x, "(\\d+)(st|nd|rd|th)", "\\1"), format = "%b %d %Y")

bfo_parse_all <- function(files) {
  map_dfr(files, \(f) tryCatch(bfo_parse_fighter(f), error = \(e) NULL)) |>
    mutate(date = parse_bfo_date(date_text)) |>
    filter(!is.na(date))
}

# One row per BFO matchup (the same fight appears on both fighters' pages).
bfo_matchups <- function(bfo_raw) {
  mid <- \(lo, hi) rowMeans(cbind(american_to_prob(lo), american_to_prob(hi)), na.rm = TRUE)
  bfo_raw |>
    mutate(p_f_close = mid(f_close_lo, f_close_hi), p_o_close = mid(o_close_lo, o_close_hi),
           p_f_open = american_to_prob(f_open), p_o_open = american_to_prob(o_open),
           k1 = normalize_name(fighter), k2 = normalize_name(opponent),
           pair = if_else(k1 < k2, paste(k1, k2, sep = "|"), paste(k2, k1, sep = "|"))) |>
    filter(!is.na(p_f_close), !is.na(p_o_close), is.finite(p_f_close), is.finite(p_o_close)) |>
    distinct(pair, date, .keep_all = TRUE)
}

# Link to UFC fights: same date (+/- 1 day) and both names similar, either order.
link_odds <- function(matchups, ufc_fights) {
  u <- ufc_fights |> filter(date >= BFO_SINCE) |>
    select(fight_url, date, fighter_a, fighter_b) |>
    mutate(lo = date - 1, hi = date + 1)
  cand <- inner_join(u, matchups |> select(bfo_date = date, fighter, opponent, p_f_close, p_o_close, p_f_open, p_o_open),
                     by = join_by(between(y$bfo_date, x$lo, x$hi))) |>
    mutate(s_same = pmin(name_sim(fighter_a, fighter), name_sim(fighter_b, opponent)),
           s_swap = pmin(name_sim(fighter_a, opponent), name_sim(fighter_b, fighter)),
           a_is_f = s_same >= s_swap, sim = pmax(s_same, s_swap)) |>
    filter(sim >= 0.85)
  cand |>
    arrange(desc(sim)) |>
    distinct(fight_url, .keep_all = TRUE) |>
    mutate(pa_raw = if_else(a_is_f, p_f_close, p_o_close), pb_raw = if_else(a_is_f, p_o_close, p_f_close),
           pa_open_raw = if_else(a_is_f, p_f_open, p_o_open), pb_open_raw = if_else(a_is_f, p_o_open, p_f_open),
           overround = pa_raw + pb_raw,
           mkt_p_a = pa_raw / overround,
           mkt_p_a_open = pa_open_raw / (pa_open_raw + pb_open_raw)) |>
    filter(overround > 0.9, overround < 1.25) |>      # drop broken lines
    select(fight_url, mkt_p_a, mkt_p_a_open, overround, link_sim = sim)
}

odds_coverage <- function(odds, fight_table, ufc_fights) {
  dec <- fight_table |> filter(date >= BFO_SINCE) |> mutate(has_odds = fight_url %in% odds$fight_url)
  all <- ufc_fights |> filter(date >= BFO_SINCE) |> mutate(has_odds = fight_url %in% odds$fight_url)
  list(by_year = dec |> mutate(year = as.integer(format(date, "%Y"))) |> group_by(year) |>
         summarise(decisions = n(), with_odds = mean(has_odds), .groups = "drop"),
       decisions = c(n = nrow(dec), with_odds = sum(dec$has_odds)),
       all_fights = c(n = nrow(all), with_odds = sum(all$has_odds)),
       # Sanity check: favourites should win about as often as the market says.
       favourite_check = ufc_fights |> inner_join(odds, by = "fight_url") |>
         filter(outcome_a %in% c("W", "L")) |>
         mutate(p_fav = pmax(mkt_p_a, 1 - mkt_p_a), fav_won = (mkt_p_a >= 0.5) == (outcome_a == "W"),
                bin = cut(p_fav, c(0.5, 0.6, 0.7, 0.8, 0.9, 1), include.lowest = TRUE)) |>
         group_by(bin) |> summarise(n = n(), market = mean(p_fav), observed = mean(fav_won), .groups = "drop"))
}

# Judges vs. the favourite (round level, judge random intercepts).
favourite_effects <- function(judge_table, odds) {
  d <- judge_table |> filter(date >= CORNER_KNOWN_FROM) |> inner_join(odds, by = "fight_url") |>
    mutate(mkt_logit = qlogis(pmin(pmax(mkt_p_a, 0.01), 0.99)),
           red_is_fav = mkt_p_a >= 0.5,
           close = abs(p_a - 0.5) <= 0.15)
  fit <- \(f, data) {
    m <- lme4::glmer(f, data = data, family = binomial(), control = lme4::glmerControl(optimizer = "bobyqa"))
    tibble::tibble(term = names(lme4::fixef(m)), est = lme4::fixef(m), se = sqrt(diag(as.matrix(vcov(m)))))
  }
  list(
    n_rows = nrow(d), n_fights = n_distinct(d$fight_url),
    red_fav_share = mean(distinct(d, fight_url, .keep_all = TRUE)$red_is_fav),
    # (1) red corner only, same sample (for comparison)
    corner_only = fit(ya ~ 1 + logit_p + (1 | judge_key), d),
    # (2) add the market: does the favourite get extra, and does red-corner survive?
    with_market = fit(ya ~ 1 + logit_p + mkt_logit + (1 | judge_key), d),
    # (3) close rounds only
    close_rounds = fit(ya ~ 1 + logit_p + mkt_logit + (1 | judge_key), filter(d, close)),
    # (4) with experience/record controls too
    full = fit(ya ~ 1 + logit_p + mkt_logit + d_exp + d_winrate + title_fight + (1 | judge_key), d)
  )
}

# Fighter "card premium" before each fight: shrunken mean of (official decision
# result - model probability) over the fighter's *earlier* UFC decisions.
card_premium <- function(robbery_index, k = 3) {
  bind_rows(
    robbery_index |> filter(winner != "draw") |>
      transmute(fighter = fighter_a, date, resid = (winner == "a") - p_a / (p_a + p_b)),
    robbery_index |> filter(winner != "draw") |>
      transmute(fighter = fighter_b, date, resid = (winner == "b") - p_b / (p_a + p_b))
  ) |> arrange(fighter, date)
}

premium_before <- function(prem, fighters, dates, k = 3) {
  map2_dbl(fighters, dates, \(f, d) {
    r <- prem$resid[prem$fighter == f & prem$date < d]
    sum(r) / (length(r) + k)
  })
}

# Does the market price decision risk? Outcome ~ market logit + difference in
# prior card premium. A positive coefficient means fighters who habitually
# "win on the cards" beat their closing odds (the market undervalues them).
decision_risk_test <- function(ufc_fights, odds, robbery_index, k = 3) {
  prem <- card_premium(robbery_index)
  d <- ufc_fights |> filter(date >= CORNER_KNOWN_FROM) |> inner_join(odds, by = "fight_url") |>
    filter(outcome_a %in% c("W", "L")) |>
    mutate(ya = as.numeric(outcome_a == "W"), mkt_logit = qlogis(pmin(pmax(mkt_p_a, 0.01), 0.99)))
  d$prem_a <- premium_before(prem, d$fighter_a, d$date, k)
  d$prem_b <- premium_before(prem, d$fighter_b, d$date, k)
  d <- d |> mutate(d_prem = prem_a - prem_b)
  run <- \(data, label) {
    m <- glm(ya ~ mkt_logit + d_prem, family = binomial(), data = data)
    V <- sandwich::vcovHC(m, type = "HC1")
    tibble::tibble(sample = label, term = names(coef(m)), est = coef(m), se = sqrt(diag(V)), n = nrow(data))
  }
  bind_rows(run(d, "All fights with odds"),
            run(filter(d, is_decision), "Fights that went to decision"),
            run(filter(d, !is_decision), "Fights that ended early"))
}

# How often was the official winner the betting favourite, by Robbery tier?
robbery_vs_market <- function(robbery_index, odds) {
  robbery_index |> filter(winner != "draw") |>
    inner_join(odds, by = "fight_url") |>
    mutate(winner_mkt = if_else(winner == "a", mkt_p_a, 1 - mkt_p_a),
           winner_was_fav = winner_mkt > 0.5) |>
    group_by(tier) |>
    summarise(n = n(), winner_was_favourite = mean(winner_was_fav),
              mean_winner_mkt = mean(winner_mkt), .groups = "drop")
}

# Does the red corner beat its closing odds? (Corner-known fights only.) The odd
# cubic term lets the market's favourite-longshot curve bend symmetrically, so
# the intercept is a pure red-corner effect.
red_vs_market <- function(ufc_fights, odds) {
  d <- ufc_fights |> filter(date >= CORNER_KNOWN_FROM, outcome_a %in% c("W", "L")) |>
    inner_join(odds, by = "fight_url") |>
    mutate(ya = as.numeric(outcome_a == "W"), m = qlogis(pmin(pmax(mkt_p_a, 0.01), 0.99)))
  fit <- glm(ya ~ m + I(m^3), family = binomial(), data = d)
  V <- sandwich::vcovHC(fit, type = "HC1")
  list(n = nrow(d), red_win = mean(d$ya), red_mkt = mean(d$mkt_p_a),
       coefs = tibble::tibble(term = names(coef(fit)), est = coef(fit), se = sqrt(diag(V))),
       by_side = d |> mutate(red_fav = mkt_p_a >= 0.5, p_fav = pmax(mkt_p_a, 1 - mkt_p_a),
                             fav_won = (mkt_p_a >= 0.5) == (ya == 1)) |>
         group_by(red_fav) |> summarise(n = n(), market = mean(p_fav), observed = mean(fav_won), .groups = "drop"))
}
