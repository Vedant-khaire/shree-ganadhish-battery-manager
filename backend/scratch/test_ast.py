import ast

source_code = """
cust_res = db.table("customers").select("id").eq("is_archived", False).execute()
res = db.table("shops").insert({
    "name": "Azad"
}).execute()
"""

class ExecuteVisitor(ast.NodeVisitor):
    def __init__(self):
        self.matches = []

    def visit_Call(self, node):
        if isinstance(node.func, ast.Attribute) and node.func.attr == "execute":
            # We found a .execute() call
            self.matches.append(node)
        self.generic_visit(node)

tree = ast.parse(source_code)
visitor = ExecuteVisitor()
visitor.visit(tree)

print(f"Found {len(visitor.matches)} calls.")
for m in visitor.matches:
    print(f"Call: lineno={m.lineno}, col={m.col_offset}, end_lineno={m.end_lineno}, end_col={m.end_col_offset}")
    print(f"Builder: lineno={m.func.value.lineno}, col={m.func.value.col_offset}, end_lineno={m.func.value.end_lineno}, end_col={m.func.value.end_col_offset}")
