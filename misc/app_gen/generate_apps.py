#!/usr/bin/env python3
"""App generation scaffold for OpenComposer apps."""

import argparse
import base64
import json
import os
import re
import subprocess
import tempfile
import traceback
import urllib.error
import urllib.request
from pathlib import Path

import yaml

DEFAULT_CONFIG_PATH = "misc/app_gen/config.yml"
AI_MARKER = "# AI generated"

CATEGORY_MAP = {
    "biology": "Bioinformatics",
    "chemistry": "Chemistry",
    "engineering": "Engineering",
    "language": "Language",
    "machine_learning": "Machine Learning",
    "earth_science": "Earth Science",
    "mathematics": "Mathematics",
    "visualisation": "Visualization",
    "workflow_management": "Workflow",
    "data_analytics": "Data Analytics",
    "climate_science": "Climate Science",
    "physics": "Physics",
    "social_science": "Social Science",
    "gpu": "GPU",
}


def normalize_key(value: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "_", value.lower())
    return re.sub(r"_+", "_", s).strip("_")


class AppGenerator:
    def __init__(self, root: Path, options: dict):
        self.root = root
        self.options = options

        config_path = root / (options.get("config") or DEFAULT_CONFIG_PATH)
        self.config = yaml.safe_load(config_path.read_text()) if config_path.exists() else {}

        paths = self.config.get("paths") or {}
        self.apps_dir = root / paths.get("apps_dir", "apps")

    def run(self):
        print("Fetching modules list...", flush=True)
        module_data = json.loads(self._fetch("modules_list_url"))
        print("Fetching support docs index...", flush=True)
        support_index = json.loads(self._fetch("support_docs_index_url"))

        support_doc_map = {
            normalize_key(row["name"][:-3]): row["name"]
            for row in support_index
            if row.get("type") == "file" and str(row.get("name", "")).endswith(".md")
        }

        targets = self._target_apps(module_data)
        total = len(targets)
        print(f"Targets: {total} app(s)\n", flush=True)
        # TODO: parallelize with ThreadPoolExecutor for bulk runs
        results = [self._process_app(app, module_data, support_doc_map, idx + 1, total)
                   for idx, app in enumerate(targets)]
        self._print_summary(results)

    def _process_app(self, app_name: str, module_data: dict, support_doc_map: dict,
                     idx: int = 1, total: int = 1) -> dict:
        prefix = f"[{idx}/{total}] {app_name}"
        try:
            print(f"{prefix}: starting...", flush=True)
            app_dir = self.apps_dir / app_name
            module_name, module_entry = self._resolve_module_entry(app_name, module_data)
            support_doc_name = support_doc_map.get(normalize_key(app_name))

            if support_doc_name:
                print(f"{prefix}: fetching support doc ({support_doc_name})...", flush=True)
                base_url = self._source_url("support_docs_raw_base_url")
                support_md = self._fetch_url(f"{base_url}/{support_doc_name}")
            else:
                support_md = None

            # Fall back to web search when the support doc is absent or has no code examples
            # (NeSI docs use both fenced ``` blocks and inline ` backticks for commands)
            if support_md is None or "`" not in support_md:
                homepage = (module_entry.get("homepage", "") if module_entry else "").strip()
                if homepage.lower() in ("", "(none)", "none"):
                    homepage = ""
                print(f"{prefix}: no support doc with code examples — fetching web docs...", flush=True)
                web_docs = self._fetch_web_docs(app_name, homepage)
                if web_docs:
                    support_md = (support_md + "\n\n" if support_md else "") + web_docs

            mod_var = f"{normalize_key(app_name)}_module"
            if support_md:
                print(f"{prefix}: calling Claude for form...", flush=True)
            claude_result = self._claude_form(app_name, mod_var, support_md) if support_md else {}
            profile = claude_result.get("profile", "basic")

            manifest_text = _yaml_to_text(self._build_manifest(app_name, module_entry, support_md))
            form_text = self._build_form_erb(app_name, profile, claude_result)

            manifest_result = self._write_file(app_dir / "manifest.yml", manifest_text)
            form_result = self._write_file(app_dir / "form.yml.erb", form_text)
            print(f"{prefix}: generating icon...", flush=True)
            icon_result = self._process_icon(app_dir,
                                             self._build_icon_prompt(app_name, module_entry, support_md))

            self._print_preview(app_name, module_name, support_doc_name, profile,
                                manifest_text, form_text, manifest_result, form_result, icon_result)

            return {
                "app": app_name,
                "module_name": module_name,
                "support_doc": support_doc_name,
                "profile": profile,
                "files": {"manifest": manifest_result, "form": form_result, "icon": icon_result},
            }
        except Exception as exc:
            print(f"{prefix}: ERROR — {exc}", flush=True)
            entry = {"app": app_name, "error": str(exc)}
            if self.options.get("verbose"):
                entry["traceback"] = traceback.format_exc()
            return entry

    def _write_file(self, path: Path, new_text: str) -> dict:
        existing = path.read_text(encoding="utf-8") if path.exists() else None
        rel = str(path.relative_to(self.root))

        if existing == new_text:
            return _result("unchanged", "no diff")
        if existing is not None and AI_MARKER not in existing.splitlines()[0] and not self.options.get("force"):
            return _result("skipped", "human-edited (AI marker absent); use --force to overwrite")
        if not self.options["write"]:
            return _result("preview", f"would {'update' if existing else 'create'} {rel}")

        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(new_text)
        return _result("updated" if existing else "created", rel)

    def _process_icon(self, app_dir: Path, icon_prompt: str) -> dict:
        gen = self.config.get("generation", {})
        icon_fmt = gen.get("icon_format", "png")
        icon_path = app_dir / f"icon.{icon_fmt}"

        if icon_path.exists() and not self.options.get("force_icon"):
            return _result("kept", "icon already exists; use --force-icon to regenerate")
        if not self.options["write"]:
            return _result("preview", f"would generate {icon_path.relative_to(self.root)}")

        app_dir.mkdir(parents=True, exist_ok=True)
        json_response = self._run_claude(icon_prompt)
        icon_b64 = json_response.get("icon_png_base64", "").strip()
        if not icon_b64:
            raise ValueError("Claude response missing icon_png_base64")
        icon_path.write_bytes(base64.b64decode(icon_b64))
        return _result("updated", "icon generated via Claude")

    def _claude_form(self, app_name: str, mod_var: str, support_md: str) -> dict:
        prompt_template = (Path(__file__).parent / "prompt_form.txt").read_text()
        prompt = (
            prompt_template
            .replace("<<<APP_NAME>>>", app_name)
            .replace("<<<SUPPORT_MD>>>", support_md)
        )
        result = self._run_claude(prompt)
        profile = result.get("profile", "basic")
        if profile not in ("basic", "gpu"):
            profile = "basic"
        erb_logic = result.get("erb_logic", "").strip()
        self._validate_erb_logic(erb_logic)
        return {
            "profile": profile,
            "form_fields": result.get("form_fields") or [],
            "erb_logic": erb_logic,
        }

    def _validate_erb_logic(self, erb_logic: str) -> None:
        if not erb_logic:
            return
        with tempfile.NamedTemporaryFile(suffix=".rb", mode="w", delete=False) as f:
            f.write(erb_logic)
            tmp_path = f.name
        try:
            result = subprocess.run(["ruby", "-c", tmp_path], capture_output=True, text=True)
            if result.returncode != 0:
                raise ValueError(f"erb_logic Ruby syntax error:\n{result.stderr.strip()}")
        except FileNotFoundError:
            pass  # ruby not installed — skip syntax check
        finally:
            os.unlink(tmp_path)

    def _fetch_web_docs(self, app_name: str, homepage: str) -> str:
        web_cmd = self.config.get("claude", {}).get("web_search_command", "").strip()
        if not web_cmd:
            return ""
        template = (Path(__file__).parent / "prompt_web_search.txt").read_text()
        if homepage:
            homepage_section = f"The application homepage is: {homepage}\nCheck it first, then broaden your search."
        else:
            homepage_section = f'Search for: "{app_name} HPC SLURM" and "{app_name} cluster job submission"'
        prompt = (
            template
            .replace("<<<APP_NAME>>>", app_name)
            .replace("<<<HOMEPAGE_SECTION>>>", homepage_section)
        )
        try:
            print(f"  web search via Claude ({app_name})...", flush=True)
            result = self._run_claude(prompt, command=web_cmd)
            return result.get("docs", "").strip()
        except Exception:
            return ""

    def _run_claude(self, prompt: str, command=None) -> dict:
        command = (command or self.config.get("claude", {}).get("command", "")).strip()
        if not command:
            raise ValueError("Claude command is empty in config.yml")
        proc = subprocess.run(command, input=prompt, capture_output=True, text=True, shell=True)
        if proc.returncode != 0:
            raise RuntimeError(f"Claude command failed: {proc.stderr.strip()}")

        raw = proc.stdout.strip()
        try:
            outer = json.loads(raw)
            if isinstance(outer, dict) and "result" in outer:
                raw = outer["result"]
        except (json.JSONDecodeError, TypeError):
            pass

        fence_match = re.search(r"```(?:json)?\s*\n(\{.*?\})\s*\n```", raw, re.DOTALL)
        if fence_match:
            return json.loads(fence_match.group(1))

        brace_match = re.search(r"\{.*\}", raw, re.DOTALL)
        if brace_match:
            return json.loads(brace_match.group(0))

        return json.loads(raw)

    def _build_manifest(self, app_name: str, module_entry: dict, support_md) -> dict:
        gen = self.config.get("generation", {})
        domains = list(module_entry.get("domains", []) if module_entry else [])
        category = next((CATEGORY_MAP[d.lower()] for d in domains if d.lower() in CATEGORY_MAP), "Other")
        homepage = (module_entry.get("homepage", "") if module_entry else "").strip()
        if homepage.lower() in ("", "(none)", "none"):
            homepage = ""
        return {
            "name": app_name,
            "category": category,
            "description": self._extract_description(support_md, module_entry),
            "homepage": homepage,
            "icon": f"icon.{gen.get('icon_format', 'png')}",
            "hidden": gen.get("default_hidden", True),
        }

    def _build_icon_prompt(self, app_name: str, module_entry, support_md) -> str:
        gen = self.config.get("generation", {})
        dim = str(gen.get("icon_dimension", 256))
        fmt = gen.get("icon_format", "png").upper()
        description = self._extract_description(support_md, module_entry)
        domains = ", ".join(module_entry.get("domains", []) if module_entry else [])
        prompt_template = (Path(__file__).parent / "prompt_icon.txt").read_text()
        return (
            prompt_template
            .replace("<<<APP_NAME>>>", app_name)
            .replace("<<<DIM>>>", dim)
            .replace("<<<FMT>>>", fmt)
            .replace("<<<DESCRIPTION>>>", description)
            .replace("<<<DOMAINS>>>", domains)
        )

    def _extract_description(self, support_md, module_entry) -> str:
        text = (module_entry.get("description", "") if module_entry else "").strip()
        if text:
            return text
        fm = _parse_frontmatter(support_md or "")
        return (fm.get("description") or "").strip()

    def _build_form_erb(self, app_name: str, profile: str, claude_result: dict) -> str:
        base = "SlurmGPU" if profile == "gpu" else "SlurmBasic"
        mod_var = f"{normalize_key(app_name)}_module"
        extra_fields = "\n".join(_render_field_ruby(f) for f in claude_result.get("form_fields", []))
        erb_logic = claude_result.get("erb_logic", "")
        script_section = (
            f"\n{erb_logic}\n\n"
            "base['script'] = base['script'].rstrip + \"\\n\\n\" + [\n"
            "  \"module -q purge\",\n"
            f"  \"module load #{{{mod_var}}}\",\n"
            "  app_cmd\n"
            "].join(\"\\n\") + \"\\n\"\n"
        )
        return (
            "<%# AI generated %>\n"
            "<%\n"
            f"base_path = File.join(File.dirname(yml_path), '../{base}/form.yml')\n"
            "base = YAML.load_file(base_path)\n"
            "\nnew_form = {}\n"
            "base['form'].each do |k, v|\n"
            "  if k == 'time_days_hours_minutes'\n"
            f"    new_form['{mod_var}'] = {{\n"
            "      'widget' => 'module_load',\n"
            f"      'module' => \"{app_name}\",\n"
            f"      'label'  => \"{app_name} Module\"\n"
            "    }\n"
            f"{extra_fields}\n"
            "  end\n"
            "  new_form[k] = v\n"
            "end\n\n"
            "base['form'] = new_form\n"
            f"{script_section}"
            "%>\n"
            "<%= base.to_yaml -%>\n"
        )

    def _target_apps(self, module_data: dict) -> list:
        if self.options["all"]:
            apps = [p.name for p in self.apps_dir.iterdir() if p.is_dir()]
        else:
            apps = list(self.options["apps"])
        if not apps:
            raise SystemExit("No target apps. Use --app APP_NAME or --all.")
        return sorted(set(apps))

    def _resolve_module_entry(self, app_name: str, module_data: dict):
        if app_name in module_data:
            return app_name, module_data[app_name]
        norm = normalize_key(app_name)
        ci_key = next((k for k in module_data if normalize_key(k) == norm), None)
        return (ci_key, module_data[ci_key]) if ci_key else (app_name, {})

    def _fetch(self, source_key: str) -> str:
        return self._fetch_url(self._source_url(source_key))

    def _fetch_url(self, url: str) -> str:
        req = urllib.request.Request(url, headers={"User-Agent": "OpenComposer-AppGenerator"})
        try:
            with urllib.request.urlopen(req) as resp:
                return resp.read().decode("utf-8")
        except urllib.error.HTTPError as exc:
            raise RuntimeError(f"HTTP {exc.code} for {url}") from exc

    def _source_url(self, key: str) -> str:
        url = (self.config.get("sources") or {}).get(key, "")
        if not url:
            raise ValueError(f"Missing sources.{key} in config")
        return url

    def _print_preview(self, app_name, module_name, support_doc, profile,
                       manifest_text, form_text, manifest_result, form_result, icon_result):
        sep = "=" * 72
        print(f"\n{sep}")
        print(f"  APP: {app_name}  |  profile: {profile}")
        print(f"  module: {module_name}  |  support_doc: {support_doc or '(none)'}")
        print(sep)
        for label, text, result in [("manifest.yml", manifest_text, manifest_result),
                                    ("form.yml.erb", form_text, form_result)]:
            print(f"\n--- {label}  [{result['status']}] ---")
            if result["status"] == "skipped":
                print(f"  ({result['detail']})")
            else:
                print(text.rstrip())
        print(f"\n--- icon  [{icon_result['status']}] ---\n  {icon_result['detail']}\n")

    def _print_summary(self, results: list):
        total = len(results)
        failed = sum(1 for r in results if "error" in r)
        changed = sum(
            1 for r in results
            if any(f.get("status") in ("created", "updated", "prompted")
                   for f in (r.get("files") or {}).values())
        )
        print(f"targets: {total}  changed: {changed}  failed: {failed}  write: {self.options['write']}")


