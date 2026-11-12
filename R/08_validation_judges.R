# 08_validation_judges.R: validation (brief section 7), judge analysis (section 8)
# and the 2017 judging-criteria update (section 9).
#
# Language rule: results describe *agreement with the statistical model*, never
# judge quality or intent. Every judge-level number uses a minimum sample
# (MIN_JUDGE_ROUNDS) and shrinkage (mixed models with judge random effects).

suppressPackageStartupMessages({ library(dplyr); library(tidyr); library(purrr) })

MIN_JUDGE_ROUNDS <- 100
MIN_MEDIA <- 5

# Decisions widely debated at the time (used only as a face-validity check, never
# as model input). Matched by both surnames and the event date's year.
DEBATED_DECISIONS <- tibble::tribble(
  ~winner,        ~loser,        ~year, ~type,
  "St-Pierre",    "Hendricks",   2013,  NA,
  "Jones",        "Reyes",       2020,  NA,
  "Volkanovski",  "Holloway",    2020,  NA,
  "Sanchez",      "Pearson",     2014,  NA,
  "Jackson",      "Machida",     2010,  NA,
  "Bisping",      "Hamill",      2007,  NA,
  "Condit",       "Diaz",        2012,  NA,
  "Henderson",    "Edgar",       2012,  "Split",   # UFC 150 (their UFC 144 fight was unanimous)
  "Henderson",    "Thomson",     2014,  NA,
  "Pokrajac",     "Maldonado",   2012,  NA,
  "Garcia",       "Phan",        2010,  NA,
  "Machida",      "Rua",         2009,  NA,
  "Iaquinta",     "Masvidal",    2015,  NA
)

boot_ci <- function(x, f, reps = 1000, cluster = NULL) {
  idx <- if (is.null(cluster)) as.list(seq_len(nrow(x))) else split(seq_len(nrow(x)), cluster)
  vals <- map_dbl(seq_len(reps), \(r) f(x[unlist(idx[sample(length(idx), replace = TRUE)]), ]))
  unname(quantile(vals, c(0.025, 0.975)))
}

# ---- 7.1 Media scorecards --------------------------------------------------------

media_validation <- function(robbery_index, reps = 1000) {
  d <- robbery_index |> filter(winner != "draw", coalesce(media_scored, 0L) >= MIN_MEDIA)
  pear <- \(x) cor(x$robbery_score, x$media_loser_share)
  spear <- \(x) cor(x$robbery_score, x$media_loser_share, method = "spearman")
  # Who does the media majority side with? Compare the model's favourite and
  # the official winner against the media majority (fights with a clear majority).
  maj <- d |>
    mutate(media_side = case_when(media_a > media_b ~ "a", media_b > media_a ~ "b", TRUE ~ NA_character_),
           model_side = if_else(p_a >= p_b, "a", "b")) |>
    filter(!is.na(media_side))
  tibble::tibble(
    n_fights = nrow(d),
    pearson = pear(d), pearson_lo = boot_ci(d, pear, reps)[1], pearson_hi = boot_ci(d, pear, reps)[2],
    spearman = spear(d), spearman_lo = boot_ci(d, spear, reps)[1], spearman_hi = boot_ci(d, spear, reps)[2],
    n_majority = nrow(maj),
    official_agrees_media = mean(maj$winner == maj$media_side),
    model_agrees_media = mean(maj$model_side == maj$media_side),
    model_agrees_official = mean(maj$model_side == maj$winner)
  )
}

# Biggest disagreements between model and media, in both directions.
media_disagreements <- function(robbery_index, n = 15) {
  d <- robbery_index |>
    filter(winner != "draw", coalesce(media_scored, 0L) >= MIN_MEDIA) |>
    mutate(gap = robbery_score - media_loser_share)
  list(
    model_not_media = d |> arrange(desc(gap)) |> head(n),   # stats favour loser; media sided with winner
    media_not_model = d |> arrange(gap) |> head(n)          # media favoured loser; stats backed the winner
  )
}

# ---- 7.2 Round-level agreement ------------------------------------------------------

