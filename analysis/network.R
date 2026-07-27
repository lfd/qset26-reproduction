library(igraph)
library(ggnetwork)
library(ggrepel)
library(scales)

normalise_project_name <- function(x) {
  x <- gsub("_", "-", x)
  ifelse(x == "cuda-quantum", "cuda-q", x)
}

format_text <- function(x) toupper(normalise_project_name(x))


create_network_graph <- function(net_nodes, net_edges) {
  net_nodes <- net_nodes[order(net_nodes$name), ]
  net_edges <- net_edges[order(net_edges$from, net_edges$to), ]

  # Determine cross-project contributor edges. These will be plotted in a
  # different color to highlight them stand out.
  cross_lookup <- setNames(net_nodes$is_cross_project, net_nodes$name)
  net_edges$edge_type <- ifelse(
    cross_lookup[net_edges$from] %in% TRUE |
      cross_lookup[net_edges$to] %in% TRUE,
    "cross_dev",
    "other"
  )

  g <- graph_from_data_frame(
    net_edges,
    directed = FALSE,
    vertices = net_nodes
  )

  return(g)
}

cap01 <- function(x, pad = 0.06) {
  # Helper function to ensure that coordinates stay within the canvas.
  pmin(pmax(x, pad), 1 - pad)
}

scale_to_canvas <- function(lo, q = 0.90, pad = 0.06) {
  # Distribute nodes equally across the entire canvas.
  
  # Center the layout around the median (affects especially far-away clusters).
  lo <- sweep(lo, 2, apply(lo, 2, median, na.rm = TRUE), "-")
  
  # Determine scale by the majority of nodes.
  r <- sqrt(rowSums(lo^2))
  s <- quantile(r, probs = q, na.rm = TRUE)
  
  # Fallback for degenerate layouts.
  if (!is.finite(s) || s == 0) s <- max(r, na.rm = TRUE)
  if (!is.finite(s) || s == 0) s <- 1
  
  # Scale coordinates by the robust distance.
  lo <- lo / s
  
  # Keep some space from the canvas border to prevent a square-looking layout.
  r <- sqrt(rowSums(lo^2))
  lo <- lo * ifelse(r > 0, tanh(r) / r, 1)
  pad + ((lo + 1) / 2) * (1 - 2 * pad)
}

pull_small_components <- function(lo, g, pull = 0.35) {
  # Helper function to pull disconnected nodes closer to the layout center.
  comp <- components(g)
  main_comp <- which.max(comp$csize)
  global_center <- colMeans(lo)
  
  for (cid in setdiff(seq_along(comp$csize), main_comp)) {
    idx <- which(comp$membership == cid)
    shift <- (global_center - colMeans(lo[idx, , drop = FALSE])) * pull
    lo[idx, ] <- sweep(lo[idx, , drop = FALSE], 2, shift, "+")
  }
  
  lo
}

repel_pairs <- function(lo, pairs,
                        min_dist = 0.08,
                        strength = 0.5,
                        n_iter = 100,
                        pad = 0.06,
                        clamp_idx = unique(as.vector(pairs))) {
  # Helper function to prevent selected node pairs from overlapping.
  if (length(pairs) == 0 || nrow(pairs) == 0) return(lo)
  
  # Iterate node pairs to adjust their spacing.
  for (iter in seq_len(n_iter)) {
    for (k in seq_len(nrow(pairs))) {
      i <- pairs[k, 1]
      j <- pairs[k, 2]
      
      delta <- lo[i, ] - lo[j, ]
      dist <- sqrt(sum(delta^2))
      
      if (!is.finite(dist)) next
      
      if (dist < min_dist) {
        direction <- if (dist < 1e-8) {
          angle <- 2 * pi * (k + iter) / nrow(pairs)
          c(cos(angle), sin(angle))
        } else {
          delta / dist
        }
        
        move <- direction * (min_dist - dist) * strength / 2
        
        lo[i, ] <- lo[i, ] + move
        lo[j, ] <- lo[j, ] - move
      }
    }
    
    lo[clamp_idx, 1] <- cap01(lo[clamp_idx, 1], pad)
    lo[clamp_idx, 2] <- cap01(lo[clamp_idx, 2], pad)
  }
  
  lo
}

