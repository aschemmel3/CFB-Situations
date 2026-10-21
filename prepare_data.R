# Run once from Situations; rerun with --refresh to update the newest season.
source('matchup_model.R')
source('profile_cache.R')
args <- commandArgs(trailingOnly=TRUE)
seasons <- suppressWarnings(as.integer(args[args != '--refresh']))
if (!length(seasons)) seasons <- 2025:2026
if (anyNA(seasons)) stop('Usage: Rscript prepare_data.R [2025 2026] [--refresh]')
invisible(prepare_profiles(seasons, refresh='--refresh' %in% args))
