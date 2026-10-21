# Matchup situation counts. Calculation functions use base R only.
# Source this file, then use load_matchup_data() and estimate_matchup().

field_groups <- function() {
  list(
    "Backed up (-1 to -20)" = function(y) y >= 80 & y <= 99,
    "Neutral field (-20 to +20)" = function(y) y > 20 & y < 80,
    "Red zone (+20 to goal line)" = function(y) y >= 1 & y <= 20
  )
}

situation_definitions <- function(short_yards = 3L) {
  stopifnot(length(short_yards) == 1L, short_yards == 3L)
  count <- function(z) as.numeric(sum(z)) # Unknown values stay unknown, not zero.
  trips <- function(x, flag = rep(TRUE, nrow(x))) {
    if (anyNA(flag) || anyNA(x$drive[flag])) return(NA_real_)
    as.numeric(length(unique(x$drive[flag])))
  }
  definitions <- list(
    "Total possessions" = function(x) trips(x),
    "1st and 10" = function(x) count(x$down == 1 & x$distance == 10),
    "2nd and 5 or less" = function(x) count(x$down == 2 & x$distance <= 5),
    "2nd and 6 or more" = function(x) count(x$down == 2 & x$distance >= 6),
    "Down plays" = function(x) count(x$down %in% 1:4) + if (anyNA(x$down)) NA_real_ else 0,
    "1st downs" = function(x) count(x$down == 1),
    "2nd downs" = function(x) count(x$down == 2),
    "3rd downs" = function(x) count(x$down == 3),
    "3rd and short" = function(x) count(x$down == 3 & x$distance >= 1 & x$distance <= short_yards),
    "3rd and medium" = function(x) count(x$down == 3 & x$distance >= 4 & x$distance <= 7),
    "3rd and long" = function(x) count(x$down == 3 & x$distance >= 8),
    "High red zone (20-11)" = function(x) count(x$yards_to_goal >= 11 & x$yards_to_goal <= 20),
    "Low red zone (10-5)" = function(x) count(x$yards_to_goal >= 5 & x$yards_to_goal <= 10),
    "Goal line (4-1)" = function(x) count(x$yards_to_goal >= 1 & x$yards_to_goal <= 4),
    "4th downs" = function(x) count(x$down == 4),
    "4th and short" = function(x) count(x$down == 4 & x$distance >= 1 & x$distance <= short_yards),
    "Red-zone plays" = function(x) count(x$yards_to_goal > 0 & x$yards_to_goal <= 20),
    "Red-zone trips" = function(x) trips(x, x$yards_to_goal > 0 & x$yards_to_goal <= 20),
    "Inside-10 plays" = function(x) count(x$yards_to_goal > 0 & x$yards_to_goal <= 10)
  )
  base_definitions <- definitions
  common <- definitions[!names(definitions) %in% c("High red zone (20-11)",
    "Low red zone (10-5)", "Goal line (4-1)", "Red-zone plays",
    "Red-zone trips", "Inside-10 plays")]
  groups <- field_groups()
  for (group in names(groups)) {
    metrics <- if (group == "Red zone (+20 to goal line)") base_definitions else common
    for (metric in names(metrics)) {
      definitions[[paste(group, metric, sep = " | ")]] <- local({
        in_group <- groups[[group]]
        measure <- metrics[[metric]]
        function(x) {
          # Unknown position makes regional counts unavailable for this game.
          if (anyNA(x$yards_to_goal)) return(NA_real_)
          measure(x[in_group(x$yards_to_goal), , drop = FALSE])
        }
      })
    }
  }
  definitions
}

