from burl.parser import parse_args


def main() -> None:
    parser, args = parse_args()
    if "cls" in args:
        try:
            args.cls(args).run()
        except (ValueError, OSError) as error:
            parser.exit(1, f"burl: {error}\n")
    else:
        parser.print_help()
