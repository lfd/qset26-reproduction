#!/usr/bin/env python3

import os
os.defpath = os.environ["PATH"]

import argparse
import logging
import sys

from repo_analysis.commands.analyse import AnalyseCmd
from repo_analysis.commands.extract import ExtractCmd

logger = logging.getLogger(__name__)

def setup_parser():
    """
    Set up the command line argument parser with subcommands for each analysis
    step.
    """
    parser = argparse.ArgumentParser(
        prog="repo-analysis",
        description="Analyses git repositories",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="count",
        default=0,
        help="increase verbosity"
    )

    subparsers = parser.add_subparsers(
        help="sub command help",
        dest="cmd",
        required=True
    )
    ExtractCmd.setup_parser(
        subparsers.add_parser(
            "extract",
            help="Extract the git history from the given repository"
        )
    )
    AnalyseCmd.setup_parser(
        subparsers.add_parser(
            "analyse",
            help="Aggregate and analyse the extracted data"
        )
    )

    return parser


def main():
    parser = setup_parser()
    args = parser.parse_args()

    level = logging.WARNING
    if args.verbose == 1:
        level = logging.INFO
    elif args.verbose == 2:
        level = logging.DEBUG

    logging.basicConfig(level=level)

    try:
        if args.cmd == "extract":
            ExtractCmd.run(args)
        if args.cmd == "analyse":
            AnalyseCmd.run(args)
    except Exception as e:
        logger.error(e)
        sys.exit(-1)


if __name__ == "__main__":
    main()