round_agreement <- function(model_data, round_probs) {
  j <- model_data |>
    filter(is.na(drop_reason)) |>
    inner_join(round_probs |> select(fight_url, round, p_a), by = c("fight_url", "round")) |>
    mutate(model_side = if_else(p_a >= 0.5, "a", "b"))
  per_round <- j |>
    group_by(fight_url, round) |>
    filter(n() == 3) |>
    summarise(k_a = sum(judge_winner == "a"), model_side = first(model_side), p_a = first(p_a), .groups = "drop") |>
    mutate(majority = if_else(k_a >= 2, "a", "b"))
  # A single judge vs. the other two, when those two agree (a benchmark for
  # how often one well-informed scorer matches a two-judge consensus).
  peer <- j |>
    group_by(fight_url, round) |>
    filter(n() == 3) |>
    mutate(others_a = sum(judge_winner == "a") - (judge_winner == "a")) |>
    ungroup() |>
    filter(others_a %in% c(0, 2)) |>
    mutate(others = if_else(others_a == 2, "a", "b"))
  tibble::tibble(
    rounds = nrow(per_round),
    model_vs_majority = mean(per_round$model_side == per_round$majority),
    model_vs_majority_unanimous = mean((per_round$model_side == per_round$majority)[per_round$k_a %in% c(0, 3)]),
    model_vs_majority_split = mean((per_round$model_side == per_round$majority)[per_round$k_a %in% c(1, 2)]),
    model_vs_individual = mean(j$model_side == j$judge_winner),
    judge_vs_other_two = mean(peer$judge_winner == peer$others),
    model_vs_other_two = mean(peer$model_side == peer$others)
  )
}

face_validity <- function(robbery_index) {
  ri <- robbery_index |> filter(winner != "draw") |>
    mutate(pct_rank = percent_rank(robbery_score), rank = min_rank(desc(robbery_score)),
           yr = as.integer(format(date, "%Y")),
           w_sn = normalize_name(winner_name), l_sn = normalize_name(loser_name))
  DEBATED_DECISIONS |>
    pmap_dfr(\(winner, loser, year, type) {
      w <- normalize_name(winner); l <- normalize_name(loser)
      ri |> filter(yr == .env$year, stringr::str_detect(w_sn, stringr::fixed(w)),
                   stringr::str_detect(l_sn, stringr::fixed(l)),
                   is.na(.env$type) | decision_type == .env$type) |>
        select(date, event, winner_name, loser_name, decision_type, robbery_score, tier, rank, pct_rank,
               media_loser_share, media_scored) |>
        mutate(query = paste(winner, "def.", loser, year))
    })
}

# ---- 8. Judge analysis -----------------------------------------------------------------

# Judge rows with the out-of-fold model probability for the round.
judge_round_table <- function(model_data, round_probs, fighter_exp) {
  model_data |>
    filter(is.na(drop_reason)) |>
    inner_join(round_probs |> select(fight_url, round, p_a), by = c("fight_url", "round")) |>
    left_join(fighter_exp, by = "fight_url") |>
    group_by(fight_url) |>
    mutate(final_round = round == max(round)) |>
    ungroup() |>
    mutate(ya = as.numeric(y == "a"),
           logit_p = qlogis(pmin(pmax(p_a, 1e-4), 1 - 1e-4)),
           p_fav = pmax(p_a, 1 - p_a),
           logit_fav = qlogis(pmin(p_fav, 1 - 1e-4)),
           agree = as.numeric(judge_winner == if_else(p_a >= 0.5, "a", "b")),
           judge_key = paste0(judge_id))
}

# 8.1 Agreement with the model, adjusted for round closeness, with judge random
# intercepts (empirical-Bayes shrinkage toward the league average).
judge_agreement <- function(jt) {
  m <- lme4::glmer(agree ~ logit_fav + (1 | judge_key), data = jt, family = binomial(),
                   control = lme4::glmerControl(optimizer = "bobyqa"))
  re <- lme4::ranef(m, condVar = TRUE)$judge_key
  se <- sqrt(attr(re, "postVar")[1, 1, ])
  ref_logit <- qlogis(0.75)   # a typical round: model favours one fighter 75/25
  b <- lme4::fixef(m)
  base <- b[[1]] + b[[2]] * ref_logit
  stats <- jt |> group_by(judge_key) |>
    summarise(judge = first(judge), rounds = n(), fights = n_distinct(fight_url),
              raw_agree = mean(agree), expected_agree = mean(p_fav),
              first_year = min(year), last_year = max(year), .groups = "drop")
  tibble::tibble(judge_key = rownames(re), re = re[, 1], re_se = se) |>
    inner_join(stats, by = "judge_key") |>
    mutate(adj_agree = plogis(base + re), adj_lo = plogis(base + re - 1.96 * re_se),
           adj_hi = plogis(base + re + 1.96 * re_se),
           league_adj_agree = plogis(base),
           eligible = rounds >= MIN_JUDGE_ROUNDS) |>
    arrange(desc(adj_agree))
}

