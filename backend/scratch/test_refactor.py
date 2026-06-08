import ast

source_code = """import datetime

def my_func():
    cust_res = db.table("customers").select("id").eq("is_archived", False).execute()
    res = db.table("shops").insert({
        "name": "Azad"
    }).execute()
    return cust_res
"""

lines = source_code.splitlines(keepends=True)

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

tree = ast.parse(source_code)
matches = []

class ExecuteVisitor(ast.NodeVisitor):
    def visit_Call(self, node):
        if isinstance(node.func, ast.Attribute) and node.func.attr == "execute":
            matches.append(node)
        self.generic_visit(node)

ExecuteVisitor().visit(tree)
matches.sort(key=lambda n: (n.lineno, n.col_offset), reverse=True)

for node in matches:
    builder_text = get_span_text(lines, node.func.value)
    replace_span(lines, node, f"safe_execute({builder_text})")

new_code = "".join(lines)
print("--- Resulting Code ---")
print(new_code)