def _render_field_ruby(field: dict) -> str:
    name = field.get("name", "unknown")
    widget = field.get("widget", "text_field")
    label = field.get("label", name)
    help_text = field.get("help", "")
    value = field.get("value", "")
    options = field.get("options")

    pairs = [f"'widget' => '{widget}'", f"'label'  => \"{label}\""]
    if value:
        pairs.append(f"'value'  => \"{value}\"")
    if help_text:
        pairs.append(f"'help'   => \"{help_text}\"")
    if options and widget == "select":
        opts_rb = ", ".join(f'["{lbl}", "{val}"]' for lbl, val in options)
        pairs.append(f"'options' => [{opts_rb}]")

    inner = ",\n".join(f"      {p}" for p in pairs)
    return f"    new_form['{name}'] = {{\n{inner}\n    }}"


def _result(status: str, detail: str) -> dict:
    return {"status": status, "detail": detail}


def _yaml_to_text(data: dict) -> str:
    return AI_MARKER + "\n" + yaml.dump(data, default_flow_style=False, allow_unicode=True)


def _parse_frontmatter(markdown: str) -> dict:
    lines = markdown.splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        return {}
    try:
        end = next(i for i, ln in enumerate(lines[1:], 1) if ln.strip() == "---")
        return yaml.safe_load("".join(lines[1:end])) or {}
    except (StopIteration, Exception):
        return {}


def parse_args() -> dict:
    parser = argparse.ArgumentParser(
        prog="generate_apps.py",
        description="Generate or refresh OpenComposer app metadata.",
    )
    parser.add_argument("--app", dest="apps", action="append", default=[], metavar="NAME",
                        help="Target a single app (repeatable)")
    parser.add_argument("--all", dest="all", action="store_true",
                        help="Target all app folders in apps/")
    parser.add_argument("--write", action="store_true",
                        help="Write changes to files (default is preview only)")
    parser.add_argument("--force", action="store_true",
                        help="Overwrite human-edited files (those missing the AI marker)")
    parser.add_argument("--force-icon", dest="force_icon", action="store_true",
                        help="Regenerate icon even when one already exists")
    parser.add_argument("--config", default=DEFAULT_CONFIG_PATH, metavar="PATH",
                        help=f"Config path (default: {DEFAULT_CONFIG_PATH})")
    parser.add_argument("--verbose", action="store_true",
                        help="Include tracebacks in error output")
    ns = parser.parse_args()
    return vars(ns)


def main():
    options = parse_args()
    root = Path(__file__).resolve().parent.parent.parent
    AppGenerator(root=root, options=options).run()


if __name__ == "__main__":
    main()