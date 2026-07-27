import logging
import re

from os import makedirs, path
from pandas import concat, read_csv, DataFrame, to_datetime

logger = logging.getLogger(__name__)

def extract_date(date_str: str):
    """
    Extract date in format YYYY-MM-DD from date string.

    Args:
        date_str: Date string in format "Thu May 30 17:42:31 2024 +0200".

    Returns:
        Date string in format "YYYY-MM-DD" or None if parsing fails.
    """
    try:
        return to_datetime(
            date_str,
            format="%a %b %d %H:%M:%S %Y %z"
        ).strftime("%Y-%m-%d")
    except Exception:
        return None


def extract_domain(identity: str):
    """
    Extract domain from an identity string.

    Args:
        identity: Identity string in format "Name <E-Mail>".

    Returns:
        Domain string or None if parsing fails.
    """
    match = re.search(r"@([\w.\-]+)>?", identity)
    return match.group(1) if match else None


def remove_bots(contributors: DataFrame, dev_cols: list[str]) -> DataFrame:
    """
    Helper function to remove bot accounts from a table based on
    common bot patterns in the identity strings.

    Args:
        contributors: Table to filter.
        dev_cols: List of identity columns to check for bot patterns.

    Returns:
        The filtered table with bot accounts removed.
    """
    bot_patterns = [
        r"\[bot\]",
        r"dependabot",
        r"hugrbot",
        r"eidrynbot",
        r"qiskit-bot",
        r"github-actions",
        r"renovate",
        r"noreply@github.com",
        r"noreply@github.ibm.com",
        r"noreply@gitee.com"
    ]
    p = "|".join(bot_patterns)

    for c in dev_cols:
        mask = contributors[c].str.contains(
            p,
            case=False,
            na=False,
            regex=True
        )
        contributors = contributors[~mask].reset_index(drop=True)
    return contributors


def remove_merge_commits(commit_table: DataFrame) -> DataFrame:
    """
    Helper function to remove merge commits from the commit table based on
    a simple heuristic.

    Args:
        commit_table: Commits table with a "message" column.

    Returns:
        The filtered table with merge commits removed.
    """
    merge_pattern = re.compile(
        r"^merge branch|"
        r"^merge remote-tracking branch|"
        r"^merge pull request|"
        r"^merge tag|"
        r"^merge commit|"
        r"^auto-merge",
        flags=re.IGNORECASE
    )
    commit_table = commit_table[~commit_table["commit_message"].str.contains(
        merge_pattern, regex=True, na=False
    )]
    return commit_table


def aggregate_commits(commit_table: DataFrame) -> DataFrame:
    """
    Aggregate commits into a table summarising the number of contributions per
    day and developer with columns:
    project, date, account, domain, count.

    Authors and committers are treated as separate entries/accounts if they
    differ.

    Args:
        commit_table: Commits table with columns project, commit_hash,
                      author, committer, committer_date, etc.

    Returns:
        Summary table.
    """
    committers = DataFrame({"committer": commit_table["committer"].unique()})
    no_bot_committers = set(
        remove_bots(committers, ["committer"])["committer"]
    )

    dates = commit_table["committer_date"].apply(extract_date)

    author_rows = DataFrame({
        "project": commit_table["project"].values,
        "date": dates.values,
        "account": commit_table["author"].values,
        "domain": commit_table["original_author"].apply(extract_domain).values,
    })

    committer_mask = (
        (commit_table["committer"] != commit_table["author"]) &
        commit_table["committer"].isin(no_bot_committers)
    )
    committer_subset = commit_table[committer_mask]
    committer_rows = DataFrame({
        "project": committer_subset["project"].values,
        "date": dates[committer_mask].values,
        "account": committer_subset["committer"].values,
        "domain": committer_subset["original_committer"].apply(extract_domain).values,
    })

    table = concat([author_rows, committer_rows], ignore_index=True)

    aggregated_table = (
        table
        .groupby(["project", "date", "account", "domain"])
        .size()
        .reset_index(name="count")
    )

    return aggregated_table


def preprocess_data(
        commit_table: DataFrame,
        identities_table: DataFrame
) -> tuple[DataFrame, DataFrame]:
    """
    Apply preprocessing steps to commit and identities table before analysis.

    Args:
        commit_table: Commits table with columns project, commit_hash,
                      author, committer, committer_date, etc.
        identities_table: Identities table with column identity.

    Returns:
        The preprocessed tables.
    """
    logger.info("Preprocessing data...")

    # Remove merge commits as they do not represent actual contributions.
    logger.info("Removing merge commits...")
    commit_table = remove_merge_commits(commit_table)

    # Remove bots.
    logger.info("Removing bots...")
    commit_table = remove_bots(commit_table, ["author"])
    identities_table = remove_bots(identities_table, ["identity"])

    return commit_table, identities_table