prepare_pbp <- function(pbp, include_overtime = FALSE) {
  if (!is.data.frame(pbp) || nrow(pbp) == 0) stop("No play-by-play data was loaded.")
  pick <- function(options) {
    found <- options[options %in% names(pbp)]
    if (!length(found)) stop("Missing required column: ", paste(options, collapse = " or "))
    pbp[[found[1L]]]
  }
  numeric_value <- function(x) suppressWarnings(as.numeric(as.character(x)))
  x <- data.frame(
    season = pick("season"), game_id = as.character(pick("game_id")),
    team = as.character(pick(c("pos_team", "offense"))),
    opponent = as.character(pick(c("def_pos_team", "defense"))),
    drive = as.character(pick(c("id_drive", "drive_id", "drive_number", "drive_num"))),
    down = numeric_value(pick("down")), distance = numeric_value(pick("distance")),
    yards_to_goal = numeric_value(pick("yards_to_goal")),
    period = numeric_value(pick("period")),
    play_type = if ("play_type" %in% names(pbp)) as.character(pbp$play_type) else rep("", nrow(pbp)), stringsAsFactors = FALSE
  )
  text <- if ("play_text" %in% names(pbp)) as.character(pbp$play_text) else rep("", nrow(x))
  text[is.na(text)] <- ""
  # Some classic-feed rows have neither a play type nor a down (empty markers).
  # Retain untyped rows when their down state identifies a football opportunity.
  untyped <- is.na(x$play_type) | trimws(x$play_type) == ""
  x$play_type[untyped] <- ""
  empty_marker <- untyped & !(x$down %in% 1:4)
  # Exclude administrative rows, kickoffs, extra points, two-point tries and
  # standalone penalties. Keep punts/FGs, kneels, spikes and live-ball penalties.
  admin <- grepl("timeout|end of|end period|end half|end game|kickoff|kick off|extra point|pat\\b|two.point|2.point|conversion|^penalty$|no play|uncategorized", x$play_type, ignore.case = TRUE)
  no_play <- grepl("\\bno[ -]play\\b", text, ignore.case = TRUE)
  text_admin <- untyped & grepl("timeout|end of (quarter|half|game)|kickoff|extra point|two.point|2.point", text, ignore.case = TRUE)
  x <- x[!admin & !no_play & !empty_marker & !text_admin, , drop = FALSE]
  if (!include_overtime) {
    if (anyNA(x$period)) stop("Missing periods: cannot safely exclude overtime.")
    x <- x[x$period <= 4, , drop = FALSE]
  }
  x <- x[is.na(x$down) | x$down %in% 1:4, , drop = FALSE]
  if (!nrow(x)) stop("No down plays remain after filtering.")
  for (col in c("season", "game_id", "team", "opponent")) {
    if (anyNA(x[[col]]) || any(trimws(as.character(x[[col]])) == ""))
      stop("Missing ", col, ": cannot identify team-games reliably.")
  }
  if (any(x$team == x$opponent)) stop("A play lists the same offense and defense.")
  x$drive[!is.na(x$drive) & trimws(x$drive) == ""] <- NA_character_
  x$distance[!is.finite(x$distance) | x$distance < 0] <- NA_real_
  x$yards_to_goal[!is.finite(x$yards_to_goal) | x$yards_to_goal <= 0 | x$yards_to_goal > 100] <- NA_real_
  x
}

