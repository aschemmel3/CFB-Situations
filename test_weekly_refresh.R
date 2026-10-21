source('profile_cache.R')
eastern <- function(x) as.POSIXct(x, tz='America/New_York')
sunday <- eastern('2026-10-11 23:59:00')
monday <- eastern('2026-10-12 00:00:00')
saved <- list(refreshed_at=eastern('2026-10-05 09:00:00'))
stopifnot(!weekly_refresh_due(saved, sunday), weekly_refresh_due(saved, monday),
          weekly_refresh_due(NULL, monday), weekly_refresh_due(list(), monday),
          !weekly_refresh_due(list(refreshed_at=monday), monday),
          refresh_week(monday) == as.Date('2026-10-12'))
# A UTC timestamp still uses the Eastern week boundary (including DST).
stopifnot(refresh_week(as.POSIXct('2026-10-12 03:59:00', tz='UTC')) == as.Date('2026-10-05'),
          refresh_week(as.POSIXct('2026-11-02 04:59:00', tz='UTC')) == as.Date('2026-10-26'))
cat('Weekly refresh boundary tests passed.\n')
