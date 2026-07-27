import logging
import yaml

from os import listdir, path, makedirs
from pandas import concat, read_csv

from repo_analysis.commands.input import GitInput
from repo_analysis.extract.git_parser import GitExtractor
from repo_analysis.extract.identity import IdentityHandler

logger = logging.getLogger(__name__)


class ExtractCmd(GitInput):
    """
    Parse Git repositories with perceval.
    """

    @classmethod
    def run(cls, args):
        git_extractor = GitExtractor()

        repo_path = args.repo_path.removesuffix("/")
        extract_path = args.extract_path.removesuffix("/")

        if not path.exists(extract_path):
            makedirs(extract_path)

        # Extract commit data for each project.
        for project in listdir(repo_path):
            project_repo_path = f"{repo_path}/{project}"
            project_extract_path = f"{extract_path}/{project}"
            git_extractor.extract(project_repo_path, project_extract_path)

        logger.info("Running pipeline for all projects...")
        # Merge all commits into a single table.
        project_list = listdir(extract_path)
        all_commits = git_extractor.merge_project_commits(
            extract_path,
            project_list
        )

        # Merge diverging developer identities in the extracted data.
        identity_handler = IdentityHandler()
        all_commits, identities = identity_handler.merge(all_commits)
        all_commits.to_csv(f"{extract_path}/all_commits.csv", index=False)
        identity_path = f"{extract_path}/all_identities.csv"
        identities.to_csv(identity_path, index=False)

        logger.info("Rerunning pipeline for selected projects...")
        # Load analysis configuration.
        conf = yaml.safe_load(open(args.conf_path))
        commits = git_extractor.merge_project_commits(
            extract_path,
            conf["selected"]
        )

        # Merge diverging developer identities in the extracted data.
        identity_handler = IdentityHandler()
        commits, identities = identity_handler.merge(commits)
        commits.to_csv(f"{extract_path}/commits.csv", index=False)
        identity_path = f"{extract_path}/identities.csv"
        identities.to_csv(identity_path, index=False)


    @classmethod
    def setup_parser(cls, parser):
        cls.parser_add_git_input_args(parser)
