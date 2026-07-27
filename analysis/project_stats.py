#!/usr/bin/env python3

import argparse
import os
import pandas as pd
import subprocess


def get_args():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--contributions",
        default="build/analysis/analysed/contributions.csv",
        help="Path to contributions.csv"
    )
    # Note: We need this because the contributions table aggregates data per
    # developer, meaning that the same commit can be counted multiple times
    # if several people contributed to it.
    parser.add_argument(
        "--commits",
        default="build/analysis/analysed/commits_processed.csv",
        help="Path to commits_processed.csv"
    )
    parser.add_argument(
        "--project_dir",
        default="projects",
        help="Base directory"
    )
    parser.add_argument(
        "--filter",
        default="analysis/conf.yml",
        help="Path to config file with projects to include in the analysis"
    )
    parser.add_argument(
        "--csv",
        default="build/analysis/analysed/project_stats.csv",
        help="Output CSV table path"
    )
    return parser.parse_args()


def run_cloc(repo_path: str) -> int:
    """
    Calculates lines of code (LoC) without blank lines and comments using cloc.

    Args:
        repo_path: Path to the git repository to analyze.

    Returns:
        LoC count.
    """
    result = subprocess.run(
        ["cloc", "--vcs=git", repo_path],
        capture_output=True,
        text=True,
        check=True,
    )
    for line in result.stdout.splitlines():
        if line.startswith("SUM:"):
            return int(line.split()[-1])
    raise RuntimeError(f"cloc produced no SUM line for {repo_path}")


# def format_num(n: int | None) -> str:
#     if n is None:
#         return "--"
#     return f"{n:,}".replace(",", ".")
#
#
def main():
    args = get_args()

    # Read input CSV files.
    df_contrib = pd.read_csv(args.contributions, parse_dates=["date"])
    df_commits = pd.read_csv(args.commits, usecols=["project", "commit_hash"])

    # Aggregate stats table from contributions and commits data.
    projects = sorted(set(df_contrib["project"]) | set(df_commits["project"]))
    stats = []
    for p in projects:
        p_contrib  = df_contrib[df_contrib["project"] == p]
        p_commits = df_commits[df_commits["project"] == p]

        start_year = p_contrib["date"].min().year
        end_year = p_contrib["date"].max().year

        # Outlier correction: filter commits which could be misleading when
        # calculating the project lifetime.
        gap_threshold_days = 365
        n_last_commits = 10

        # Print results for a manual sanity check.
        dates_list = p_contrib.sort_values("date")["date"].tolist()
        p_last_commits = dates_list[-n_last_commits:]
        print(f"{p}: Last {n_last_commits} commits on: {', '.join(
            d.date().isoformat() for d in p_last_commits
        )}")

        for i in range(len(p_last_commits)-1):
            gap = p_last_commits[i+1] - p_last_commits[i]
            if gap > pd.Timedelta(days=gap_threshold_days):
                new_end = p_last_commits[i].year
                print(f"  {p}: Commit gap of over 1 year detected. "
                      f"Adjusting end date from {end_year} to {new_end}.")
                end_year = new_end

        active = str(start_year) if start_year == end_year \
            else f"{start_year}--{end_year}"

        stats.append({
            "project": p,
            "commits": p_commits["commit_hash"].nunique(),
            "team": p_contrib["account"].nunique(),
            "active": active,
            "loc": None,   # filled in by cloc below
        })

    print(f"Analysing lines of code (LoC) with cloc...")
    for s in stats:
        repo_path = os.path.join(args.project_dir, s["project"])
        s["loc"] = run_cloc(repo_path)

    # Store the entire stats table for later use.
    stats_df = pd.DataFrame(stats)
    stats_df.to_csv(args.csv, index=False)

    # # Generate LaTex table.
    # conf = yaml.safe_load(open(args.filter))
    # p_filter = conf["selected"]
    # tex_table = write_table(stats, p_filter)
    # with open(args.tex, "w", encoding="utf-8") as fh:
    #     fh.write(tex_table)
    # print(f"LaTeX table exported to {args.tex}")

if __name__ == "__main__":
    main()