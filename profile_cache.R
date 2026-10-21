# Increment this when situation definitions or weighting change.
profile_cache_version <- 'v4'
# Recount games for the updated low-red-zone and goal-line boundaries.
game_cache_version <- 'v3'
profile_path <- function(seasons, overtime=FALSE) {
  file.path('data', 'prepared', paste0(profile_cache_version, '_', paste(sort(unique(seasons)),collapse='-'), '_ot', as.integer(overtime), '.rds'))
}
read_prepared <- function(seasons=2025:2026, overtime=FALSE) {
  path <- profile_path(seasons,overtime)
  if (!file.exists(path)) stop('No prepared data for these settings. Run Rscript prepare_data.R once, or click Prepare / update data.')
  readRDS(path)
}
refresh_week <- function(now=Sys.time()) {
  day <- as.Date(now, tz='America/New_York')
  day - (as.integer(format(day, '%u')) - 1L)
}
weekly_refresh_due <- function(result, now=Sys.time()) {
  is.null(result) || is.null(result$refreshed_at) ||
    refresh_week(result$refreshed_at) < refresh_week(now)
}
prepare_profiles <- function(seasons=2025:2026, overtime=FALSE, refresh=FALSE) {
  dir.create(file.path('data','prepared'),recursive=TRUE,showWarnings=FALSE)
  raw_cache <- file.path(tools::R_user_dir('cfbMatchup','cache'),'pbp')
  pieces <- lapply(sort(unique(seasons)), function(year) {
    path <- file.path('data','prepared',paste0(game_cache_version,'_games_',year,'_ot',as.integer(overtime),'.rds'))
    # Historical seasons are reused. Refresh only the latest selected season.
    rebuild <- refresh && year == max(seasons)
    if (file.exists(path) && !rebuild) return(readRDS(path))
    message('Preparing ',year,'...')
    pbp <- load_matchup_data(year,cache_dir=raw_cache,refresh=rebuild)
    games <- build_team_games(pbp,include_overtime=overtime)
    saveRDS(games,path)
    games
  })
  result <- list(profiles=team_profiles(do.call(rbind,pieces)),seasons=sort(unique(seasons)),
                 overtime=overtime,short=3L,prepared_at=format(Sys.time(),'%Y-%m-%d %H:%M:%S %Z'))
  # Recalculating cached games must not mark them as newly downloaded.
  previous <- if (file.exists(profile_path(seasons,overtime))) read_prepared(seasons,overtime) else NULL
  result$refreshed_at <- if (refresh) Sys.time() else previous$refreshed_at
  # Finish successfully before replacing the usable profile cache.
  path <- profile_path(seasons,overtime)
  temp <- tempfile(tmpdir=dirname(path))
  saveRDS(result,temp)
  if (!file.copy(temp,path,overwrite=TRUE)) stop('Could not save prepared profiles.')
  unlink(temp)
  message('Saved prepared profiles: ',path)
  result
}