# 8.2 Do judges weight grappling vs. striking differently? Split the round
# model's linear predictor (Phase 3 logistic) into a striking and a grappling
# part, and let each judge have their own multiplier on each (random slopes).
judge_tendencies <- function(jt, logit_effects) {
  b <- setNames(logit_effects$beta, logit_effects$feature)
  strike <- c("d_kd", "d_head_l", "d_body_l", "d_leg_l", "d_clinch_l", "d_ground_l", "d_nonsig_l", "d_sig_acc")
  grap <- c("d_td_l", "d_td_fail", "d_sub_att", "d_rev", "d_ctrl_min")
  X <- as.matrix(jt[, c(strike, grap)])
  d <- jt |> mutate(S = drop(X[, strike] %*% b[strike]), G = drop(X[, grap] %*% b[grap]))
  m <- lme4::glmer(ya ~ 1 + S + G + (0 + S + G || judge_key), data = d, family = binomial(),
                   control = lme4::glmerControl(optimizer = "bobyqa"))
  fe <- lme4::fixef(m)
  re <- lme4::ranef(m, condVar = TRUE)$judge_key
  pv <- attr(re, "postVar")
  # With `||`, lme4 stores each term separately; pull the matching SEs.
  se_of <- \(term) {
    if (is.list(pv)) sqrt(pv[[which(colnames(re) == term)]][1, 1, ]) else sqrt(pv[which(colnames(re) == term), which(colnames(re) == term), ])
  }
  stats <- d |> group_by(judge_key) |> summarise(judge = first(judge), rounds = n(), .groups = "drop")
  tibble::tibble(judge_key = rownames(re), s_re = re[, "S"], g_re = re[, "G"],
                 s_se = se_of("S"), g_se = se_of("G")) |>
    inner_join(stats, by = "judge_key") |>
    mutate(strike_w = fe[["S"]] + s_re, grap_w = fe[["G"]] + g_re,
           # Relative grappling emphasis: judge's grappling multiplier over striking multiplier,
           # normalised so the league average is 1. Interval from the grappling term only (approx.).
           grap_emphasis = (grap_w / strike_w) / (fe[["G"]] / fe[["S"]]),
           grap_lo = ((fe[["G"]] + g_re - 1.96 * g_se) / strike_w) / (fe[["G"]] / fe[["S"]]),
           grap_hi = ((fe[["G"]] + g_re + 1.96 * g_se) / strike_w) / (fe[["G"]] / fe[["S"]]),
           eligible = rounds >= MIN_JUDGE_ROUNDS) |>
    structure(fixef = fe)
}

# Prior UFC experience for each fighter at each fight (all UFC fights back to
# 1993, not just the analysis window). Used as a control in the corner analysis.
fighter_experience <- function(greco) {
  all_f <- clean_greco_fights(greco) |> filter(!is.na(date))
  long <- bind_rows(
    all_f |> transmute(fight_url, date, fighter = fighter_a, side = "a", win = outcome_a == "W"),
    all_f |> transmute(fight_url, date, fighter = fighter_b, side = "b", win = outcome_a == "L")
  ) |>
    arrange(fighter, date) |>
    group_by(fighter) |>
    mutate(prior_fights = row_number() - 1L, prior_wins = cumsum(win) - win) |>
    ungroup()
  long |>
    select(fight_url, side, prior_fights, prior_wins) |>
    pivot_wider(names_from = side, values_from = c(prior_fights, prior_wins)) |>
    mutate(d_exp = log1p(prior_fights_a) - log1p(prior_fights_b),
           d_winrate = (prior_wins_a + 1) / (prior_fights_a + 2) - (prior_wins_b + 1) / (prior_fights_b + 2))
}

