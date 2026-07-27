import logging
import re

from os import listdir, path
from pandas import DataFrame, concat, read_csv

logger = logging.getLogger(__name__)


class IdentityHandler:
    """
    Handler for developer identities..
    """

    @staticmethod
    def _find_by_email(
            dev: str,
            identities: DataFrame
    ) -> tuple[int | None, str | None]:
        """
        Helper function to search for a developer by his e-mail address.

        Args:
            dev: Single name and e-mail address of the developer.
            identities: Identity table.

        Returns:
            Index and identity of the matching developer.
        """
        pattern = re.compile(r"<(.*?)>")
        for m in re.finditer(pattern, dev):
            id_1_email = m.group(1)

            # Replace invalid e-mail addresses to not match these identities.
            id_1_email = id_1_email.replace('(none)', '')
            if len(id_1_email) <= 1:
                continue

            # Add braces to avoid partial matches with incorrectly formatted
            # local domains.
            id_1_email = "<"+id_1_email+">"

            # Compare the given e-mail address to the other e-mail addresses.
            for idx, row in identities.iterrows():
                id_2 = row["identity"]
                if id_1_email in id_2:
                    return idx, id_2
        return None, None

    @staticmethod
    def _find_by_name(
            name: str,
            identities: DataFrame
    ) -> tuple[int | None, str | None]:
        """
        Helper function to search for a developer by his name.

        Args:
            name: Name of the developer.
            identities: Identity table.

        Returns:
            Index and identity of the matching developer.
        """
        for idx, row in identities.iterrows():
            id_2 = row["identity"]
            id_2_parts = id_2.split(" | ")
            for p_2 in id_2_parts:
                id_2_name = p_2.split("<")[0]
                # Use exact string matching to ignore partial matches
                # such as first name with different last name.
                if name == id_2_name:
                    return idx, id_2
        return None, None

    @staticmethod
    def _extract_github_username(dev: str) -> str | None:
        """
        Helper function to extract a GitHub username from a noreply email.

        Args:
            dev: Single name and e-mail address of the developer.

        Returns:
            The GitHub username if in the GitHub noreply email, None otherwise.
        """
        pattern = re.compile(
            r"(\d+\+([^@]+)|([^@]+))@users\.noreply\.github\.com"
        )
        m = pattern.search(dev)
        if m:
            return m.group(2) or m.group(3)
        return None

    def _find_by_github_username(
            self,
            dev: str,
            identities: DataFrame
    ) -> tuple[int | None, str | None]:
        """
        Helper function to search for a developer by his GitHub username in
        a noreply email.

        Args:
            dev: Single name and e-mail address of the developer.
            identities: Identity table.

        Returns:
            Index and identity of the matching developer.
        """
        username = self._extract_github_username(dev)
        if not username:
            return None, None

        for idx, row in identities.iterrows():
            if self._extract_github_username(row["identity"]) == username:
                return idx, row["identity"]
        return None, None

    def _create_id_table(
            self,
            commits_table: DataFrame
    ) -> DataFrame:
        """
        Helper function to construct a single source of truth identity table
        containing the merged unique person identities.

        Args:
            commits_table: Commits table.

        Returns:
            Merged identities table.
        """
        unique_ids = set(commits_table[["author", "committer"]].stack())
        identities = DataFrame()

        for id_1 in unique_ids:
            exact_match = False  # Matching name and e-mail address
            email_match = False  # Matching e-mail address, but different name
            github_match = False # Matching GitHub username in noreply address
            name_match = False  # Matching name, but different e-mail address

            # Search for matches of both e-mail address and name.
            for idx, row in identities.iterrows():
                id_2 = row["identity"]
                if id_1 in id_2:
                    exact_match = True
                    break

            # Search for e-mail address matches.
            if not exact_match:
                idx, id_2 = self._find_by_email(id_1, identities)
                if idx is not None and id_2 is not None:
                    logger.debug("Adding %s to identity %s.", id_1, id_2)
                    identities.loc[idx, "identity"] += " | "+id_1
                    email_match = True

            # Search for GitHub username matches in noreply addresses.
            if not exact_match and not email_match:
                idx, id_2 = self._find_by_github_username(id_1, identities)
                if idx is not None and id_2 is not None:
                    logger.debug("Adding %s to identity %s.", id_1, id_2)
                    identities.loc[idx, "identity"] += " | "+id_1
                    github_match = True

            # Search for name matches.
            if not exact_match and not email_match and not github_match:
                id_1_name = id_1.strip(" ").split("<")[0]
                if id_1_name.strip(" ") == "unknown":
                    # Identities named unknown should not be matched based on
                    # name because "unknown" might result from an API issue.
                    continue

                idx, id_2 = self._find_by_name(id_1_name, identities)
                if idx is not None and id_2 is not None:
                    logger.debug("Adding %s to identity %s.", id_1, id_2)
                    identities.loc[idx, "identity"] += " | "+id_1
                    name_match = True

            if not exact_match and not email_match and not name_match:
                # Add a newly observed identity.
                logger.debug("Adding new identity for %s", id_1)
                entry = DataFrame({"identity": [id_1]})
                identities = concat([identities, entry], ignore_index=True)

        # Due to unfortunate order of adding identities, some matching criteria
        # may not be fulfilled even though there is a match. For instance,
        # developers A <a@example.com> and Anna <anna@example.com> cannot
        # be matched if we neither observed A using <anna@example.com> nor Anna
        # using <a@example.com> before.
        return identities

    @staticmethod
    def _replace_ids(
            identities: DataFrame,
            commits_table: DataFrame
    ) -> DataFrame:
        """
        Helper function to replace possibly diverging identities in the commits
        table.

        Args:
            identities: Existing identity table with unique person identities.
            commits_table: Commits table with potentially diverging identities.

        Returns:
            Commits table with merged identities.
        """
        unique_ids = set(commits_table[["author", "committer"]].stack())

        # Search for exact matches and replace diverging identities.
        for id_1 in list(unique_ids):
            for idx, row in identities.iterrows():
                id_2 = row["identity"]
                if id_1 != id_2 and id_1 in id_2:
                    logger.debug("Replacing %s by %s.", id_1, id_2)
                    commits_table.loc[commits_table["author"].str.contains(
                        id_1,
                        regex=False
                    ), "author"] = id_2
                    commits_table.loc[commits_table["committer"].str.contains(
                        id_1,
                        regex=False
                    ), "committer"] = id_2
                    break
        return commits_table

    def merge(self, commit_table) -> DataFrame:
        """
        Merge developer identities using different names and e-mail addresses
        in the extracted data.

        Args:
            commit_table: Commit table with potentially diverging identities.

        Returns:
            Commit table with merged identities and identity table.
        """
        logger.info("Merging developer identities across projects...")

        identities = DataFrame(columns=["identity"])
        if len(commit_table) > 0:
            # Create an identity table as reference for identity
            # matching.
            identities = self._create_id_table(commit_table)
            # Add a second pass if some identities were missed due to
            # unfortunate order of adding identities.
            tmp_identities = DataFrame(
                {"author": identities["identity"],
                 "committer": identities["identity"]}
            )
            identities = self._create_id_table(tmp_identities)
            identities = identities.sort_values(by=["identity"])

            # Save the original names and e-mail addresses for analysis
            # purposes.
            commit_table["original_author"] = commit_table["author"]
            commit_table["original_committer"] = commit_table["committer"]

            # Unify identities in the commits table based on the
            # identity table.
            commits_merged = self._replace_ids(
                identities,
                commit_table
            )
            return commits_merged, identities
        else:
            return commit_table, identities