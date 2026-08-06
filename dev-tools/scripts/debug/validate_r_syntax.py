#!/usr/bin/env python3
import os
import sys

def check_file(path):
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        content = f.read()

    stack = []
    in_single_quote = False
    in_double_quote = False
    in_backtick = False

    lines = content.splitlines()
    for line_idx, line in enumerate(lines, 1):
        escaped = False
        col_idx = 0
        while col_idx < len(line):
            char = line[col_idx]

            if escaped:
                escaped = False
                col_idx += 1
                continue

            if char == '\\':
                if in_single_quote or in_double_quote or in_backtick:
                    escaped = True
                col_idx += 1
                continue

            if char == '"':
                if not in_single_quote and not in_backtick:
                    in_double_quote = not in_double_quote
                col_idx += 1
                continue

            if char == "'":
                if not in_double_quote and not in_backtick:
                    in_single_quote = not in_single_quote
                col_idx += 1
                continue

            if char == "`":
                if not in_single_quote and not in_double_quote:
                    in_backtick = not in_backtick
                col_idx += 1
                continue

            if in_single_quote or in_double_quote or in_backtick:
                col_idx += 1
                continue

            if char == '#':
                # Comment starts, remainder of line is ignored
                break

            if char in '([{':
                stack.append((char, line_idx, col_idx + 1))
            elif char in ')]}':
                if not stack:
                    return f"Unmatched closing '{char}' at line {line_idx}, column {col_idx + 1}"
                opening, op_line, op_col = stack.pop()
                if (char == ')' and opening != '(') or \
                   (char == ']' and opening != '[') or \
                   (char == '}' and opening != '{'):
                    return f"Mismatched closing '{char}' at line {line_idx}, col {col_idx + 1} (expected matching for '{opening}' from line {op_line}, col {op_col})"

            col_idx += 1

    if in_double_quote:
        return "Unclosed double quote (\") at end of file"
    if in_single_quote:
        return "Unclosed single quote (') at end of file"
    if in_backtick:
        return "Unclosed backtick (`) at end of file"

    if stack:
        opening, op_line, op_col = stack[-1]
        return f"Unmatched opening '{opening}' at line {op_line}, column {op_col} (not closed by end of file)"
    return None

def main():
    target_dirs = ['R', 'inst/shiny']
    has_error = False
    checked_count = 0

    for target in target_dirs:
        if not os.path.exists(target):
            continue
        for root, _, files in os.walk(target):
            for file in files:
                if file.endswith('.R') or file.endswith('.r'):
                    full_path = os.path.join(root, file)
                    err = check_file(full_path)
                    checked_count += 1
                    if err:
                        print(f"❌ ERROR in {full_path}: {err}")
                        has_error = True
                    else:
                        # Print periodically or verbose if you want
                        pass

    print(f"Checked {checked_count} R files.")
    if has_error:
        sys.exit(1)
    else:
        print("✅ All checked R files have balanced brackets/parentheses and closed quotes.")
        sys.exit(0)

if __name__ == '__main__':
    main()
