import logging

logger = logging.getLogger(__name__)


class GitInput:
    """
    Provides options for Git repository input.
    """

    @classmethod
    def parser_add_git_input_args(cls, parser):
        parser.add_argument(
            "repo_path",
            type=str,
            help="Local path to the Git repositories to analyse"
        )
        parser.add_argument(
            "extract_path",
            type=str,
            help="Path to store the extracted data for the analysis"
        )
        parser.add_argument(
            "conf_path",
            type=str,
            help="Path to the configuration file"
        )


class AnalysisInput:
    """
    Provides options for analysis input.
    """

    @classmethod
    def parser_add_analysis_input_args(cls, parser):
        parser.add_argument(
            "extract_path",
            type=str,
            help="Path to the extracted data for the analysis"
        )
        parser.add_argument(
            "analysis_path",
            type=str,
            help="Path to the analysis results"
        )