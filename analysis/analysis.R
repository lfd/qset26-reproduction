#!/usr/bin/env Rscript

library(dplyr)
library(here)
library(readr)
library(ggplot2)
library(lubridate)
library(ggridges)
library(grDevices)
library(ggnewscale)
library(tikzDevice)
library(yaml)
# library(httpgd)

source(here("analysis/network.R"))

# These dimensions were measured by LaTeX before.
PAPER_TEXTWIDTH <- 7.1413
PAPER_TEXTHEIGHT <- 9.3003
PAPER_LINEWIDTH <- 3.48761
violin_height <- 4 #3.5

COLORS <- c(
  "#1f78b4",  # LfD blue
  "#E69F00",  # LfD amber
  "#009371",  # LfD teal-green
  "#ed665a",  # LfD coral red
  "#beaed4",  # LfD lavender
  "#3089c5",  # LfD mid blue
  "#555555",  # LfD dark grey
  "#000000",  # LfD black
  "#999999",  # LfD medium grey
  "#E294B5"  # sneaked in pink
)

# The first commandline argument can be d_out and the second argument can be d_analysed, but the defaults are set to these values for convenience.
arguments <- commandArgs(trailingOnly = TRUE)
if (length(arguments) >= 2) {
  d_out <- arguments[1]
  d_analysed <- arguments[2]
} else {
  d_out <- here("build/tex")
  d_analysed <- here("build/analysis/analysed")
}

save_plot <- function(plot, filename, width = 10, height = 12) {
  if (Sys.getenv("RSTUDIO") == "1") {
    print(plot)
    return()
  }

  if (!dir.exists(d_out)) {
    dir.create(d_out, recursive = TRUE)
  }
  filename <- file.path(d_out, filename)

  # pdf output
  pdf(paste0(filename, ".pdf"), width = width, height = height)
  print(plot)
  dev.off()

  # tikz output
  tikz(paste0(filename, ".tex"), width = width, height = height, sanitize = FALSE)
  print(plot)
  dev.off()
}

generate_dev_aesthetics <- function(n) {
  shapes <- c(16, 4, 17, 15, 25)
  idx <- seq_len(n) - 1
  color_idx <- (idx %% length(COLORS)) + 1
  shape_idx <- (idx %/% length(COLORS)) + 1   # advance shape each color cycle
  data.frame(
    color = COLORS[color_idx],
    shape = shapes[shape_idx],
    stringsAsFactors = FALSE
  )
}

prepare_plot_data <- function(df, df_dev, p_dates, n_projects=2, top=0.2) {
  p_dates$date <- as.Date(p_dates$date)
  p_dates$project <- factor(p_dates$project, levels = levels(df$project))
  p_dates$type <- factor(p_dates$type)

  # Highlight developers who contributed to three or more projects.
  highlight <- df_dev %>%
    filter(num_projects >= n_projects) %>%
    pull(identity) %>%
    unique()

  # Among the cross-project developers, keep the top fraction by total commits.
  account_totals <- df %>%
    filter(account %in% highlight) %>%
    group_by(account) %>%
    summarise(total_commits = sum(count), .groups = "drop") %>%
    arrange(desc(total_commits))
  print(paste0("In total, there are ",nrow(account_totals)," cross-project developers."))

  n_keep <- ceiling(nrow(account_totals) * top)
  highlight <- account_totals$account[seq_len(n_keep)]
  print(paste0("... with ",n_keep," top-committers."))

  # Build color palette.
  unique_accounts <- sort(highlight)
  #account_palette <- setNames(generate_colors(length(unique_accounts)), unique_accounts)
  aes_tbl <- generate_dev_aesthetics(length(unique_accounts))
  account_palette <- setNames(aes_tbl$color, unique_accounts)
  account_shapes <- setNames(aes_tbl$shape, unique_accounts)

  # Add account color column.
  account_colors <- df %>%
    mutate(account_color = coalesce(account_palette[account], "")) %>%
    select(account, account_color) %>%
    distinct()

  # Add account shape column.
  account_shape_df <- df %>%
    mutate(account_shape = coalesce(account_shapes[account], NA_real_)) %>%
    select(account, account_shape) %>%
    distinct()

  df$date <- as.Date(df$date)
  # levels determines the order
  df$project <- factor(df$project, levels = rev(c(
    "xacc",
	  "qcor",
	  "cuda-quantum",
	  "mqt-core",
	  "catalyst",
	  "pennylane",
	  "qiro",
	  "qat",
    "QDMI",
	  "qdk",
	  "qiskit",
	  "qiskit-qir",
	  "pyqir",
	  "qe-compiler",
	  "tket2",
	  "hugr",
	  # pretty much unsorted
	  "jeffmlir",
	  "qbraid-qir",
	  "qe-qasm",
	  "qssa",
 	  "hugr-mlir",
	  "mqss-passes-suite",
	  "openql",
	  "qBraid",
	  "qiree",
	  "qllvm",
	  "qwerty",
	  "tud_hybrid_quantum"
  )))

  monthly <- df %>%
    mutate(month = floor_date(date, "month")) %>%
    group_by(project, account, month) %>%
    summarise(commits = sum(count), .groups = "drop") %>%
    left_join(account_colors, by = "account") %>%
    left_join(account_shape_df, by = "account") %>%
    mutate(account_label = trimws(sub("<.*", "", account)))
  return(monthly)
}