# 8.3 Red corner and title-fight effects, controlling for round stats (the
# model's out-of-fold logit) and prior UFC experience. Fixed effects give the
# league-wide shift toward fighter A (listed first = red corner); the judge
# random intercept gives each judge's own lean, shrunk toward the average.
corner_effects <- function(jt) {
  m0 <- glm(ya ~ 1 + logit_p, family = binomial(), data = jt)
  m1 <- lme4::glmer(ya ~ 1 + title_fight + logit_p + d_exp + d_winrate + (1 | judge_key),
                    data = jt, family = binomial(), control = lme4::glmerControl(optimizer = "bobyqa"))
  V0 <- sandwich::vcovCL(m0, cluster = jt$fight_url)
  fe <- lme4::fixef(m1); se <- sqrt(diag(as.matrix(vcov(m1))))
  re <- lme4::ranef(m1, condVar = TRUE)$judge_key
  re_se <- sqrt(attr(re, "postVar")[1, 1, ])
  by_era <- jt |> mutate(era = if_else(post_2017, "2017-2026", "2006-2016")) |>
    group_by(era) |>
    group_modify(\(d, k) {
      m <- glm(ya ~ 1 + title_fight + logit_p + d_exp + d_winrate, family = binomial(), data = d)
      V <- sandwich::vcovCL(m, cluster = d$fight_url)
      tibble::tibble(term = names(coef(m)), est = coef(m), se = sqrt(diag(V)))
    }) |> ungroup()
  stats <- jt |> group_by(judge_key) |> summarise(judge = first(judge), rounds = n(), .groups = "drop")
  list(
    simple = tibble::tibble(term = names(coef(m0)), est = coef(m0), se = sqrt(diag(V0))),
    full = tibble::tibble(term = names(fe), est = fe, se = se),
    by_era = by_era,
    judges = tibble::tibble(judge_key = rownames(re), re = re[, 1], re_se = re_se) |>
      inner_join(stats, by = "judge_key") |>
      mutate(eligible = rounds >= MIN_JUDGE_ROUNDS),
    re_sd = attr(lme4::VarCorr(m1)$judge_key, "stddev")[[1]],
    n_rows = nrow(jt), n_fights = n_distinct(jt$fight_url)
  )
}

# 8.3 Late-round recency (fight level): does winning the final round (by the
# model) predict the official result beyond the full simulated probability?
# The first round is tested the same way as a comparison.
recency_test <- function(robbery_index, round_probs) {
  edges <- round_probs |>
    group_by(fight_url) |>
    arrange(round, .by_group = TRUE) |>
    summarise(first_edge = first(p_a) - mean(p_a), last_edge = last(p_a) - mean(p_a), .groups = "drop")
  d <- robbery_index |>
    filter(winner != "draw") |>
    inner_join(edges, by = "fight_url") |>
    mutate(ya = as.numeric(winner == "a"),
           logit_sim = qlogis(pmin(pmax(p_a / (p_a + p_b), 1e-4), 1 - 1e-4)))
  m <- glm(ya ~ logit_sim + first_edge + last_edge, family = binomial(), data = d)
  tibble::tibble(term = names(coef(m)), est = coef(m), se = sqrt(diag(vcov(m))),
                 p = summary(m)$coefficients[, 4], n = nrow(d))
}

# ---- 9. 2017 criteria ----------------------------------------------------------------------

