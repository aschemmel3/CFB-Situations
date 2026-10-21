# College football situation estimator

Choose two teams to estimate situation counts separately for each offense:

    (team's offensive count per game + opponent's defensive count faced per game) / 2

For example, Texas averaging 12 possessions and Oklahoma's opponents averaging 13 yields **12.5 possessions for Texas**. Oklahoma gets its own calculation from its offense and Texas's defense. The app applies the same formula to every situation.

## START HERE: run the app

In VS Code, choose **Terminal > New Terminal**. Make sure the terminal is **PowerShell** (use the dropdown next to the **+** button to select it).

**Copy and paste this entire two-line block into the terminal, then press Enter:**

```powershell
Set-Location 'C:\Users\asche\OneDrive\Desktop\VIPFall2026\Situations'
& 'C:\Program Files\R\R-4.6.1\bin\Rscript.exe' --vanilla -e "shiny::runApp('.', launch.browser=TRUE)"
```

**Your browser will open the app. Leave the terminal open while using it.** To stop the app, click in the terminal and press **Ctrl+C**. To start it again, paste the same two-line block above.

These commands use the folder and R installation on this computer. Paste only the code inside the block, not the backticks, into the PowerShell terminal.

### First-time setup only: install missing packages

If the launch command reports that there is no package called `shiny` or `cfbfastR`, paste this command into the same terminal and wait for installation to finish:

```powershell
& 'C:\Program Files\R\R-4.6.1\bin\Rscript.exe' --vanilla -e "install.packages(c('cfbfastR', 'shiny'), repos='https://cloud.r-project.org')"
```

Then paste the **two-line launch block above** again. Install packages only once. If R requests a personal library, accept it. Installation and the initial season download require an internet connection. No API key is needed for `load_cfb_pbp()`.

### Once the app opens

