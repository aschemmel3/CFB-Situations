# Run with Rscript --vanilla test_model.R from this folder.
source("matchup_model.R")

# Exact requested arithmetic, including the reverse matchup.
historical <- data.frame(
  season = 2025, game_id = c("1", "2", "3", "4"),
  team = c("Texas", "Texas", "Other", "Oklahoma"),
  opponent = c("Other", "Other", "Oklahoma", "Other"),
  situation = "Total possessions", count = c(10, 14, 13, 11)
)
result <- estimate_matchup(historical, "Texas", "Oklahoma")
stopifnot(result$expected_count[result$team == "Texas"] == 12.5)
stopifnot(result$offense_per_game[result$team == "Texas"] == 12)
stopifnot(result$opponent_defense_per_game[result$team == "Texas"] == 13)

# One game reaches the red zone twice on one drive; the next has zero trips.
pbp <- data.frame(
  season = 2025, game_id = c(1, 1, 1, 1, 2, 2, 2, 2),
  pos_team = "Texas", def_pos_team = "Oklahoma",
  id_drive = c(1, 1, 2, 2, 1, 1, 1, 2),
  down = c(3, 4, 4, 4, 1, 3, 4, 3),
  distance = c(3, 2, 10, 10, 10, 3, 3, 1),
  yards_to_goal = c(20, 18, 70, 70, 80, 70, 70, 5),
  period = c(1, 1, 2, 2, 1, 1, 1, 5),
  play_type = c("Rush", "Field Goal Good", "Punt", "Timeout", "Rush", "Penalty", "Rush", "Rush"),
  play_text = c("", "", "", "", "", "", "No play", "")
)
games <- build_team_games(pbp)
value <- function(game, situation, z = games) z$count[z$game_id == game & z$situation == situation]
stopifnot(value(1, "Total possessions") == 2, value(2, "Total possessions") == 1)
stopifnot(value(1, "4th downs") == 2, value(2, "4th downs") == 0)
stopifnot(value(1, "3rd and short") == 1, value(2, "3rd and short") == 0)
stopifnot(value(1, "Red-zone plays") == 2, value(1, "Red-zone trips") == 1)
stopifnot(value(2, "Red-zone trips") == 0)
profiles <- team_profiles(games)
stopifnot(profiles$average[profiles$team == "Texas" & profiles$role == "offense" & profiles$situation == "Red-zone trips"] == 0.5)
stopifnot(profiles$average[profiles$team == "Oklahoma" & profiles$role == "defense" & profiles$situation == "Red-zone trips"] == 0.5)
with_ot <- build_team_games(pbp, include_overtime = TRUE)
stopifnot(value(2, "Red-zone trips", with_ot) == 1)
pbp$yards_to_goal[1] <- NA
missing <- build_team_games(pbp)
stopifnot(is.na(value(1, "Red-zone plays", missing)), value(1, "4th downs", missing) == 2)
stopifnot(inherits(try(estimate_matchup(games, "Texas", "Texas"), silent = TRUE), "try-error"))
# Exercise every inclusive boundary and the gaps between field-position bands.
boundary <- pbp[rep(1, 14), ]
boundary$game_id <- 3
boundary$id_drive <- 1:14
boundary$down <- c(1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 4, 4)
boundary$distance <- c(10, 9, 1, 5, 6, 10, 1, 3, 4, 7, 8, 20, 1, 10)
boundary$yards_to_goal <- c(21, 20, 11, 10, 5, 4, 1, 30, 30, 30, 30, 30, 30, 30)
boundary$play_type <- "Rush"
boundary$play_text <- ""
b <- build_team_games(boundary)
expected <- c("Total possessions" = 14, "1st and 10" = 1,
  "2nd and 5 or less" = 2, "2nd and 6 or more" = 2,
  "3rd and short" = 2, "3rd and medium" = 2, "3rd and long" = 2,
  "High red zone (20-11)" = 2, "Low red zone (10-5)" = 2, "Goal line (4-1)" = 2)
stopifnot(all(names(expected) %in% b$situation))
stopifnot(all(b$count[match(names(expected), b$situation)] == expected))
stopifnot(sum(expected[8:10]) == value(3, "Red-zone plays", b))
# Each new situation participates in offense AND defense matchup averages.
both_sides <- rbind(games, b)
reverse <- both_sides
reverse$team <- "Oklahoma"
reverse$opponent <- "Texas"
prediction <- estimate_matchup(rbind(both_sides, reverse), "Texas", "Oklahoma")
texas <- prediction[prediction$team == "Texas", ]
stopifnot(all(texas$expected_count == texas$offense_per_game))
# Unequal season sample sizes distinguish per-game weighting from averaging
# season means. Zero counts retain their weight; missing counts do not.
weighted_history <- data.frame(
  season = rep(c(2025, 2025, 2026, 2026, 2026), 2),
  game_id = as.character(1:10),
  team = rep(c("Texas", "Other"), each = 5),
  opponent = rep(c("Oklahoma", "Texas"), each = 5),
  situation = "Total possessions",
  count = c(12, 20, 30, 0, NA, 4, 8, 12, 0, NA)
)
wp <- team_profiles(weighted_history)
stopifnot(wp$average[wp$team == "Texas" & wp$role == "offense"] == 122 / 8)
stopifnot(wp$average[wp$team == "Texas" & wp$role == "defense"] == 48 / 8)
stopifnot(all(wp$games_used == 4), all(wp$games_available == 5))
ok_off <- weighted_history[1:5, ]
ok_off$team <- "Oklahoma"
ok_off$opponent <- "Other"
ok_off$count <- c(2, 4, 6, 0, NA)
weighted_prediction <- estimate_matchup(rbind(weighted_history, ok_off), "Texas", "Oklahoma")
stopifnot(weighted_prediction$expected_count[weighted_prediction$team == "Texas"] == 15.25)
stopifnot(weighted_prediction$expected_count[weighted_prediction$team == "Oklahoma"] == 4.5)
cat("All tests passed, including 2026 triple weighting for offense and defense.\n")

# Missing play labels do not invalidate usable down/distance states.
untyped <- boundary
untyped$play_type <- NA_character_
stopifnot(identical(build_team_games(untyped), build_team_games(boundary)))
marker <- untyped[1, ]
marker$down <- NA
marker$distance <- NA
marker$play_text <- NA_character_
stopifnot(identical(build_team_games(rbind(untyped,marker)), build_team_games(untyped)))
cat('Missing play-type regression tests passed.\n')

# Regional counts partition down plays at both 20s and preserve drive identity.
stopifnot(all(lengths(strsplit(names(situation_definitions()), " | ", fixed = TRUE)) <= 2L))
regional <- boundary[rep(1, 7), ]
regional$yards_to_goal <- c(99, 80, 79, 50, 21, 20, 1)
regional$id_drive <- c(1, 1, 1, 2, 2, 2, 2)
regional$down <- 1
regional$distance <- 10
rg <- build_team_games(regional)
groups <- names(field_groups())
stopifnot(identical(vapply(groups, function(g) value(3, paste(g, "Down plays", sep = " | "), rg), numeric(1)),
                    setNames(c(2, 3, 2), groups)))
stopifnot(value(3, paste(groups[1], "Total possessions", sep = " | "), rg) == 1,
          value(3, paste(groups[2], "Total possessions", sep = " | "), rg) == 2)
regional$yards_to_goal[1] <- NA
rg_missing <- build_team_games(regional)
stopifnot(all(is.na(rg_missing$count[grepl(" | ", rg_missing$situation, fixed = TRUE)])))
cat('Field group boundary and missing-position tests passed.\n')
