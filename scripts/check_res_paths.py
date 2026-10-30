import os
import re

res_pattern = re.compile(r'res://([a-zA-Z0-9_\-\./]+)')
errors = []
checked = 0

for root, dirs, files in os.walk('.'):
    if '.godot' in root or '.git' in root:
        continue
    for file in files:
        if file.endswith(('.gd', '.tscn', '.tres', '.godot')):
            file_path = os.path.join(root, file)
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            for match in res_pattern.finditer(content):
                rel_path = match.group(1).rstrip('"\',; )')
                if not rel_path or '.' not in rel_path:
                    continue
                checked += 1
                normalized = os.path.normpath(rel_path)
                if not os.path.exists(normalized):
                    errors.append((file_path, match.group(0), normalized))

print(f"Checked {checked} res:// references across all project files.")
if errors:
    print(f"Found {len(errors)} missing references:")
    for src, raw, norm in errors:
        print(f"  In {src}: {raw} -> '{norm}' does not exist!")
else:
    print("ALL res:// REFERENCES ARE 100% VALID AND EXIST ON DISK!")
