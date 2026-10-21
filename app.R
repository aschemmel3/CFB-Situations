# In RStudio, open this file and click Run App.
# First-time setup: install.packages(c("cfbfastR", "shiny"))
library(shiny)
source("matchup_model.R", local = TRUE)
source("team_directory.R", local = TRUE)
source("profile_cache.R", local = TRUE)

ui <- fluidPage(
  tags$head(tags$link(rel = "stylesheet", href = "situations.css")),
  titlePanel("College football matchup situations"),
  p("Expected count = (team offense per game + opponent defense faced per game) / 2."),
  sidebarLayout(
    sidebarPanel(
      selectizeInput("seasons", "Historical seasons", choices = 2025:as.integer(format(Sys.Date(), "%Y")), selected = 2025:2026, multiple = TRUE),
      checkboxInput("overtime", "Include overtime", FALSE),
      checkboxInput("refresh", "Refresh newest selected season when preparing", FALSE),
      checkboxInput("weekly", "Automatically refresh each week", TRUE),
      actionButton("load", "Load saved estimates", class = "btn-primary"),
      actionButton("prepare", "Prepare / update data"),
      hr(),
      selectizeInput("a", "Team A", choices = NULL),
      selectizeInput("b", "Team B", choices = NULL),
      actionButton("retry_teams", "Reload bundled team list"),
      textOutput("team_status"),
      hr(),
      helpText("Each 2026 game has weight 3; each 2025 game has weight 1. Other selected seasons also have weight 1. Current-season data includes only available games."),
      helpText("Prepare once to save team averages. Normal loads and team changes use only those small saved averages. Preparing or updating can take several minutes."),
      helpText("Automatic refresh downloads the newest selected season once per week (Monday, Eastern time), while the app is running or when reopened. Downloads replace the season data; only games published by the source are available. Use Prepare / update data with refresh checked for an extra update.")
    ),
    mainPanel(
      textOutput("status"),
      fluidRow(
        column(6, uiOutput("card_a")),
        column(6, uiOutput("card_b"))
      ),
      hr(), h4("What is counted?"),
      tags$ul(
        tags$li("Backed up: own 1-20. Neutral field: between the 20s. Red zone: opponent 20 to goal line. Each 20 belongs to backed up or red zone. Drives can appear in multiple groups."),
        tags$li("Possessions: distinct offensive drives with at least one retained down play. Kneel-only drives count."),
        tags$li("Down situations: pre-play states, including punts and field-goal attempts on fourth down. First downs means first-down plays, not first downs gained."),
        tags$li("High red zone: 20-11 yard line; low red zone: 10-5; goal line: 4-1. Each counts plays starting in that band."),
        tags$li("Red-zone plays: plays starting inside or on the opponent's 20. Red-zone trips: distinct drives with at least one such play."),
        tags$li("Timeouts, kickoffs, tries, standalone penalties and explicitly labeled no-plays are excluded. Situations can overlap."),
        tags$li("Missing fields make that game unavailable for the affected metric. Zero-event games count as zero."),
        tags$li("These are expected counts, not probabilities or guaranteed totals. There is no adjustment for venue, injuries, opponent strength or recent roster changes.")
      )
    )
  )
)

