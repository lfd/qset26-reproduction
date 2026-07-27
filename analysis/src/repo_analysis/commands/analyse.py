import logging
import yaml

from os import listdir, path
from pandas import concat, read_csv

from repo_analysis.analyse.contributions import *
from repo_analysis.commands.input import AnalysisInput
from repo_analysis.extract.git_parser import GitExtractor
from repo_analysis.extract.identity import IdentityHandler

logger = logging.getLogger(__name__)

class AnalyseCmd(AnalysisInput):
    """
    Parse Git repositories with perceval.
    """

    @classmethod
    def run(cls, args):
        extract_path = args.extract_path.removesuffix("/")
        analysis_path = args.analysis_path.removesuffix("/")
        if not path.isdir(analysis_path):
            makedirs(analysis_path, exist_ok=True)

        logger.info("Running pipeline for all projects...")
        # Load extracted data for all projects.
        commit_table = read_csv(path.join(extract_path, f"all_commits.csv"))
        identities_table = read_csv(path.join(extract_path, f"all_identities.csv"))

        # Preprocess data.
        commit_table, identities_table = preprocess_data(
            commit_table,
            identities_table
        )
        commit_table.to_csv(
            f"{analysis_path}/all_commits_processed.csv",
            index=False
        )
        identities_table.to_csv(
            f"{analysis_path}/all_identities_processed.csv",
            index=False
        )

        # Prepare data for the violin contribution plot.
        contributions, contributors = analyse_contributions(
            commit_table,
            identities_table
        )
        contributors.to_csv(
            f"{analysis_path}/all_contributors_projects.csv",
            index=False
        )
        contributions.to_csv(
            f"{analysis_path}/all_contributions.csv",
            index=False
        )

        # Prepare data for the ecosystem network plot.
        node_table, edge_table = aggregate_network_data(
            contributions,
            contributors
        )
        node_table.to_csv(
            f"{analysis_path}/all_network_nodes.csv",
            index=False
        )
        edge_table.to_csv(
            f"{analysis_path}/all_network_edges.csv",
            index=False
        )

        logger.info("Rerunning pipeline for selected projects...")
        # Load extracted data for selected projects.
        commit_table = read_csv(path.join(extract_path, f"commits.csv"))
        identities_table = read_csv(path.join(extract_path, f"identities.csv"))

        # Preprocess data.
        commit_table, identities_table = preprocess_data(
            commit_table,
            identities_table
        )
        commit_table.to_csv(
            f"{analysis_path}/commits_processed.csv",
            index=False
        )
        identities_table.to_csv(
            f"{analysis_path}/identities_processed.csv",
            index=False
        )

        # Prepare data for the violin contribution plot.
        contributions, contributors = analyse_contributions(
            commit_table,
            identities_table
        )
        contributors.to_csv(
            f"{analysis_path}/contributors_projects.csv",
            index=False
        )
        contributions.to_csv(
            f"{analysis_path}/contributions.csv",
            index=False
        )

        # Prepare data for the ecosystem network plot.
        node_table, edge_table = aggregate_network_data(
            contributions,
            contributors
        )
        node_table.to_csv(
            f"{analysis_path}/network_nodes.csv",
            index=False
        )
        edge_table.to_csv(
            f"{analysis_path}/network_edges.csv",
            index=False
        )

    @classmethod
    def setup_parser(cls, parser):
        cls.parser_add_analysis_input_args(parser)