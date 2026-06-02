#!/usr/bin/env python3
"""
Generates an OpenComposer app for every module in the NeSI modules-list.
Run from the project root: python generate_apps.py
"""
import json
import os
import re
import urllib.request
import ssl
from tqdm import tqdm

APPS_DIR  = os.path.join(os.path.dirname(__file__), "apps")
SKIP_DIRS = {
    # Hand-crafted apps — never overwrite
    "LAMMPS", "SlurmGPU", "SlurmBasic",
    # Manually removed — do not regenerate
    "AOCC", "AOCL-BLAS", "AOCL-BLIS", "AOCL-FFTW", "AOCL-ScaLAPACK",
    "AlphaFold2DB", "AlphaFold3DB", "AlwaysIntelMKL", "Apptainer",
    "Boost", "CMake", "CUDA", "Clang", "Doxygen", "EasyBuild", "Eigen",
    "FFTW", "FFTW.MPI", "FFmpeg", "FlexiBLAS", "Globus-CLI",
    "ImageMagick", "JupyterLab", "M4", "Marimo", "Mesa", "Meson",
    "NVHPC", "OpenBLAS", "OpenBabel", "OpenCV", "OpenFOAM", "OpenJPEG",
    "OpenMC", "OpenMPI", "OpenSSL", "OpenSees", "OpenSeesPy", "OpenSlide",
    "Parallel", "ParallelIO", "UCC", "UCC-CUDA", "UCX", "UCX-CUDA",
    "XZ", "Zip", "binutils", "bzip2", "cairo", "code-server", "easi",
    "f90wrap", "flex", "fontconfig", "foss", "freetype", "funcx-endpoint",
    "g2clib", "gettext", "gfbf", "gimkl", "gimpi", "git",
    "globus-compute-endpoint", "gompi", "google-sparsehash", "googletest",
    "gperf", "h5pp", "h5py", "iccifort", "ifbf", "iimpi", "imkl",
    "imkl-FFTW", "impi", "intel", "intel-compilers", "iofbf", "iompi",
    "libRmath", "libarchive", "libcuda-stub", "libpng", "libreadline",
    "libvori", "libxc", "libxml2", "libzstd", "matlab-proxy", "mctc-lib",
    "mpcci", "nano", "ncurses", "nesi_eb", "nf-core", "numactl", "pandoc",
    "parallel-fastq-dump", "pod5", "tmux", "wannier90", "x264", "x265",
    "xkbcommon", "yaml-cpp", "zlib", "zstd",
}
URL       = "https://raw.githubusercontent.com/nesi/modules-list/main/module-list.json"

DOMAIN_CATEGORIES = {
    "engineering":     "Engineering",
    "biology":         "Biology",
    "chemistry":       "Chemistry",
    "machine_learning": "Machine Learning",
    "mathematics":     "Mathematics",
    "visualisation":   "Visualisation",
    "earth_science":   "Earth Science",
    "social_science":  "Social Science",
}

# ERB templates use __PLACEHOLDERS__ substituted by Python before writing.
# Single-quoted SCRIPT heredoc preserves #{...} tokens for OpenComposer's template engine.

# Python doesn't interpolate #{...} so these tokens survive into the generated
# ERB files as-is. Inside Ruby's single-quoted <<~'SCRIPT' heredoc they are
# treated as literal text, ready for OpenComposer's own template substitution.

GPU_ERB_TEMPLATE = (
    "<%\n"
    "base_path = File.join(File.dirname(yml_path), '../__SLURM_BASE__/form.yml')\n"
    "base = YAML.load_file(base_path)\n"
    "\n"
    "new_form = {}\n"
    "base['form'].each do |k, v|\n"
    "  if k == 'time_days_hours_minutes'\n"
    "    new_form['__MOD_KEY__'] = {\n"
    "      'widget' => 'module_load',\n"
    "      'module' => __MOD_NAME_RUBY__,\n"
    "      'label'  => __MOD_LABEL_RUBY__\n"
    "    }\n"
    "  end\n"
    "  new_form[k] = v\n"
    "end\n"
    "\n"
    "base['form']   = new_form\n"
    "base['script'] = <<~'SCRIPT'\n"
    "  #!/bin/bash -e\n"
    "  #SBATCH --job-name=#{OC_JOB_NAME}\n"
    "  #SBATCH --partition=#{partition}\n"
    "  #SBATCH --ntasks=#{cores_simple}\n"
    "  #SBATCH --ntasks=#{cores_advanced_1}\n"
    "  #SBATCH --cpus-per-task=#{cores_advanced_2}\n"
    "  #SBATCH --nodes=#{number_of_nodes}\n"
    "  #SBATCH --mem=#{memory_total_gb}G\n"
    "  #SBATCH --mem-per-cpu=#{memory_per_cpu_gb}G\n"
    "  #SBATCH --gpus-per-node=#{gpu_any}:#{number_of_gpus_any}\n"
    "  #SBATCH --gpus-per-node=#{gpu_genoa}:#{number_of_gpus_genoa}\n"
    "  #SBATCH --gpus-per-node=#{gpu_milan}:#{number_of_gpus_milan}\n"
    "  #SBATCH --time=#{time_days_hours_minutes_1}-#{zeropadding(time_days_hours_minutes_2,2)}:#{zeropadding(time_days_hours_minutes_3,2)}:#{zeropadding(time_days_hours_minutes_4,2)}\n"
    "  #SBATCH --array=#{array_1}-#{array_2}:#{array_3}\n"
    "  #SBATCH --qos=#{testing}\n"
    "  #SBATCH --profile=#{profiling}\n"
    "  #SBATCH --acctg-freq=#{profiling_time}\n"
    "  #SBATCH --mail-type=#{mail_option}\n"
    "\n"
    "  module purge\n"
    "  module load #{__MOD_KEY__}\n"
    "\n"
    "SCRIPT\n"
    "%>\n"
    "<%= base.to_yaml -%>\n"
)

