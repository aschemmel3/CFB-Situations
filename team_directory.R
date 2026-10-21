# NCAA names normalized to CFBD names; explicit aliases avoid fuzzy matches.
default_tech_opponent <- function(available, now=Sys.time()) {
  # Official 2026 schedule snapshot: https://ramblinwreck.com/sports/m-footbl/schedule/season/2026-27
  schedule <- read.csv(file.path('data', 'georgia_tech_schedule.csv'), stringsAsFactors=FALSE)
  schedule$date <- as.Date(schedule$date)
  day <- as.Date(now, tz='America/New_York')
  monday <- day - (as.integer(format(day, '%u')) - 1L)
  schedule <- schedule[order(schedule$date), ]
  upcoming <- schedule[schedule$date >= monday & schedule$opponent %in% available, ]
  if (nrow(upcoming)) return(upcoming$opponent[1])
  # After the season, retain the last scheduled matchup until the schedule is updated.
  covered <- schedule[schedule$opponent %in% available, ]
  if (nrow(covered)) return(tail(covered$opponent, 1))
  setdiff(available, 'Georgia Tech')[1]
}

canonical_team <- function(x) {
  x <- trimws(as.character(x))
  x <- sub(" St\\.$", " State", x)
  aliases <- c("Army West Point"="Army", "App State"="Appalachian State",
    "UConn"="Connecticut", "UMass"="Massachusetts", "Hawai'i"="Hawaii",
    "San José State"="San Jose State", "Miami (FL)"="Miami",
    "Miami (Ohio)"="Miami (OH)", "Sam Houston State"="Sam Houston",
    "Louisiana-Lafayette"="Louisiana", "Louisiana-Monroe"="Louisiana Monroe",
    "UL Monroe"="Louisiana Monroe", "La.-Monroe"="Louisiana Monroe",
    "Southern Miss."="Southern Miss", "Middle Tenn."="Middle Tennessee",
    "Western Ky."="Western Kentucky", "Northern Ill."="Northern Illinois",
    "Eastern Mich."="Eastern Michigan", "Western Mich."="Western Michigan",
    "Central Mich."="Central Michigan", "Fla. Atlantic"="Florida Atlantic",
    "FIU"="Florida International", "Ga. Southern"="Georgia Southern",
    "Georgia St."="Georgia State", "Kennesaw St."="Kennesaw State",
    "N.C. State"="NC State", "Ole Miss"="Ole Miss", "Southern California"="USC")
  matched <- match(x, names(aliases))
  x[!is.na(matched)] <- unname(aliases[matched[!is.na(matched)]])
  x
}

normalize_ncaa_directory <- function(raw, season) {
  required <- c("team_name", "division", "season")
  if (!is.data.frame(raw) || !all(required %in% names(raw)))
    stop("NCAA team data is empty or missing team_name, division or season.")
  raw <- raw[!is.na(raw$division) & !is.na(raw$season) & raw$division == 11 & raw$season == season, , drop=FALSE]
  if (!nrow(raw)) stop("No FBS teams published for NCAA season ", season, ".")
  teams <- data.frame(team=canonical_team(raw$team_name), display_name=as.character(raw$team_name), logo="", stringsAsFactors=FALSE)
  if (anyNA(teams$team) || any(!nzchar(teams$team))) stop("NCAA data contains unnamed teams.")
  teams <- teams[!duplicated(teams$team), , drop=FALSE]
  teams[order(teams$team), , drop=FALSE]
}

# Read the exact bundled files and team keys used by cfb4thDownVIP.
# Parse JSON only; never execute JavaScript.
read_bundled_team_data <- function(path, variable) {
  lines <- readLines(path, warn=FALSE)
  text <- paste(lines[!grepl("^\\s*//", lines)], collapse="\n")
  marker <- paste0("window.", variable, " = ")
  at <- regexpr(marker, text, fixed=TRUE)[1]
  if (at < 0) stop("Missing ", variable, " in ", path)
  body <- substring(text, at + nchar(marker))
  jsonlite::fromJSON(sub(";\\s*$", "", body), simplifyVector=FALSE)
}

load_fbs_directory <- function() {
  profiles <- read_bundled_team_data(file.path("data", "team_profiles.js"), "CFB_TEAMS")
  colors <- read_bundled_team_data(file.path("data", "team_colors.js"), "CFB_TEAM_COLORS")
  names <- sort(names(profiles))
  if (!length(names)) stop("Bundled team profiles contain no teams.")
  teams <- data.frame(team=names, display_name=names, logo="",
    primary="#174b69", secondary="#ffffff", stringsAsFactors=FALSE)
  for (i in seq_len(nrow(teams))) {
    color <- colors[[teams$team[i]]]
    if (!is.null(color)) {
      teams$primary[i] <- color$primary
      teams$secondary[i] <- color$secondary
    }
  }
  # Optional saved logos never determine membership or require a request.
  root <- tools::R_user_dir("cfbMatchup", "cache")
  for (file in list.files(root, pattern="^(ncaa_)?fbs_directory.*\\.rds$", full.names=TRUE)) {
    tryCatch({
      old <- readRDS(file)
      if (all(c("team", "logo") %in% names(old))) {
        idx <- match(canonical_team(teams$team), canonical_team(old$team))
        good <- !is.na(idx) & !is.na(old$logo[idx]) & nzchar(old$logo[idx])
        teams$logo[good] <- old$logo[idx[good]]
      }
    }, error=function(e) NULL)
  }
  # Bundled logo assets take precedence and need no network connection.
  logo_file <- file.path("data", "team_logos.csv")
  if (file.exists(logo_file)) {
    logos <- read.csv(logo_file, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
    idx <- match(teams$team, logos$team)
    if ("local_logo" %in% names(logos)) {
      good <- !is.na(idx) & file.exists(file.path("www", logos$local_logo[idx]))
      teams$logo[good] <- logos$local_logo[idx[good]]
    }
  }
  teams
}

resolve_pbp_team <- function(team, available) {
  i <- which(canonical_team(available) == canonical_team(team))
  if (length(i) == 1) available[i] else NA_character_
}

