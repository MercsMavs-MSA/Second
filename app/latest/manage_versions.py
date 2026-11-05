#!/usr/bin/env python3
import argparse
import json
import os
import shutil
import sys
from pathlib import Path


def sort_tags(tags_list):
    def version_key(v):
        cleaned = v.lstrip("vV")
        parts = []
        for part in cleaned.split("."):
            if part.isdigit():
                parts.append(int(part))
            else:
                parts.append(part)
        return parts

    try:
        return sorted(tags_list, key=version_key, reverse=True)
    except Exception:
        return sorted(tags_list, reverse=True)


def main():
    parser = argparse.ArgumentParser(description="Manage web deployment versions and generate HTML UI.")
    parser.add_argument("--deploy-dir", required=True, help="Path to deploy/app directory")
    parser.add_argument("--version", required=True, help="Version identifier (tag name or commit hash)")
    parser.add_argument("--type", choices=["tag", "commit"], required=True, help="Version type ('tag' or 'commit')")
    args = parser.parse_args()

    deploy_dir = Path(args.deploy_dir).resolve()
    deploy_dir.mkdir(parents=True, exist_ok=True)

    versions_file = deploy_dir / "versions.json"

    # Load existing versions metadata if available
    data = {}
    if versions_file.exists():
        try:
            with open(versions_file, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception as e:
            print(f"Warning: Failed to read existing versions.json: {e}")

    latest_commit = data.get("latest_commit")
    tags = data.get("tags", [])
    if not isinstance(tags, list):
        tags = []

    if args.type == "commit":
        latest_commit = args.version
    elif args.type == "tag":
        if args.version not in tags:
            tags.append(args.version)

    # Detect existing version subdirectories on disk
    for item in deploy_dir.iterdir():
        if item.is_dir() and (item / "index.html").exists():
            if item.name == "latest":
                continue
            if item.name in tags:
                continue
            # Clean up legacy commit hash directories if present
            if len(item.name) == 7 or len(item.name) == 40:
                print(f"Removing legacy commit directory: {item.name}")
                shutil.rmtree(item, ignore_errors=True)
            else:
                tags.append(item.name)

    tags = sort_tags(list(set(tags)))

    # Save metadata
    versions_data = {
        "latest_commit": latest_commit,
        "tags": tags
    }
    with open(versions_file, "w", encoding="utf-8") as f:
        json.dump(versions_data, f, indent=2)

    # Generate unstyled Version Manager HTML UI
    generate_html(deploy_dir / "index.html", latest_commit, tags)
    print(f"Updated version management: latest_commit={latest_commit}, tags={tags}")


def generate_html(output_path, latest_commit, tags):
    if latest_commit:
        commit_html = f'<ul>\n    <li><a href="./latest/">Latest Commit ({latest_commit})</a></li>\n  </ul>'
    else:
        commit_html = "<p>No commit build available.</p>"

    if tags:
        tags_list_items = "\n".join([f'    <li><a href="./{t}/">{t}</a></li>' for t in tags])
        tags_html = f'<ul>\n{tags_list_items}\n  </ul>'
    else:
        tags_html = "<p>No tagged versions available.</p>"

    options_html = []
    if latest_commit:
        options_html.append(f'<option value="./latest/">Latest Commit ({latest_commit})</option>')
    for t in tags:
        options_html.append(f'<option value="./{t}/">Tag {t}</option>')

    options_str = "\n      ".join(options_html) if options_html else '<option value="">No versions available</option>'

    html_content = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Web Deployment Version Manager</title>
</head>
<body>
  <h1>Web Deployment Version Manager</h1>
  <p>Select a version of the web application to launch:</p>

  <h2>Latest Commit Version</h2>
  {commit_html}

  <h2>Tagged Versions</h2>
  {tags_html}

  <h2>Version Switcher</h2>
  <form id="version-form">
    <label for="version-select">Choose a version:</label>
    <select id="version-select">
      {options_str}
    </select>
    <button type="submit">Go to Version</button>
  </form>

  <script>
    document.getElementById('version-form').addEventListener('submit', function(e) {{
      e.preventDefault();
      var selected = document.getElementById('version-select').value;
      if (selected) {{
        window.location.href = selected;
      }}
    }});
  </script>
</body>
</html>
"""

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(html_content)


if __name__ == "__main__":
    main()