build_team_games <- function(pbp, include_overtime = FALSE, short_yards = 3L) {
  x <- prepare_pbp(pbp, include_overtime)
  definitions <- situation_definitions(short_yards)
  keys <- paste(x$season, x$game_id, x$team, x$opponent, sep = "\r")
  rows <- lapply(split(x, keys), function(g) {
    data.frame(season = g$season[1], game_id = g$game_id[1],
               team = g$team[1], opponent = g$opponent[1],
               situation = names(definitions),
               count = vapply(definitions, function(f) f(g), numeric(1)),
               stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  # Every retained team-game has every metric, including zero occurrences.
  out
}

team_profiles <- function(team_games) {
  if (anyNA(team_games$season)) stop("Season is required to weight games.")
  summarize <- function(role) {
    z <- team_games
    if (role == "defense") z$team <- z$opponent
    keys <- interaction(z$team, z$situation, drop = TRUE)
    do.call(rbind, lapply(split(z, keys), function(g) {
      values <- g$count[!is.na(g$count)]
      weights <- ifelse(g$season[!is.na(g$count)] == 2026, 3, 1)
      data.frame(team = g$team[1], situation = g$situation[1], role = role,
                 average = if (length(values)) weighted.mean(values, weights) else NA_real_,
                 games_used = length(values), games_available = nrow(g),
                 stringsAsFactors = FALSE)
    }))
  }
  out <- rbind(summarize("offense"), summarize("defense"))
  rownames(out) <- NULL
  out
}

estimate_matchup <- function(team_games, team_a, team_b) {
  estimate_profiles(team_profiles(team_games), team_a, team_b, unique(team_games$situation))
}

estimate_profiles <- function(profiles, team_a, team_b, order_names = names(situation_definitions())) {
  if (identical(team_a, team_b)) stop("Choose two different teams.")
  available <- unique(profiles$team)
  if (!all(c(team_a, team_b) %in% available)) stop("Selected team is absent from the loaded data.")
  one_side <- function(team, opponent) {
    offense <- profiles[profiles$team == team & profiles$role == "offense", ]
    defense <- profiles[profiles$team == opponent & profiles$role == "defense", ]
    z <- merge(offense, defense, by = "situation", suffixes = c("_off", "_def"), all = TRUE)
    data.frame(team = team, opponent = opponent, situation = z$situation,
      offense_per_game = z$average_off, opponent_defense_per_game = z$average_def,
      expected_count = (z$average_off + z$average_def) / 2,
      offense_games = z$games_used_off, defense_games = z$games_used_def,
      offense_games_available = z$games_available_off,
      defense_games_available = z$games_available_def, stringsAsFactors = FALSE)
  }
  out <- rbind(one_side(team_a, team_b), one_side(team_b, team_a))
  out <- out[order(match(out$team, c(team_a, team_b)), match(out$situation, order_names)), ]
  rownames(out) <- NULL
  out
}

load_matchup_data <- function(seasons = 2025:2026, cache_dir = NULL, refresh = FALSE) {
  if (!requireNamespace("cfbfastR", quietly = TRUE)) stop("Install cfbfastR first: install.packages('cfbfastR')")
  if (!length(seasons) || anyNA(seasons) || any(seasons < 2014 | seasons != floor(seasons)))
    stop("Choose seasons from 2014 onward.")
  seasons <- sort(unique(as.integer(seasons)))
  if (!is.null(cache_dir)) dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)
  result <- lapply(seasons, function(year) {
    path <- if (!is.null(cache_dir)) file.path(cache_dir, paste0("pbp_", year, ".rds")) else NULL
    from_cache <- !refresh && !is.null(path) && file.exists(path)
    if (from_cache) {
      p <- readRDS(path)
    } else {
      p <- as.data.frame(cfbfastR::load_cfb_pbp(seasons = year))
    }
    if (!is.data.frame(p) || !nrow(p)) stop("No data returned for ", year, ". Check the connection or choose a completed season.")
    if (!"season" %in% names(p) || !all(year %in% p$season)) stop("Loaded data does not contain requested season ", year)
    # Store only fields this model uses, so seasons with extra EPA columns combine safely.
    canonical <- function(options) {
      hit <- options[options %in% names(p)]
      if (!length(hit)) stop("Missing field: ", paste(options, collapse = " / "))
      p[[hit[1]]]
    }
    z <- data.frame(season = canonical("season"), game_id = canonical("game_id"),
      pos_team = canonical(c("pos_team", "offense")), def_pos_team = canonical(c("def_pos_team", "defense")),
      id_drive = canonical(c("id_drive", "drive_id", "drive_number", "drive_num")),
      down = canonical("down"), distance = canonical("distance"),
      yards_to_goal = canonical("yards_to_goal"), period = canonical("period"),
      play_type = canonical("play_type"),
      play_text = if ("play_text" %in% names(p)) p$play_text else "",
      stringsAsFactors = FALSE)
    if (!is.null(path) && !from_cache) saveRDS(z, path)
    z
  })
  do.call(rbind, result)
}