filter_prj <- function(data, prj) {
  filtered <- data %>%
  filter(project %in% prj) %>%
  mutate(
    project = factor(
      project,
      levels = levels(droplevels(prj))
    )
  )
  return(filtered)
}

violin <- function(data, filename) {
  pdates <- filter_prj(paper_dates, data$project)
  plot <- ggplot(data, aes(x = month, y = project, weight = commits, fill = project)) +
    geom_violin(scale = "width", trim = TRUE, show.legend = FALSE) +
    geom_linerange(data = pdates, aes(x = date,
      ymin = as.numeric(project) - 0.5, ymax = as.numeric(project) + 0.5,
      color = type),
      linetype = "dashed", linewidth = 0.8, inherit.aes = FALSE) +
    labs(x = NULL, y = NULL, color="Publication") +
    scale_x_date(
      date_breaks = "1 year",
      date_labels = "%Y"
    ) +
    scale_y_discrete(labels = \(x) paste0("\\enspace", gsub("_", "-", x))) +
    theme_bw() +
    theme(legend.position="bottom", legend.box="horizontal") +
    guides(color = guide_legend(nrow = 1, byrow = TRUE))
  save_plot(plot, filename, width = PAPER_TEXTWIDTH, height = violin_height)
}

violin_highlighted <- function(data, filename) {
  pdates <- filter_prj(paper_dates, data$project)
  highlighted <- subset(data, account_color != "")
  highlighted <- filter_prj(highlighted, data$project)
  plot <- ggplot(data, aes(x = month, y = project, weight = commits)) +
    geom_violin(scale = "width",
                trim = TRUE,
                fill = "grey97",
                color = "grey40",
                linewidth = 0.5) +
    geom_point(data = highlighted,
               aes(x = month, y = as.numeric(project), color = account_color, shape = account_shape),
               position = position_jitter(height = 0.3, width = 8, seed=123),
               size = 0.65, #0.35,
               alpha=0.75,
               inherit.aes = FALSE,
               show.legend = FALSE
    ) +
    scale_shape_identity() +
    scale_color_identity(
      name   = "contributor",
      guide  = "none",
      labels = setNames(highlighted$account_label, highlighted$account_color)
    ) +
    new_scale_color() +
    geom_linerange(data = pdates, aes(x = date,
                                         ymin = as.numeric(project) - 0.47,
                                         ymax = as.numeric(project) + 0.47,
                                         color = type,
                                         linetype = type),
                 linewidth = 1.5,
                 inherit.aes = FALSE, show.legend=TRUE,
                 key_glyph = "vpath") + # vertical legend symbol
    scale_color_manual(name = "Publication",
                       values = c(preprint = "#555555", published = "#555555")) +
    scale_linetype_manual(name = "Publication",
                          values = c(preprint = "22", published = "solid")) +
    labs(x = NULL, y = NULL) +
    scale_x_date(
      date_breaks = "1 year",
      date_labels = "%Y"
    ) +
    theme_bw() +
    coord_cartesian(clip = "off") +
    #scale_y_discrete(labels = \(x) parse(text = paste0('phantom("x")*"', x, '"'))) +
    scale_y_discrete(labels = \(x) paste0("\\enspace{}", format_text(x))) +
    theme(
      legend.title = element_text(size = 7),
      legend.text  = element_text(size = 7),
      legend.position = "inside",
      legend.position.inside = c(0.25, 0.045),
      legend.justification = c(0.5, 0),
      legend.direction = "horizontal",
      legend.background =
        element_rect(
          fill = scales::alpha("white", 0.45),
          color = "grey70",
          linewidth = 0.3
        ),
      legend.box.margin = margin(2, 4, 2, 4),
      legend.key = element_rect(fill = NA, color = NA),
      legend.key.width = unit(10, "pt"),
      legend.key.height = unit(13, "pt"),

      axis.text.y  = element_text(
        hjust = 0,
        margin = margin(r = -60),
        size = 7
      ),
      axis.text.x  = element_text(size = 8),
      axis.ticks.y = element_line(linewidth = 0.3, color = "black"),
      axis.ticks.length.y = unit(2, "pt"),

      plot.margin = margin(7.5, 8, 5.5, 10)
    ) +
    guides(color = guide_legend(nrow = 1, byrow = TRUE))
  save_plot(plot, filename, width = PAPER_TEXTWIDTH, height = violin_height)
}