CPU_ERB_TEMPLATE = (
    "<%\n"
    "base_path = File.join(File.dirname(yml_path), '../__SLURM_BASE__/form.yml')\n"
    "base = YAML.load_file(base_path)\n"
    "\n"
    "new_form = {}\n"
    "base['form'].each do |k, v|\n"
    "  if k == 'time_days_hours_minutes'\n"
    "    new_form['__MOD_KEY__'] = {\n"
    "      'widget' => 'module_load',\n"
    "      'module' => __MOD_NAME_RUBY__,\n"
    "      'label'  => __MOD_LABEL_RUBY__\n"
    "    }\n"
    "  end\n"
    "  new_form[k] = v\n"
    "end\n"
    "\n"
    "base['form']   = new_form\n"
    "base['script'] = <<~'SCRIPT'\n"
    "  #!/bin/bash -e\n"
    "  #SBATCH --job-name=#{OC_JOB_NAME}\n"
    "  #SBATCH --partition=#{partition}\n"
    "  #SBATCH --ntasks=#{cores_simple}\n"
    "  #SBATCH --ntasks=#{cores_advanced_1}\n"
    "  #SBATCH --cpus-per-task=#{cores_advanced_2}\n"
    "  #SBATCH --nodes=#{number_of_nodes}\n"
    "  #SBATCH --mem=#{memory_total_gb}G\n"
    "  #SBATCH --mem-per-cpu=#{memory_per_cpu_gb}G\n"
    "  #SBATCH --time=#{time_days_hours_minutes_1}-#{zeropadding(time_days_hours_minutes_2,2)}:#{zeropadding(time_days_hours_minutes_3,2)}:#{zeropadding(time_days_hours_minutes_4,2)}\n"
    "  #SBATCH --array=#{array_1}-#{array_2}:#{array_3}\n"
    "  #SBATCH --qos=#{testing}\n"
    "  #SBATCH --profile=#{profiling}\n"
    "  #SBATCH --acctg-freq=#{profiling_time}\n"
    "  #SBATCH --mail-type=#{mail_option}\n"
    "\n"
    "  module purge\n"
    "  module load #{__MOD_KEY__}\n"
    "\n"
    "SCRIPT\n"
    "%>\n"
    "<%= base.to_yaml -%>\n"
)


def sanitize_dir(name: str) -> str:
    return re.sub(r'[/\\\x00]', '_', name)


def sanitize_key(name: str) -> str:
    key = re.sub(r'[^a-z0-9]', '_', name.lower())
    key = re.sub(r'_+', '_', key).strip('_')
    if not key or key[0].isdigit():
        key = 'm' + key
    return key + '_module'


def category_for(domains: list) -> str:
    non_gpu = [d for d in domains if d.lower() != 'gpu']
    if not non_gpu:
        return "Others"
    d = non_gpu[0].lower()
    return DOMAIN_CATEGORIES.get(d, ' '.join(w.capitalize() for w in re.split(r'[_\-]', d)))


def ruby_string(s: str) -> str:
    """Return s as a Ruby double-quoted string literal with proper escaping."""
    escaped = s.replace('\\', '\\\\').replace('"', '\\"').replace('#', '\\#')
    return f'"{escaped}"'


def yaml_str(s: str) -> str:
    """Simple YAML scalar: quote if it contains special chars or newlines."""
    if any(c in s for c in (':', '#', '\n', '"', "'")):
        lines = s.splitlines()
        if len(lines) > 1:
            indented = '\n'.join('  ' + ln for ln in lines)
            return '|\n' + indented
        return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'
    return s


def main():
    print("Fetching module list from GitHub...")
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(URL, context=ctx, timeout=30) as resp:
        modules = json.loads(resp.read().decode())
    print(f"{len(modules)} modules found")

    created = 0
    skipped = 0

    for name, data in tqdm(modules.items(), desc="Generating apps", unit="app"):
        dir_name = sanitize_dir(name)
        app_dir  = os.path.join(APPS_DIR, dir_name)

        if dir_name in SKIP_DIRS or os.path.isdir(app_dir):
            skipped += 1
            continue

        domains     = [str(d) for d in (data.get("domains") or [])]
        gpu         = any(d.lower() == "gpu" for d in domains)
        category    = category_for(domains)
        description = (data.get("description") or "").strip() or f"{name} application."
        mod_key     = sanitize_key(name)
        slurm_base  = "SlurmGPU" if gpu else "SlurmBasic"

        os.makedirs(app_dir)

        # manifest.yml
        manifest = (
            "---\n"
            f"name: {yaml_str(name)}\n"
            f"category: {yaml_str(category)}\n"
            f"description: {yaml_str(description)}\n"
        )
        with open(os.path.join(app_dir, "manifest.yml"), "w") as f:
            f.write(manifest)

        # form.yml.erb
        template = GPU_ERB_TEMPLATE if gpu else CPU_ERB_TEMPLATE
        erb = (template
               .replace("__SLURM_BASE__",     slurm_base)
               .replace("__MOD_KEY__",         mod_key)
               .replace("__MOD_NAME_RUBY__",   ruby_string(name))
               .replace("__MOD_LABEL_RUBY__",  ruby_string(f"{name} Module")))
        with open(os.path.join(app_dir, "form.yml.erb"), "w") as f:
            f.write(erb)

        created += 1

    print(f"Done. Created: {created}, Skipped (existing/reserved): {skipped}")


if __name__ == "__main__":
    main()
