source('team_directory.R')
teams <- load_fbs_directory()$team
opponent <- function(day) default_tech_opponent(teams, as.POSIXct(day, tz='America/New_York'))
stopifnot(opponent('2026-10-07') == 'Duke',
          opponent('2026-10-11') == 'Duke',
          opponent('2026-10-12') == 'Virginia Tech',
          opponent('2026-10-02') == 'Duke',
          opponent('2026-10-26') == 'Pittsburgh',
          opponent('2026-12-07') == 'Georgia')
cat('Weekly opening matchup tests passed.\n')
