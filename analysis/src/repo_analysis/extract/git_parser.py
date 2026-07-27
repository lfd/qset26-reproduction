import csv
import logging

from git import GitCommandError, Repo
from os import makedirs, path, listdir
from pandas import concat, read_csv, DataFrame
from perceval.backends.core.git import Git
from perceval.errors import RepositoryError

logger = logging.getLogger(__name__)


class GitExtractor:
    """
    Parser for git repositories.
    """

    @staticmethod
    def extract(repo_path: str, out_path: str) -> None:
        """
        Extract and store commits from the git repository. We use local
        clones to ensure that all subsequent analyses refer to the same
        repository state.

        Args:
            repo_path: Path to the git repository to parse.
            out_path: Path where the extracted logs will be stored.
        """
        makedirs(out_path, exist_ok=True)

        # Extract the package repository's git log with perceval and store
        # relevant information in tables.
        commit_path = path.join(out_path, f"commits.csv")
        file_path = path.join(out_path, f"files.csv")

        try:
            perceval_repo = Git(
                uri=repo_path,
                gitpath=f"/tmp/git-repo/{repo_path.split("/")[-1]}"
            )

            # Extract the git log with perceval and parse relevant
            # information into tables.
            try:
                # Determine default branch and fetch commits.
                git_repo = Repo(repo_path)
                br = [git_repo.remotes.origin.refs.HEAD.reference.remote_head]
                git_log = perceval_repo.fetch(branches=br)

                with open(
                        commit_path,
                        "w",
                        newline="",
                        encoding="utf-8",
                        errors="replace"
                ) as commit_table, \
                        open(
                            file_path,
                            "w",
                            newline="",
                            encoding="utf-8",
                            errors="replace"
                        ) as file_table:
                    commit_cols = [
                        "commit_hash",
                        "commit_message",
                        "author",
                        "author_date",
                        "committer",
                        "committer_date",
                        "added",
                        "removed"
                    ]
                    commit_writer = csv.DictWriter(
                        commit_table, fieldnames=commit_cols
                    )
                    commit_writer.writeheader()
                    file_cols = [
                        "commit_hash",
                        "file_path",
                        "action",
                        "added",
                        "removed"
                    ]
                    file_writer = csv.DictWriter(
                        file_table, fieldnames=file_cols
                    )
                    file_writer.writeheader()

                    for commit in git_log:
                        # Extract file statistics per commit.
                        added_sum = 0
                        removed_sum = 0

                        for file_change in commit["data"]["files"]:
                            action = file_change["action"] if \
                                "action" in file_change else "-"
                            added = file_change["added"] if \
                                "added" in file_change else 0
                            removed = file_change["removed"] if \
                                "removed" in file_change else 0

                            file_entry = {
                                "commit_hash": commit["data"]["commit"],
                                "file_path": file_change["file"],
                                "action": action,
                                "added": added,
                                "removed": removed
                            }
                            file_writer.writerow(file_entry)

                            if added != "-":
                                added_sum += int(added)
                            if removed != "-":
                                removed_sum += int(removed)

                        # Aggregate commit information.
                        commit_entry = {
                            "commit_hash": commit["data"]["commit"],
                            "commit_message": commit["data"]["message"],
                            "author": commit["data"]["Author"],
                            "author_date": commit["data"]["AuthorDate"],
                            "committer": commit["data"]["Commit"],
                            "committer_date": commit["data"]["CommitDate"],
                            "added": added_sum,
                            "removed": removed_sum
                        }
                        commit_writer.writerow(commit_entry)

            except RepositoryError as e:
                logger.warning(
                    f"Could not parse repository {repo_path} with perceval:\n"
                    f"{e}",
                    exc_info=True
                )

        except GitCommandError as e:
            logger.warning(
                f"Could not find git repository {repo_path}:\n{e}",
                exc_info=True
            )

    @staticmethod
    def merge_project_commits(
            extract_path: str,
            project_list: list[str]
    ) -> DataFrame:
        """
        Merges commits extracted from multiple projects into a single table.

        Args:
            extract_path: Path where the individual project commit tables are
                          stored.
            project_list: List of project names within the data extraction
                          directory to merge.

        Returns:
            The merged commit table.
        """
        commit_list = []
        for project in project_list:
            csv_path = path.join(extract_path, project, "commits.csv")
            if path.isfile(csv_path):
                commits = read_csv(csv_path)
                commits.insert(0, "project", project)
                commit_list.append(commits)
        return concat(commit_list, ignore_index=True)