project_dev_pairs <- function(g) {
  # Helper function to determine edges between a project and a developer.
  ed <- as_edgelist(g, names = FALSE)
  
  is_project <- V(g)$type == "project"
  is_dev <- !is_project
  
  keep <- (is_project[ed[, 1]] & is_dev[ed[, 2]]) |
    (is_project[ed[, 2]] & is_dev[ed[, 1]])
  
  if (!any(keep)) {
    return(matrix(integer(), nrow = 0, ncol = 2))
  }
  
  ed <- ed[keep, , drop = FALSE]
  
  cbind(
    project = ifelse(is_project[ed[, 1]], ed[, 1], ed[, 2]),
    dev = ifelse(is_project[ed[, 1]], ed[, 2], ed[, 1])
  )
}

push_devs_from_projects <- function(lo, g,
                                    min_dist = 0.045,
                                    strength = 1,
                                    n_iter = 50,
                                    pad = 0.06) {
  # Adjust spacing between project and developer nodes to avoid overlap.
  pairs <- project_dev_pairs(g)
  if (nrow(pairs) == 0) return(lo)
  
  dev_idx <- unique(pairs[, 2])
  
  # Iterate node pairs to adjust the spacing.
  for (iter in seq_len(n_iter)) {
    for (k in seq_len(nrow(pairs))) {
      p <- pairs[k, 1]
      d <- pairs[k, 2]
      
      delta <- lo[d, ] - lo[p, ]
      dist <- sqrt(sum(delta^2))
      
      if (!is.finite(dist) || dist >= min_dist) next
      
      direction <- if (dist < 1e-8) {
        angle <- 2 * pi * (k + iter) / nrow(pairs)
        c(cos(angle), sin(angle))
      } else {
        delta / dist
      }
      
      target <- lo[p, ] + direction * min_dist
      lo[d, ] <- (1 - strength) * lo[d, ] + strength * target
    }
    
    lo[dev_idx, 1] <- cap01(lo[dev_idx, 1], pad)
    lo[dev_idx, 2] <- cap01(lo[dev_idx, 2], pad)
  }
  
  lo
}

pull_single_devs <- function(lo, g, net_edges, pull = 0.45) {
  # Move single project contributors closer to their corresponding project.
  rownames(lo) <- V(g)$name
  
  projects <- V(g)$name[V(g)$type == "project"]
  singles <- V(g)$name[
    V(g)$type != "project" & !(V(g)$is_cross_project %in% TRUE)
  ]
  
  for (dev in singles) {
    nbrs <- unique(c(
      net_edges$to[net_edges$from == dev],
      net_edges$from[net_edges$to == dev]
    ))
    
    proj <- intersect(nbrs, projects)[1]
    
    if (!is.na(proj)) {
      lo[dev, ] <- (1 - pull) * lo[dev, ] + pull * lo[proj, ]
    }
  }
  
  lo
}

jitter_devs <- function(lo, g,
                        radius = c(0.004, 0.018),
                        seed = 43) {
  # Add a small random offset to developer node positions.
  set.seed(seed)
  
  dev_idx <- which(V(g)$type != "project")
  
  angle <- runif(length(dev_idx), 0, 2 * pi)
  r <- runif(length(dev_idx), radius[1], radius[2])
  
  lo[dev_idx, ] <- lo[dev_idx, ] + cbind(
    cos(angle) * r,
    sin(angle) * r
  )
  
  lo
}

create_network_layout <- function(g, net_edges,
                                seed = 42,
                                pad = 0.06) {
  # Creates a graph layout with lots of (AI-co-developed) tweaks.
  set.seed(seed)
  lo <- layout_with_fr(g, niter = 10000)
  
  # Spread project nodes across the canvas.
  # This avoids that a large cluster of connected projects is densely clustered
  # in one part of the canvas, while one or few single projects are pushed to
  # the outside and create a large gap.
  proj_idx <- which(V(g)$type == "project")
  
  if (length(proj_idx) > 0) {
    angle <- seq(0, 2 * pi, length.out = length(proj_idx) + 1)[-1]
    lo[proj_idx, ] <- lo[proj_idx, ] +
      cbind(cos(angle), sin(angle)) * 0.01
  }
  
  lo <- scale_to_canvas(lo, q = 0.90, pad = pad)
  
  # Extra adjustment to pull isolated (smaller) projects.
  lo <- pull_small_components(lo, g, pull = 0.35)
  
  if (length(proj_idx) > 1) {
    lo <- repel_pairs(
      lo,
      pairs = t(combn(proj_idx, 2)),
      min_dist = 0.12,
      strength = 0.4,
      n_iter = 1000,
      pad = pad,
      clamp_idx = proj_idx
    )
  }
  
  # Push developer nodes away from the project nodes to avoid that project
  # nodes hide them (especially in the smaller projects).
  lo <- push_devs_from_projects(
    lo,
    g,
    min_dist = 0.045,
    strength = 1,
    n_iter = 50,
    pad = pad
  )
  
  # Pull single project developer nodes closer to the projects to give more
  # visual attention to cross-project collaborations.
  lo <- pull_single_devs(
    lo,
    g,
    net_edges,
    pull = 0.45
  )
  
  # Avoid developer overlap, especially for the smaller projects.
  lo <- jitter_devs(
    lo,
    g,
    radius = c(0.004, 0.018),
    seed = seed + 1
  )
  
  lo
}