def analyse_contributions(
        commit_table: DataFrame,
        identities_table: DataFrame
) -> tuple[DataFrame, DataFrame]:
    """
    Get cross-project contributions from the extracted data and aggregate
    contribution data sets summarising the number of contributions per day
    and developer as well as the cross-project statistics.

    Args:
        commit_table: Commits table with columns project, commit_hash,
                        author, committer, committer_date, etc.
        identities_table: Identities table with column identity.

    Returns:
        Tuple of (contributions, contributors) for further analysis.
    """
    logger.info("Analysing cross-project contributors...")

    # Get developer activity per project.
    projects = commit_table.project.unique().tolist()
    contributors = identities_table.reindex(
        columns=identities_table.columns.tolist() + projects
    )
    contributors[projects] = 0

    for p in projects:
        project_commits = commit_table[commit_table["project"] == p]

        active = concat([
            project_commits[["author"]].rename(
                columns={"author": "identity"}
            ),
            project_commits[["committer"]].rename(
                columns={"committer": "identity"}
            ),
        ])

        counts = active.groupby("identity").size()
        contributors[p] = contributors["identity"].map(
            counts
        ).fillna(0).astype(int)

    # Aggregate the number of projects per contributor.
    contributors["num_projects"] = (contributors[projects] > 0).sum(axis=1)
    contributors.sort_values(by=["num_projects"], ascending=False, inplace=True)

    # Aggregate contributions per day and developer.
    logger.info("Aggregating contributions per day and developer...")
    contributions = aggregate_commits(commit_table)

    return contributions, contributors


def analyse_shared_commits(extract_path: str, analysis_path: str) -> None:
    """
    Analyse shared commits across projects from the extracted data.

    Args:
        extract_path: Path where the extracted logs are stored.
        analysis_path: Path where the analysis results are stored.
    """
    logger.info("Analysing shared commits across projects...")
    commit_table = read_csv(path.join(extract_path, "all_commits.csv"))

    # Get commit hashes that appear in multiple projects.
    shared_commits = commit_table.groupby("commit_hash").filter(
        lambda x: len(x) > 1
    )
    shared_commits.to_csv(
        f"{analysis_path}/shared_commits.csv",
        index=False
    )


def aggregate_network_data(
        contributions: DataFrame,
        contributors: DataFrame
) -> tuple[DataFrame, DataFrame]:
    """
    Construct node and edge tables for the ecosystem network plot.

    Args:
        contributions: Table with project, date, account, domain, count.
        contributors: Table with identity and per-project commit counts.

    Returns:
        Tuple of (node_table, edge_table).
    """
    logger.info("Constructing developer network tables...")
    projects = [
        c for c in contributors.columns
        if c not in ("identity", "num_projects")
    ]

    # Aggregate developer node attributes.
    dev_total = contributors.copy()
    dev_total["node_commits"] = dev_total[projects].sum(axis=1)
    dev_nodes = (
        dev_total[["identity", "node_commits", "num_projects"]]
        .assign(
            name=lambda df: df["identity"],
            type="developer",
            is_cross_project=lambda df: df["num_projects"] >= 2
        )
        [["name", "type", "node_commits", "num_projects", "is_cross_project"]]
    )

    # Aggregate project node attributes.
    proj_nodes = (
        contributions.groupby("project")["count"].sum()
        .reset_index()
        .assign(
            name=lambda df: df["project"],
            type="project",
            is_cross_project=None,
            # Total number of commits in the project.
            node_commits=lambda df: df["count"]
        )
        [["name", "type", "node_commits", "is_cross_project"]]
    )
    node_table = concat([dev_nodes, proj_nodes], ignore_index=True)

    # Compute each developer's monthly share of project activity.
    contributions["date"] = to_datetime(contributions["date"])
    contributions["month"] = contributions["date"].dt.to_period("M")

    # Aggregate monthly commits per developer per project.
    monthly = (
        contributions.groupby(["account", "project", "month"])["count"].sum()
        .reset_index()
    )

    # Total commits per project per month, considering all developers.
    project_month_totals = (
        monthly.groupby(["project", "month"])["count"].sum()
        .reset_index()
        .rename(columns={"count": "project_month_commits"})
    )
    monthly = monthly.merge(project_month_totals, on=["project", "month"])
    monthly["share"] = monthly["count"] / monthly["project_month_commits"]

    # Aggregate edge attributes.
    edge_table = (
        monthly.groupby(["account", "project"])
        .agg(
            edge_commits=("count", "sum"),
            months_active=("month", "nunique"),
            # Mean share of a project's monthly activity during the
            # developer's active months in the project. This should indicate
            # developer coreness during their active period in the project.
            commit_intensity=("share", "mean")
        )
        .reset_index()
        .assign(
            **{"from": lambda df: df["account"]},
            to=lambda df: df["project"],
        )
        [["from", "to", "edge_commits", "months_active", "commit_intensity"]]
    )

    return node_table, edge_table