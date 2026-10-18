"""Prints the release notes of a version, from its section in CHANGELOG.md.

The text before the section's first list heading (a summary) shows as it is, and each list
(Added, Changed, Fixed...) is folded under its name and number of entries, so the builds
stay in sight below. Wrapped lines are joined: GitHub shows every line break in release
notes. Exits with 1 when the changelog has no section for the version. Keep @ out of
the changelog outside `code`: GitHub takes @2x for a user and lists them as a contributor.

Usage: release_notes.py <version> <changelog> <owner/repository>
"""

import sys


def read_section(path: str, version: str) -> list[str] | None:
    lines = open(path, encoding="utf-8").read().splitlines()
    try:
        start = lines.index("## " + version) + 1
    except ValueError:
        return None
    end = next((i for i in range(start, len(lines)) if lines[i].startswith("## ")), len(lines))
    return lines[start:end]


def join_wrapped(lines: list[str]) -> list[str]:
    """One line per entry, paragraph and heading, with blank lines kept between them"""
    joined: list[str] = []
    for line in lines:
        continues = line.strip() and joined and joined[-1] and not joined[-1].startswith("#")
        if continues and not line.startswith(("- ", "#")):
            joined[-1] += " " + line.strip()
        else:
            joined.append(line.rstrip())
    return joined


def fold(lines: list[str]) -> str:
    parts: list[str] = []
    heading = ""
    entries: list[str] = []

    def close() -> None:
        if heading:
            count = sum(1 for line in entries if line.startswith("- "))
            body = "\n".join(entries).strip()
            parts.append(
                f"<details><summary><b>{heading}</b> ({count})</summary>\n\n{body}\n\n</details>\n"
            )

    for line in lines:
        if line.startswith("### "):
            close()
            heading = line[4:].strip()
            entries = []
        elif heading:
            entries.append(line)
        else:
            parts.append(line)
    close()
    return "\n".join(parts).strip()


def main() -> int:
    version, changelog, repository = sys.argv[1:4]
    section = read_section(changelog, version)
    if section is None or not any(line.strip() for line in section):
        return 1
    print(fold(join_wrapped(section)))
    print()
    print(
        f"The builds aren't signed: [Download](https://github.com/{repository}#download) says"
        " how to open them the first time on Windows and macOS."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