plot_network <- function(g, net_nodes, net_edges, sf=1) {
  # Create the graph layout.
  lo <- create_network_layout(g, net_edges, seed = 4200, pad = 0.01*sf)
  gnet <- ggnetwork(g, layout = lo)
  
  # Scale developer nodes according to the number of commits contributed in the
  # entire ecosystem. Together with the edges and their sizes, this indicates
  # whether they focused on a single or multiple projects.
  gnet$node_size <- ifelse(
    gnet$type == "project",
    5*sf,
    scales::rescale(log1p(gnet$node_commits), to = c(0.3*sf, 4*sf))
  )

  gnet$tex_label <- format_text(gnet$name)
  
  # Prepare cross-project contributor highlighting.
  gnet$color_group <- ifelse(
    gnet$is_cross_project %in% TRUE,
    "cross_dev",
    "single_dev"
  )
  
  ggplot(gnet, aes(x, y, xend = xend, yend = yend)) +
    geom_edges(
      aes(
        linewidth = commit_intensity,
        alpha = commit_intensity,
        color = edge_type
      ),
      curvature = 0.1*sf
    ) +
    geom_nodes(
      data = function(x) subset(x, type == "project"),
      aes(size = node_size),
      color = scales::alpha("#999999", 0.5),
      shape = 16
    ) +
    geom_nodes(
      data = function(x) subset(x, type != "project"),
      aes(color = color_group, shape = is_cross_project, size = node_size)
    ) +
    geom_nodelabel_repel(
      data = function(x) subset(x, type == "project"),
      aes(label = tex_label),
      color = "#555555",
      fill = scales::alpha("white", 0.5),
      box.padding = unit(0.15*sf, "lines"),
      label.padding = unit(0.2*sf, "lines"),
      min.segment.length = 0,
      size = 1+2*sf,
      max.overlaps = 50
    ) +
    scale_color_manual(values = c(
      cross_dev = "#1f78b4",
      single_dev = "#beaed4"
    )) +
    scale_size_identity() +
    scale_shape_manual(values = c("TRUE" = 17, "FALSE" = 16), na.value = 16) +
    scale_linewidth(range = c(0.15, 0.7)) +
    scale_alpha(range = c(0.2, 0.75)) +
    #coord_equal(xlim = c(-0.03, 1.03), ylim = c(-0.03, 1.03), expand = FALSE, clip = "off") +
    coord_fixed(ratio = 3 / 3.48761,
                xlim = c(-0.03, 1.03), ylim = c(-0.03, 1.03),
                expand = FALSE, clip = "off")+
    theme_void() +
    theme(legend.position = "none",
          plot.margin = margin(0, 0, 0, 0))
}