# Round model with era interactions: does the weight on each stat change after
# the criteria update? Clustered SEs; joint Wald test on all interactions.
criteria_era_model <- function(model_data, drop_2017 = FALSE, unit_feature = "d_head_l") {
  d <- model_data |> filter(is.na(drop_reason)) |> mutate(ya = as.numeric(y == "a"), post = as.numeric(post_2017))
  if (drop_2017) d <- filter(d, year != 2017)
  f <- reformulate(c(ROUND_FEATURES, paste0(ROUND_FEATURES, ":post")), response = "ya", intercept = FALSE)
  m <- glm(f, family = binomial(), data = d)
  V <- sandwich::vcovCL(m, cluster = d$fight_url)
  b <- coef(m)
  int <- grep(":post$", names(b), value = TRUE)
  wald <- drop(t(b[int]) %*% solve(V[int, int]) %*% b[int])
  # Exchange rates (in head strikes) for each era, delta-method CIs.
  rate <- \(feat, post) {
    num <- c(feat, if (post) paste0(feat, ":post"))
    den <- c(unit_feature, if (post) paste0(unit_feature, ":post"))
    bn <- sum(b[num]); bd <- sum(b[den]); r <- bn / bd
    g <- setNames(rep(0, length(b)), names(b))
    g[num] <- g[num] + 1 / bd
    g[den] <- g[den] - bn / bd^2
    c(r, sqrt(drop(t(g) %*% V %*% g)), bn)
  }
  rates <- map_dfr(ROUND_FEATURES, \(f) map_dfr(c(FALSE, TRUE), \(p) {
    r <- rate(f, p)
    tibble::tibble(feature = f, era = if (p) "2017-2026" else "Before 2017",
                   beta = r[3], head_equiv = r[1], lo = r[1] - 1.96 * r[2], hi = r[1] + 1.96 * r[2])
  }))
  inter <- tibble::tibble(feature = sub(":post$", "", int), shift = b[int], se = sqrt(diag(V)[int])) |>
    mutate(z = shift / se, p = 2 * pnorm(-abs(z)))
  list(rates = rates, interactions = inter, wald_chi2 = wald, wald_df = length(int),
       wald_p = pchisq(wald, length(int), lower.tail = FALSE), n = nrow(d), drop_2017 = drop_2017)
}

# 10-8 rate by year (raw), and the era effect adjusted for round stats.
ten_eight_trend <- function(ten_eight_data) {
  by_year <- ten_eight_data |> group_by(year) |>
    summarise(rounds = n(), rate = mean(ten_eight), .groups = "drop")
  m <- glm(TEN_EIGHT_FORMULA, family = binomial(), data = ten_eight_data)
  V <- sandwich::vcovCL(m, cluster = ten_eight_data$fight_url)
  b <- coef(m)[["post_2017TRUE"]]; se <- sqrt(V["post_2017TRUE", "post_2017TRUE"])
  m_raw <- glm(ten_eight ~ post_2017, family = binomial(), data = ten_eight_data)
  V_raw <- sandwich::vcovCL(m_raw, cluster = ten_eight_data$fight_url)
  list(by_year = by_year,
       adjusted_or = exp(b), adjusted_lo = exp(b - 1.96 * se), adjusted_hi = exp(b + 1.96 * se),
       raw_or = exp(coef(m_raw)[[2]]),
       raw_lo = exp(coef(m_raw)[[2]] - 1.96 * sqrt(V_raw[2, 2])), raw_hi = exp(coef(m_raw)[[2]] + 1.96 * sqrt(V_raw[2, 2])),
       pre_rate = mean(ten_eight_data$ten_eight[!ten_eight_data$post_2017]),
       post_rate = mean(ten_eight_data$ten_eight[ten_eight_data$post_2017]))
}

# Robbery-tier shares by year, and a pre/post comparison for 2011-2026 (years
# with good scorecard and media coverage).
robbery_trend <- function(robbery_index) {
  ri <- robbery_index |> filter(winner != "draw") |> mutate(year = as.integer(format(date, "%Y")))
  by_year <- ri |> group_by(year) |>
    summarise(decisions = n(), robbery = mean(tier == "Robbery"),
              questionable_or_worse = mean(tier %in% c("Questionable", "Robbery")),
              mean_score = mean(robbery_score), split_share = mean(decision_type == "Split"), .groups = "drop")
  d <- ri |> filter(year >= 2011) |> mutate(post = date >= CRITERIA_2017)
  m1 <- glm(I(tier == "Robbery") ~ post, family = binomial(), data = d)
  m2 <- glm(I(tier %in% c("Questionable", "Robbery")) ~ post, family = binomial(), data = d)
  ci <- \(m) { b <- coef(m)[[2]]; s <- sqrt(vcov(m)[2, 2]); exp(c(b, b - 1.96 * s, b + 1.96 * s)) }
  list(by_year = by_year,
       pre_post = d |> group_by(post) |>
         summarise(n = n(), robbery = mean(tier == "Robbery"),
                   questionable_or_worse = mean(tier %in% c("Questionable", "Robbery")),
                   mean_score = mean(robbery_score), .groups = "drop"),
       or_robbery = ci(m1), or_q_or_worse = ci(m2))
}
