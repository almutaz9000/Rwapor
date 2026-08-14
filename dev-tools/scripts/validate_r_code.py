#!/usr/bin/env python3
import os
import sys

def validate_r_file(filepath):
    with open(filepath, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    # Check for getFromNamespace outside comments
    # To be extremely robust, let us parse and look for getFromNamespace

    in_comment = False
    in_string = False
    string_char = None
    escape_next = False

    stack = []

    line_num = 1
    col_num = 0

    get_from_namespace_instances = []

    i = 0
    n = len(content)
    while i < n:
        char = content[i]
        col_num += 1

        if char == "\n":
            line_num += 1
            col_num = 0
            if in_comment:
                in_comment = False
            i += 1
            continue

        if in_comment:
            i += 1
            continue

        if in_string:
            if escape_next:
                escape_next = False
            elif char == "\\":
                escape_next = True
            elif char == string_char:
                in_string = False
                string_char = None
            i += 1
            continue

        # Not in comment, not in string
        if char == "#":
            in_comment = True
            i += 1
            continue

        if char in ('"', "'", "`"):
            in_string = True
            string_char = char
            escape_next = False
            i += 1
            continue

        if char in ("(", "[", "{"):
            stack.append((char, line_num, col_num))
            i += 1
            continue

        if char in (")", "]", "}"):
            if not stack:
                return False, f"Unexpected closing '{char}' at line {line_num}, col {col_num}"
            top_char, top_line, top_col = stack.pop()
            # check matching
            matches = {"(": ")", "[": "]", "{": "}"}
            if matches[top_char] != char:
                return False, f"Mismatched bracket: opened '{top_char}' at line {top_line}, col {top_col} but closed with '{char}' at line {line_num}, col {col_num}"
            i += 1
            continue

        # Check for getFromNamespace
        if content[i:i+16] == "getFromNamespace":
            # Let's check if it is part of a longer identifier
            prev_char = content[i-1] if i > 0 else ""
            next_char = content[i+16] if i+16 < n else ""
            if not (prev_char.isalnum() or prev_char == "." or prev_char == "_") and not (next_char.isalnum() or next_char == "." or next_char == "_"):
                get_from_namespace_instances.append((line_num, col_num))

        i += 1

    if in_string:
        return False, f"Unclosed string/identifier starting with {string_char} at the end of the file"

    if stack:
        top_char, top_line, top_col = stack[-1]
        return False, f"Unclosed bracket '{top_char}' opened at line {top_line}, col {top_col}"

    if get_from_namespace_instances:
        locations = ", ".join(f"line {l}, col {c}" for l, c in get_from_namespace_instances)
        return False, f"Forbidden 'getFromNamespace' function call found at: {locations}"

    return True, "OK"

def main():
    target_dirs = ["R", "tests", "inst/shiny"]
    has_errors = False
    checked_count = 0

    print("=== Starting Static Code Validation ===")
    for d in target_dirs:
        if not os.path.exists(d):
            continue
        for root, dirs, files in os.walk(d):
            for f in files:
                if f.endswith(".R"):
                    filepath = os.path.join(root, f)
                    checked_count += 1
                    success, msg = validate_r_file(filepath)
                    if not success:
                        print(f"❌ ERROR in {filepath}: {msg}")
                        has_errors = True
                    else:
                        # Print only for debugging if verbose, but let's keep it clean
                        pass

    print(f"Checked {checked_count} R files.")
    if has_errors:
        print("❌ Static validation FAILED!")
        sys.exit(1)
    else:
        print("✅ Static validation PASSED successfully!")
        sys.exit(0)

if __name__ == "__main__":
    main()
