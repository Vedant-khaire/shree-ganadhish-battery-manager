import ast
import os

files_to_refactor = [
    "app/services/dashboard.py",
    "app/services/shop.py",
    "app/services/reminder.py",
    "app/services/customer.py",
    "app/services/stock.py"
]

def get_span_text(lines, node):
    start_line = node.lineno - 1
    start_col = node.col_offset
    end_line = node.end_lineno - 1
    end_col = node.end_col_offset
    
    if start_line == end_line:
        return lines[start_line][start_col:end_col]
    
    result = []
    result.append(lines[start_line][start_col:])
    for r in range(start_line + 1, end_line):
        result.append(lines[r])
    result.append(lines[end_line][:end_col])
    return "".join(result)

def replace_span(lines, node, replacement):
    start_line = node.lineno - 1
    start_col = node.col_offset
    end_line = node.end_lineno - 1
    end_col = node.end_col_offset
    
    if start_line == end_line:
        lines[start_line] = lines[start_line][:start_col] + replacement + lines[start_line][end_col:]
    else:
        lines[start_line] = lines[start_line][:start_col] + replacement
        for r in range(start_line + 1, end_line):
            lines[r] = ""
        lines[end_line] = lines[end_line][end_col:]

def refactor_file(filepath):
    print(f"Checking {filepath}...")
    if not os.path.exists(filepath):
        print(f"File {filepath} not found!")
        return

    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    lines = content.splitlines(keepends=True)
    try:
        tree = ast.parse(content)
    except Exception as e:
        print(f"Failed to parse AST for {filepath}: {e}")
        return

    matches = []
    class ExecuteVisitor(ast.NodeVisitor):
        def visit_Call(self, node):
            if isinstance(node.func, ast.Attribute) and node.func.attr == "execute":
                matches.append(node)
            self.generic_visit(node)

    ExecuteVisitor().visit(tree)
    
    if not matches:
        print(f"No .execute() calls found in {filepath}")
        return

    print(f"Found {len(matches)} .execute() calls in {filepath}. Refactoring...")
    matches.sort(key=lambda n: (n.lineno, n.col_offset), reverse=True)

    for node in matches:
        builder_text = get_span_text(lines, node.func.value)
        replace_span(lines, node, f"safe_execute({builder_text})")

    new_content = "".join(lines)
    
    # Add import if not present
    if "safe_execute" not in new_content:
        # Find where to add import statement. We can prepend it, or add it after other imports.
        # Prepending is safe.
        new_content = "from app.database import safe_execute\n" + new_content

    with open(filepath, "w", encoding="utf-8") as f:
        f.write(new_content)
    print(f"Finished refactoring {filepath}.")

if __name__ == "__main__":
    for filepath in files_to_refactor:
        refactor_file(filepath)