# Load paper dates.
f_pd <- here("res/paper_dates.csv")
paper_dates <- read_csv(f_pd)

# Violin plot
f <- file.path(d_analysed, "contributions.csv")
f_dev <- file.path(d_analysed, "contributors_projects.csv")
df <- read_csv(f)
df_dev <- read_csv(f_dev)

monthly <- prepare_plot_data(df, df_dev, paper_dates)
#violin(monthly, "violin_selected")
violin_highlighted(monthly, "violin_h_selected")

# Ecosystem network plot
f_nodes <- file.path(d_analysed, "network_nodes.csv")
f_edges <- file.path(d_analysed, "network_edges.csv")
df_nodes <- read_csv(f_nodes)
df_edges <- read_csv(f_edges)

g <- create_network_graph(df_nodes, df_edges)
network_plot <- plot_network(g, df_nodes, df_edges, sf=0.6)
save_plot(network_plot, "network_plot", width = PAPER_LINEWIDTH, height=3)

# Graph and project statistics table
graph_stats <- create_graph_stats_table(g, df)
project_stats <- read.csv(file.path(d_analysed, "project_stats.csv"), stringsAsFactors = FALSE)
stats <- merge(graph_stats, project_stats, by = "project", all.x = TRUE)
tex <- create_latex_table(stats)
writeLines(tex, file.path(d_out, "table.tex"))


# # Additional analysis-only plots (to be removed before publication)
# f_all <- file.path(d_analysed, "all_contributions.csv")
# f_dev_all <- file.path(d_analysed, "all_contributors_projects.csv")
# df_all <- read_csv(f_all)
# df_dev_all <- read_csv(f_dev_all)
#
# # Violin plot for all projects
# monthly_all <- prepare_plot_data(df_all, df_dev_all, paper_dates, n_projects=3)
# #violin(monthly, "violin_all")
# violin_highlighted(monthly_all, "violin_h_all")
#
# # Network plot for all projects
# f_nodes_all <- file.path(d_analysed, "all_network_nodes.csv")
# f_edges_all <- file.path(d_analysed, "all_network_edges.csv")
# df_nodes_all <- read_csv(f_nodes_all)
# df_edges_all <- read_csv(f_edges_all)
#
# g <- create_network_graph(df_nodes_all, df_edges_all)
# network_plot <- plot_network(g, df_nodes_all, df_edges_all)
# save_plot(network_plot, "network_plot_all", width = PAPER_TEXTWIDTH, height=4)
#
# # Violin plot for non-selected projects
# conf <- yaml.load_file(here("analysis/conf.yml"))
# monthly_all <- prepare_plot_data(df_all, df_dev_all, paper_dates, n_projects=2)
# selected <- monthly_all %>%
#   filter(project %in% conf[["selected"]])
# not_selected <- monthly_all %>% filter(!project %in% selected$project) #%>% droplevels()
#
# #violin(not_selected, "violin_not_selected")
# violin_highlighted(not_selected, "violin_h_not_selected")

