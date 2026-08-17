#!/usr/bin/env python3
"""
Static R code validator for the Rwapor repository.
Checks R files for:
1. Balanced brackets, braces, and parentheses.
2. Unclosed string literals/quotes.
3. Violation of repository namespace policy (e.g. usage of getFromNamespace).
"""

import sys
import re
from pathlib import Path

def check_file_syntax(filepath):
    errors = []
    content = filepath.read_text(encoding="utf-8")

    # Check 1: Forbidden getFromNamespace calls
    if "getFromNamespace" in content:
        # Find line numbers
        for i, line in enumerate(content.splitlines(), start=1):
            if "getFromNamespace" in line and not line.strip().startswith("#"):
                errors.append(f"Line {i}: Usage of 'getFromNamespace' is forbidden by package coding standards.")

    # Check 2: Balanced delimiters and quotes parsing line by line / character by character
    stack = []
    matching = {')': '(', ']': '[', '}': '{'}

    in_single_quote = False
    in_double_quote = False
    in_backtick = False
    in_comment = False
    escaped = False

    for i, char in enumerate(content):
        # Calculate line and col for error reporting
        line_num = content[:i].count('\n') + 1

        if escaped:
            escaped = False
            continue

        if char == '\\' and (in_single_quote or in_double_quote):
            escaped = True
            continue

        if in_comment:
            if char == '\n':
                in_comment = False
            continue

        if in_single_quote:
            if char == "'":
                in_single_quote = False
            continue

        if in_double_quote:
            if char == '"':
                in_double_quote = False
            continue

        if in_backtick:
            if char == '`':
                in_backtick = False
            continue

        # Outside strings and comments
        if char == '#':
            in_comment = True
            continue

        if char == "'":
            in_single_quote = True
            continue

        if char == '"':
            in_double_quote = True
            continue

        if char == '`':
            in_backtick = True
            continue

        if char in '([{':
            stack.append((char, line_num))
        elif char in ')]}':
            if not stack:
                errors.append(f"Line {line_num}: Unmatched closing character '{char}'.")
            else:
                top_char, top_line = stack.pop()
                if top_char != matching[char]:
                    errors.append(f"Line {line_num}: Closing '{char}' does not match opening '{top_char}' from line {top_line}.")

    if in_single_quote:
        errors.append("Unclosed single quote (').")
    if in_double_quote:
        errors.append('Unclosed double quote (").')
    if in_backtick:
        errors.append("Unclosed backtick (`).")

    while stack:
        top_char, top_line = stack.pop()
        errors.append(f"Line {top_line}: Unclosed '{top_char}'.")

    return errors

def main():
    repo_root = Path(__file__).resolve().parent.parent.parent
    target_dirs = [repo_root / "R", repo_root / "inst" / "shiny", repo_root / "tests"]

    r_files = []
    for d in target_dirs:
        if d.exists():
            r_files.extend(d.rglob("*.R"))

    r_files = sorted(set(r_files))

    print(f"Validating {len(r_files)} R source files across R/, inst/shiny/, and tests/...")

    total_errors = 0
    failed_files = 0

    for r_file in r_files:
        rel_path = r_file.relative_to(repo_root)
        errors = check_file_syntax(r_file)
        if errors:
            failed_files += 1
            total_errors += len(errors)
            print(f"\n❌ {rel_path}:")
            for err in errors:
                print(f"  - {err}")
        else:
            pass

    if total_errors == 0:
        print(f"\n✅ All {len(r_files)} R files passed static validation successfully!")
        sys.exit(0)
    else:
        print(f"\n❌ Static validation failed: {total_errors} issue(s) across {failed_files} file(s).")
        sys.exit(1)

if __name__ == "__main__":
    main()
