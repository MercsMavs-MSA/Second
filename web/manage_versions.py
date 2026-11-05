#!/usr/bin/env python3
import argparse
import json
import os
import shutil
import sys
from pathlib import Path

try:
    import jinja2
except ImportError:
    jinja2 = None


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
    parser = argparse.ArgumentParser(description="Manage web deployment versions and generate Hugo Markdown using Jinja2 template.")
    parser.add_argument("--deploy-dir", required=True, help="Path to deploy/app directory")
    parser.add_argument("--docs-content-dir", help="Path to docs/content/app directory", default=None)
    parser.add_argument("--version", help="Version identifier (tag name or commit hash)", default=None)
    parser.add_argument("--type", choices=["tag", "commit"], help="Version type ('tag' or 'commit')", default=None)
    parser.add_argument("--template", help="Path to Jinja2 Markdown template file", default=None)
    args = parser.parse_args()

    deploy_dir = Path(args.deploy_dir).resolve()
    deploy_dir.mkdir(parents=True, exist_ok=True)

    docs_content_dir = Path(args.docs_content_dir).resolve() if args.docs_content_dir else Path(__file__).parent.parent / "docs" / "content" / "app"
    docs_content_dir.mkdir(parents=True, exist_ok=True)

    template_path = Path(args.template).resolve() if args.template else Path(__file__).parent / "version_manager_template.md"

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

    if args.type == "commit" and args.version:
        latest_commit = args.version
    elif args.type == "tag" and args.version:
        if args.version not in tags:
            tags.append(args.version)

    # Detect existing version subdirectories on disk
    for item in deploy_dir.iterdir():
        if item.is_dir() and (item / "index.html").exists():
            if item.name == "latest":
                continue
            if item.name in tags:
                continue
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

    # Generate Markdown page in docs/content/app/_index.md using Jinja2 template
    generate_markdown(docs_content_dir / "_index.md", template_path, latest_commit, tags)
    print(f"Updated version management: latest_commit={latest_commit}, tags={tags}")


def generate_markdown(output_path, template_path, latest_commit, tags):
    if not template_path.exists():
        raise FileNotFoundError(f"Template file not found at: {template_path}")

    with open(template_path, "r", encoding="utf-8") as f:
        template_str = f.read()

    if jinja2 is not None:
        env = jinja2.Environment(
            variable_start_string="[[",
            variable_end_string="]]",
            block_start_string="[%",
            block_end_string="%]"
        )
        template = env.from_string(template_str)
        rendered_md = template.render(latest_commit=latest_commit, tags=tags)
    else:
        raise ImportError("jinja2 package is required to render the Markdown template. Install with 'pip install jinja2'")

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(rendered_md)


if __name__ == "__main__":
    main()
