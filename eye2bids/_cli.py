from __future__ import annotations

import sys
import tempfile
from collections.abc import Sequence
from pathlib import Path

import yaml

from eye2bids._parser import global_parser
from eye2bids.edf2bids import edf2bids
from eye2bids.logger import eye2bids_logger
from eye2bids.scully.metadata import (
    OVERRIDE_FLAGS,
    add_metadata_arguments,
    build_metadata,
)

e2b_log = eye2bids_logger()


def set_verbosity(verbosity: int | list[int]) -> None:
    """Set verbosity level."""
    if isinstance(verbosity, list):
        verbosity = verbosity[0]
    verbosity_map = {0: "ERROR", 1: "WARNING", 2: "INFO", 3: "DEBUG"}
    e2b_log.setLevel(verbosity_map[verbosity])


def cli(argv: Sequence[str] = sys.argv) -> None:
    """Entry point."""
    parser = global_parser()
    parser.add_argument(
        "--input_type",
        type=str,
        help="""
        Input type if it cannot be determined from input_file.
        """,
        required=False,
        default=None,
    )

    add_metadata_arguments(parser)
    parser.allow_abbrev = False  # a mistyped flag is an error, not a guess

    args = parser.parse_args(argv[1:])

    input_file = Path(args.input_file).absolute()

    output_dir = Path(args.output_dir).resolve()

    set_verbosity(args.verbosity)

    # Metadata: the given file (or the bundled Scully file), then the
    # command-line overrides and --task, passed to edf2bids as one file.
    metadata = build_metadata(args)
    source = args.metadata_file or "bundled Scully MEG metadata"
    overrides = [
        f for flag, f in OVERRIDE_FLAGS.items() if getattr(args, flag) is not None
    ]
    e2b_log.info(
        f"metadata: {source}; TaskName: {args.task}"
        + (f"; overridden: {', '.join(overrides)}" if overrides else "")
    )

    with tempfile.TemporaryDirectory() as tmp:
        metadata_file = Path(tmp) / "metadata.yml"
        metadata_file.write_text(yaml.safe_dump(metadata, sort_keys=False))
        edf2bids(
            input_file=input_file,
            metadata_file=metadata_file,
            output_dir=output_dir,
            interactive=args.interactive,
            force=args.force,
        )