create_graph_stats_table <- function(g,
                                     contributions,
                                     research_projects = c(),
                                     industrial_projects = c(),
                                     org_domains = list()) {
  project_names <- V(g)$name[V(g)$type == "project"]

  # Compute developer attributes.
  dev_idx <- which(V(g)$type == "developer")

  stat_rows <- lapply(project_names, function(p) {
    p_vertex <- which(V(g)$name == p)

    # Developers directly connected to this project (1 hop).
    nbr <- neighbors(g, p_vertex)
    dev_nbr <- nbr[V(g)$type[nbr] == "developer"]

    # Distinguish developer cross-project/single-project status.
    is_cross <- V(g)$is_cross_project[dev_nbr]
    n_cross  <- sum(is_cross %in% TRUE)
    n_single <- sum(is_cross %in% FALSE)

    # Calculate percentage of cross-project developers.
    total_dev <- n_cross + n_single
    pct_single <- if (total_dev > 0) n_single / total_dev else NA_real_
    pct_cross <- if (total_dev > 0) n_cross / total_dev else NA_real_

    # Calculate median degree of directly connected developers (number of
    # projects they contribute to).
    if (length(dev_nbr) > 0) {
      median_dev_degree <- median(degree(g, v = dev_nbr))
    } else {
      median_dev_degree <- NA_real_
    }

    # Projects directly reachable with one developer in between (2 hops).
    reachable_projects <- character(0)
    for (d in dev_nbr) {
      d_nbr <- neighbors(g, d)
      d_projects <- V(g)$name[d_nbr[V(g)$type[d_nbr] == "project"]]
      reachable_projects <- union(reachable_projects, d_projects)
    }
    reachable_projects <- setdiff(reachable_projects, p)  # exclude self
    n_reachable <- length(reachable_projects)

    # Number of developers (busiest first) whose cumulative commits
    # reach >= 80% of a project's total commits (similar to bus factor).
    proj_contrib <- contributions %>% filter(project == p)
    dev_commits_p <- proj_contrib %>%
      group_by(account) %>%
      summarise(c = sum(count), .groups = "drop") %>%
      arrange(desc(c)) %>%
      pull(c)

    n_devs_core <- if (sum(dev_commits_p) > 0) {
      which(cumsum(dev_commits_p) / sum(dev_commits_p) >= 0.8)[1]
    } else {
      NA_integer_
    }

    n_devs_peripheral <- if (length(dev_commits_p) > 0) {
      length(dev_commits_p) - n_devs_core
    } else {
      NA_integer_
    }

    # Assemble table.
    data.frame(
      project = p,
      pct_single_devs = pct_single, 1,
      pct_cross_devs = pct_cross, 1,
      median_dev_degree = median_dev_degree,
      n_devs_core = n_devs_core,
      n_devs_peripheral = n_devs_peripheral,
      n_reachable  = n_reachable,
      stringsAsFactors = FALSE
    )
  })

  do.call(rbind, stat_rows)
}

format_num_0 <- function(x) {
  if (is.na(x)) return("--")
  formatC(x, format = "d", big.mark = ",")
}

format_num_2 <- function(x) {
  if (is.na(x)) return("--")
  formatC(x, format = "f", digits = 2, big.mark = ",")
}

format_num_k <- function(x) {
  if (is.na(x)) return("--")
  formatC(x / 1000, format = "f", digits = 0, big.mark = ",")
}

create_latex_table <- function(stats) {
  make_row <- function(s) {
    sprintf(
      "        %s & %s & %s & %s & %s & %s & %s & %s & %s & %s & %s \\\\",
      paste0("\\textsc{", normalise_project_name(s$project), "}"),
      format_num_0(s$commits),
      format_num_k(s$loc),
      format_num_0(s$team),
      s$active,
      format_num_2(s$pct_single_devs),
      format_num_2(s$pct_cross_devs),
      format_num_0(s$n_devs_core),
      format_num_0(s$n_devs_peripheral),
      format_num_2(s$median_dev_degree),
      format_num_0(s$n_reachable)
    )
  }

  row_lines <- paste(
    vapply(seq_len(nrow(stats)),
           function(i) make_row(stats[i, ]),
           character(1)),
    collapse = "\n"
  )

  # Rotate header labels 90 degrees.
  rot <- function(txt) paste0("\\rotatebox{90}{\\shortstack[l]{", txt, "}}")

  header <- paste(
    "Project",
    rot("Commits"),
    rot("LoC[k]"),
    rot("Team Size"),
    rot("Active\\\\Development\\\\Time"),
    rot("Exclusive\\\\Dev. Ratio"),
    rot("Cross-Project\\\\Dev. Ratio"),
    rot("Core Devs."),
    rot("Peripheral\\\\Devs."),
    rot("Median\\\\Projects/Dev."),
    rot("Linked\\\\Projects"),
    sep = " & "
  )

  paste0(
    "  \\begin{tblr}{colspec={Xrrrlrrrrrr},\n",
    "                colsep=2.9pt,rowsep=0.6pt,\n",
    "                row{odd}={bg=gray!15},\n",
    "                row{1}={bg=white,fg=black}}\n",
    "        \\toprule\n",
    "        ", header, " \\\\ \\midrule\n",
    row_lines, "\n",
    "        \\bottomrule\n",
    "  \\end{tblr}\n"
  )
}