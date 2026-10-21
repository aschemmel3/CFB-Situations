source("app.R")
shiny::testServer(server, {
  session$setInputs(a = "Texas", b = "Oklahoma")
  session$flushReact()
  for (rendered in list(output$table_a, output$table_b)) {
    stopifnot(all(vapply(names(field_groups()), function(group) {
      grepl(group, rendered$html, fixed = TRUE)
    }, logical(1))))
    stopifnot(grepl("Total possessions (whole field)", rendered$html, fixed = TRUE))
    stopifnot(!grepl("Unavailable", rendered$html, fixed = TRUE))
  }
  teams <- load_fbs_directory()
  stopifnot(grepl(paste0('--team-primary:', teams$primary[teams$team == 'Texas']),
                  output$card_a$html, fixed=TRUE))
  session$setInputs(a = 'Oregon')
  session$flushReact()
  stopifnot(grepl(paste0('--team-primary:', teams$primary[teams$team == 'Oregon']),
                  output$card_a$html, fixed=TRUE),
            grepl('Oregon', output$card_a$html, fixed=TRUE))
})
cat("Both teams' grouped tables rendered successfully.\n")