server <- function(input, output, session) {
  data <- reactiveVal(NULL)
  load_error <- reactiveVal(NULL)
  observeEvent(input$load, {
    # Keep existing estimates if loading another setting fails.
    load_error(NULL)
    tryCatch({
      if (!length(input$seasons)) stop("Choose at least one season.")
      result <- read_prepared(as.integer(input$seasons), input$overtime)
      data(result)
    }, error = function(e) load_error(conditionMessage(e)))
  })
  observeEvent(input$prepare, {
    load_error(NULL)
    tryCatch({
      req(length(input$seasons))
      result <- withProgress(message="Preparing team averages (one-time work)", {
        prepare_profiles(as.integer(input$seasons), input$overtime, input$refresh)
      })
      data(result)
    }, error=function(e) load_error(conditionMessage(e)))
  })
  observeEvent(TRUE, {
    # Startup reads only a small profile file; it never downloads play-by-play.
    if (file.exists(profile_path(2025:2026,FALSE))) data(read_prepared())
  }, once=TRUE)
  last_auto_attempt <- NULL
  observe({
    invalidateLater(60 * 60 * 1000, session)
    req(isTRUE(input$weekly), length(input$seasons))
    seasons <- sort(unique(as.integer(input$seasons)))
    key <- profile_path(seasons, input$overtime)
    saved <- if (file.exists(key)) read_prepared(seasons, input$overtime) else NULL
    if (!weekly_refresh_due(saved)) {
      if (is.null(isolate(data())) ||
          !identical(isolate(data())$prepared_at, saved$prepared_at) ||
          !identical(isolate(data())$seasons, saved$seasons) ||
          !identical(isolate(data())$overtime, saved$overtime)) data(saved)
      return()
    }
    # Retry failures hourly, without repeated attempts from unrelated UI changes.
    now <- Sys.time()
    if (!is.null(last_auto_attempt) && identical(last_auto_attempt$key, key) &&
        as.numeric(difftime(now, last_auto_attempt$time, units='secs')) < 3600) return()
    last_auto_attempt <<- list(key=key, time=now)
    tryCatch({
      result <- withProgress(message="Weekly refresh: downloading latest season", {
        prepare_profiles(seasons, input$overtime, refresh=TRUE)
      })
      data(result)
      load_error(NULL)
    }, error=function(e) load_error(paste('Weekly refresh failed; keeping saved estimates. Will retry in an hour.', conditionMessage(e))))
  })
  output$status <- renderText({
    if (!is.null(load_error())) return(paste("Could not load data:", load_error()))
    z <- data()
    if (is.null(z)) return("No saved estimates loaded. Prepare data once, then load saved estimates.")
    paste0("Prepared ", z$prepared_at, ". Loaded: ", paste(z$seasons, collapse = ", "), ". ",
           if (!is.null(z$refreshed_at)) paste0("Last season download: ", format(z$refreshed_at, tz='America/New_York', usetz=TRUE), ". ") else "Season download time unknown. ",
           if (z$overtime) "Overtime included." else "Regulation only.",
           " Game weights: 2026 = 3; other seasons = 1. Short = 1-", z$short, " yards; medium = ", z$short + 1, "-7; long = 8+. Reload to apply setting changes.")
  })

  directory <- reactiveVal(NULL)
  directory_error <- reactiveVal(NULL)
  observeEvent(input$retry_teams, {
    tryCatch({
      teams <- load_fbs_directory()
      directory(teams)
      directory_error(attr(teams, "notice"))
      choices <- setNames(teams$team, teams$team)
      selected_a <- if (!is.null(input$a) && input$a %in% teams$team) input$a else "Georgia Tech"
      selected_b <- if (!is.null(input$b) && input$b %in% teams$team) input$b else default_tech_opponent(teams$team)
      updateSelectizeInput(session, "a", choices = choices, selected = selected_a, server = TRUE)
      updateSelectizeInput(session, "b", choices = choices, selected = selected_b, server = TRUE)
    }, error = function(e) directory_error(conditionMessage(e)))
  }, ignoreNULL = FALSE)
  output$team_status <- renderText({
    if (!is.null(directory_error())) return(directory_error())
    if (is.null(directory())) return("Loading FBS teams...")
    paste(nrow(directory()), "FBS teams available")
  })
  header <- function(team) {
    req(directory(), team)
    t <- directory()[directory()$team == team, , drop = FALSE]
    req(nrow(t) == 1)
    words <- strsplit(team, " ", fixed = TRUE)[[1]]
    initials <- if (length(words) == 1) toupper(substr(team, 1, 4)) else toupper(paste0(substr(words, 1, 1), collapse = ""))
    div(class = "team-header",
      if (nzchar(t$logo)) tags$img(src = t$logo, alt = paste(team, "logo"), class = "team-logo",
        onerror = "this.style.display='none';this.nextElementSibling.style.display='block';"),
      div(initials, title = paste(team, "team abbreviation"),
        style = paste0(if (nzchar(t$logo)) "display:none;" else "display:block;",
          "margin:auto;width:110px;height:85px;line-height:85px;border-radius:10px;font-size:26px;font-weight:bold;background:",
          t$primary, ";color:", t$secondary, ";")),
      h3(team), p("Expected situations per game"))
  }
  output$header_a <- renderUI(header(input$a))
  output$header_b <- renderUI(header(input$b))
  team_card <- function(team, side) {
    req(directory(), team)
    t <- directory()[directory()$team == team, , drop=FALSE]
    req(nrow(t) == 1)
    div(class="team-card", style=paste0('--team-primary:', t$primary, ';'),
      div(class="team-scroll-label", tags$span(class="team-color-dot"),
          tags$strong(team), tags$span(class="team-side", paste('Team', toupper(side)))),
      uiOutput(paste0('header_', side)), uiOutput(paste0('table_', side)))
  }
  output$card_a <- renderUI(team_card(input$a, 'a'))
  output$card_b <- renderUI(team_card(input$b, 'b'))
  matchup <- reactive({
    req(data(), input$a, input$b)
    validate(need(input$a != input$b, "Choose two different teams."))
    p <- data()$profiles
    available <- intersect(p$team[p$role == "offense"], p$team[p$role == "defense"])
    a <- resolve_pbp_team(input$a, available)
    b <- resolve_pbp_team(input$b, available)
    validate(need(!is.na(a), paste("No usable offense and defense data for", input$a, "in the selected seasons.")),
             need(!is.na(b), paste("No usable offense and defense data for", input$b, "in the selected seasons.")))
    estimate_profiles(data()$profiles, a, b)
  })
  display <- function(team) {
    validate(need(!is.null(data()), "Load saved estimates to see results."))
    z <- matchup()
    name <- resolve_pbp_team(team, unique(z$team))
    z <- z[z$team == name, ]
    table_for <- function(rows, labels) {
      tags$table(class = "table table-striped",
        tags$thead(tags$tr(tags$th("Situation"), tags$th("Expected count"), tags$th("Rounded"))),
        tags$tbody(lapply(seq_len(nrow(rows)), function(i) {
          value <- rows$expected_count[i]
          tags$tr(tags$td(labels[i]),
            tags$td(if (is.na(value)) "Unavailable" else sprintf("%.2f", value)),
            tags$td(if (is.na(value)) "Unavailable" else as.character(floor(value + 0.5))))
        })))
    }
    total <- z[match(c("Total possessions", "Down plays"), z$situation), , drop = FALSE]
    tagList(table_for(total, c("Total possessions (whole field)", "Total plays (whole field)")),
      lapply(names(field_groups()), function(group) {
        prefix <- paste0(group, " | ")
        rows <- z[startsWith(z$situation, prefix) &
          z$situation %in% names(situation_definitions()), , drop = FALSE]
        tagList(h4(group), table_for(rows, substring(rows$situation, nchar(prefix) + 1L)))
      }))
  }
  output$table_a <- renderUI(display(input$a))
  output$table_b <- renderUI(display(input$b))
}

shinyApp(ui, server)

