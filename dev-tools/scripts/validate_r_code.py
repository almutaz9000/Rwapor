import os
import sys

def check_r_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    errors = []

    # Check for getFromNamespace
    if 'getFromNamespace' in content:
        errors.append("Found getFromNamespace")

    # Check balanced brackets/braces/parentheses
    stack = []
    in_string = False
    string_char = ''
    in_comment = False

    lines = content.split('\n')
    for line_no, line in enumerate(lines, 1):
        in_comment = False
        i = 0
        while i < len(line):
            char = line[i]
            if in_comment:
                break
            if in_string:
                if char == '\\':
                    i += 1 # skip escaped char
                elif char == string_char:
                    in_string = False
            else:
                if char == '#':
                    in_comment = True
                elif char in ['"', "'", '`']:
                    in_string = True
                    string_char = char
                elif char in '({[':
                    stack.append((char, line_no))
                elif char in ')}]':
                    if not stack:
                        errors.append(f"Unmatched closing '{char}' at line {line_no}")
                    else:
                        top, top_line = stack.pop()
                        expected = {'(': ')', '{': '}', '[': ']'}[top]
                        if char != expected:
                            errors.append(f"Mismatched bracket '{char}' at line {line_no}, expected '{expected}' (opened at line {top_line})")
            i += 1

    if stack:
        for char, line_no in stack:
            errors.append(f"Unclosed opening '{char}' at line {line_no}")

    return errors

def main():
    has_errors = False
    for root, dirs, files in os.walk('.'):
        if '.git' in root:
            continue
        for file in files:
            if file.endswith('.R') or file.endswith('.r'):
                filepath = os.path.join(root, file)
                errors = check_r_file(filepath)
                if errors:
                    print(f"Errors in {filepath}:")
                    for err in errors:
                        print(f"  - {err}")
                    has_errors = True

    if not has_errors:
        print("All R files passed syntax validation and checks!")
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == '__main__':
    main()