The opening matchup is Georgia Tech against its opponent for the current Monday-based week in Eastern time. During a bye week it selects the next scheduled opponent. This uses a bundled [official 2026 schedule](https://ramblinwreck.com/sports/m-footbl/schedule/season/2026-27) in `data/georgia_tech_schedule.csv`; schedule changes and future seasons require updating that file. After the final listed game, the last matchup remains the default. You can still choose any two teams.

The default saved estimates load automatically if they have already been prepared. If no saved estimates are available, click **Prepare / update data** and wait for preparation to finish; this can take several minutes. Then choose **Team A** and **Team B**.

Change team selectors freely. After changing seasons or the overtime setting, click **Load saved estimates**; if those settings have not been prepared yet, click **Prepare / update data**. Defaults are the 2025 and 2026 seasons, regulation only and short = 1–3 yards. Results appear in two side-by-side team columns, with the selected team logo above each column. There is no CSV download.

Alternatively, open `app.R` in RStudio and click **Run App** after installing the packages.

## Included situations

Each team's results are divided into **Backed up (-1 to -20)**, **Neutral field (-20 to +20)** and **Red zone (+20 to goal line)**. Backed up includes the own 1 through own 20; neutral field is strictly between the two 20s; red zone includes the opponent's 20 through the 1. Each boundary 20 belongs to the adjacent end group, so plays appear in exactly one field group. Each group shows its own down/distance counts and possessions (drives with at least one play starting in that group). A drive can visit multiple groups, so grouped possessions should not be added. Whole-field total possessions remain above the groups. Red-zone-specific breakdowns appear in the Red zone group. Missing field positions make that game's grouped counts unavailable.

The grouped calculations use prepared cache version v4 and game-count cache version v3 for the updated red-zone boundaries. Older saved estimates are not reused; prepare data again after updating.

- Total possessions: unique drives with at least one retained down play, including kneel-only drives.
- First-and-10; second-and-5-or-less; second-and-6-or-more.
- High red zone (20–11 yard line), low red zone (10–5), and goal line (4–1): plays starting in each band.
- Down plays and plays on each of first, second, third and fourth down.
- Third-and-short (1–3), medium (4–7), long (8+), and fourth-and-short (1–3). These yardage bands are fixed.
- Red-zone plays: pre-play field position is 1–20 yards from the opponent's goal line.
- Red-zone trips: unique drives with at least one such play, counted once even if a drive exits and re-enters the red zone.
- Inside-10 plays: pre-play field position is 1–10 yards from the goal line.

Fourth downs include punts and field-goal attempts; they do not mean only attempts to convert. First-down counts mean plays on first down, not first downs gained. Situations overlap and should not be added together. A long touchdown with no play starting inside the 20 is not a red-zone trip under this definition.

Timeouts/end markers, kickoffs, tries, standalone penalty rows and explicitly labeled no-plays are excluded. Live plays with penalties remain unless labeled no-play. This counts retained play opportunities, not every transient dead-ball situation a team might face. Possessions with no retained down play are not counted.

## Method and coverage

Each team-game gets a count for every situation, including zero. Offense averages are calculated from that team's counts. Defense averages are calculated from its opponents' counts in games against it. Each 2026 game has weight 3; each 2025 game has weight 1. Any other selected season also has weight 1. Both offense and defense use sum(game count * game weight) / sum(game weight), excluding missing counts and their weights. Thus the default average is (2025 total + 3 * 2026 total) / (2025 games + 3 * 2026 games). This weights individual games, not season averages; the displayed game counts remain actual, unweighted counts. The final estimate gives equal weight to the offensive and defensive averages regardless of their sample sizes.

Missing required situation data makes a game unavailable for that metric instead of treating it as zero. The app shows used / available games for both inputs. It cannot detect an entirely absent game or missing play; coverage and completeness depend on the loaded play-by-play repository. The app uses all games present in the selected seasons, including postseason and any covered FCS opponents. Use completed seasons for a full historical baseline. Refresh the cache when using a season in progress.

This is a descriptive matchup baseline, not a fitted probability model. It does not adjust for schedule strength, venue, roster changes, pace changes or recency within a season. Fractional estimates are intentional. Defensive fourth-down counts mean situations faced, not necessarily undesirable situations 'allowed.' Independently blended possession estimates need not satisfy the constraints of a simulated game.

Add a metric by adding a named function to `situation_definitions()` in `matchup_model.R`. It will automatically appear for both teams using the same averaging formula.

## Use without Shiny

Run in an R console with this folder as the working directory:

```r
source('matchup_model.R')
pbp <- load_matchup_data(2025:2026)
games <- build_team_games(pbp, include_overtime = FALSE, short_yards = 3)
prediction <- estimate_matchup(games, 'Texas', 'Oklahoma')
print(prediction)
```

## Validation

`test_model.R` tests the 12.5 example, zero-event games, the defense perspective, drive deduplication, fourth-down kicks, overtime exclusion, administrative/penalty/no-play exclusions and missing field handling. It uses controlled synthetic data, not real historical results.

```powershell
& 'C:\Program Files\R\R-4.6.1\bin\Rscript.exe' --vanilla test_model.R
```

During creation, HTTPS/SSL errors prevented installing Shiny and downloading a real season in this environment. The live app and real-data integration therefore still need a successful run with internet access.

Sources: [cfbfastR loader](https://github.com/sportsdataverse/cfbfastR/blob/main/R/load_cfb_pbp.R), [play-by-play field documentation](https://github.com/sportsdataverse/cfbfastR/blob/main/R/cfbd_pbp_data.R).



## Team selectors and logos

The dropdowns use the exact 136 team keys from a local copy of cfb4thDownVIP/data/team_profiles.js, just as the working fourth-down app does. data/team_colors.js is also copied locally. No ESPN or NCAA request is made to build the list, and no 2026 directory release is required. The list is a bundled snapshot, not a live membership feed.

The original cfb4thDownVIP files are unchanged. Situations is self-contained and does not need an R subfolder. Only team names and colors are reused; the fourth-down probabilities are not used in the situation estimates. The 2025/2026 weighted situation calculations remain in matchup_model.R.

The working fourth-down app uses colored team abbreviations rather than logos. Situations uses those as its offline fallback, while displaying previously cached logos where available. Season play-by-play downloads still require internet access on first load; this directory fix does not supply missing 2026 game data.

## Fast prepared estimates

**Automatically refresh each week** is enabled by default. The app downloads the newest selected season once each Monday-based week in Eastern time, on startup or during its hourly check while running. With the default settings, this reruns `cfbfastR::load_cfb_pbp(seasons = 2026)` and replaces the saved 2026 plays and counts before rebuilding estimates; it never appends a second copy of the season. The 2025 counts are reused. New games must first be published in the source dataset.

If the app is closed, the update happens when you next open it. This is an app refresh, not a Windows background scheduled task. The first launch after this change refreshes once because older saved estimates have no download timestamp. Failed updates keep the loaded estimates and retry hourly. Uncheck the automatic refresh option to use saved estimates only. For an extra update after games are published, check **Refresh newest selected season when preparing**, then click **Prepare / update data**. The app displays the last successful refresh time separately from the preparation time. Recalculating cached data does not mark it as newly downloaded.

The app starts from a small file of precomputed offense/defense averages, then refreshes if the weekly update is due. Team changes only select rows and average the two inputs. Saved files in data/prepared are keyed by seasons, overtime setting and model cache version.

Run `Rscript prepare_data.R` once from this folder to prepare 2025–2026, or click **Prepare / update data** in the app. Existing raw downloads and per-season game counts are reused. To fetch new games, run `Rscript prepare_data.R --refresh` or check **Refresh newest selected season when preparing** and click **Prepare / update data**. This refreshes only the latest selected season. Normal **Load saved estimates** does no downloading or counting. The default prepared file loads automatically at startup.

Preparation must succeed for all selected seasons before the combined file is replaced. If new settings or an update fail, the previously loaded estimates remain visible with their original settings and timestamp. Historical per-season counts are stored so a current-season update does not recount 2025. The fourth-down project remains untouched.

Team logos are now bundled in www/logos for all 136 dropdown teams and load without internet access. data/team_logos.csv maps teams to local assets and records their ESPN source URLs. Each result table includes the decimal estimate and a Rounded column (nearest whole number, with .5 rounding up, computed from the unrounded estimate).
