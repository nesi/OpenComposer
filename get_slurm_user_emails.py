#!/usr/bin/env python3
"""
get_slurm_user_emails.py

Read one or more text files containing Slurm job IDs (one per line, array tasks
like ``579306_3`` allowed) and work out who ran each job and, where possible,
their notification email address.

How it works
------------
Slurm's accounting database (``sacct``) reliably records the *username* that
submitted each job, even for long-finished jobs. It does **not** store an email
address. The contact email is looked up from FreeIPA with
``ipa user-show <username>`` (the ``Email address:`` field).

This script therefore:
  1. Extracts and de-duplicates the base job IDs from each file.
  2. Batches them through ``sacct -X`` to map job -> username.
  3. Looks up each unique username in FreeIPA (``ipa user-show``) for the email.
  4. Falls back to the username when no email could be found.

Needs the Slurm client tools (``sacct``) and the FreeIPA client (``ipa``), and
a valid Kerberos ticket for ``ipa`` (run ``kinit`` first if prompted).

Output: a per-file summary, a de-duplicated unique email list, and a combined
CSV (user, email, source, n_jobs, files).

Usage
-----
    python3 get_slurm_user_emails.py *.txt
    python3 get_slurm_user_emails.py A100_*.txt H100_*.txt L4_*.txt -o users.csv
    python3 get_slurm_user_emails.py file.txt --no-email       # usernames only

Must run on a node with the Slurm client tools (``sacct``) and FreeIPA (``ipa``).
"""

import argparse
import csv
import re
import subprocess
import sys
from collections import defaultdict
from shutil import which

try:
    from tqdm import tqdm
except ImportError:  # graceful fallback if tqdm isn't installed
    def tqdm(iterable=None, **kwargs):
        return iterable if iterable is not None else []

JOBID_RE = re.compile(r"^\s*(\d+)(?:[_.].*)?\s*$")  # capture leading numeric job id


def read_job_ids(path):
    """Return the ordered, de-duplicated base job IDs found in *path*."""
    seen = set()
    ids = []
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = JOBID_RE.match(line)
            if not m:
                continue
            jid = m.group(1)
            if jid not in seen:
                seen.add(jid)
                ids.append(jid)
    return ids


def batched(seq, size):
    for i in range(0, len(seq), size):
        yield seq[i:i + size]


def sacct_users(job_ids, batch=500):
    """Map base job id -> username via ``sacct -X``. Missing jobs are skipped."""
    mapping = {}
    n_batches = (len(job_ids) + batch - 1) // batch
    for chunk in tqdm(batched(job_ids, batch), total=n_batches,
                      desc="sacct (usernames)", unit="batch"):
        cmd = [
            "sacct", "-X", "-n", "-P",
            "-j", ",".join(chunk),
            "-o", "JobID,User",
        ]
        try:
            out = subprocess.run(
                cmd, capture_output=True, text=True, check=True
            ).stdout
        except FileNotFoundError:
            sys.exit("error: 'sacct' not found. Run this on a Slurm submit/login node.")
        except subprocess.CalledProcessError as e:
            sys.stderr.write(f"warning: sacct failed for a batch: {e.stderr.strip()}\n")
            continue
        for row in out.splitlines():
            if not row.strip():
                continue
            parts = row.split("|")
            if len(parts) < 2:
                continue
            jobid, user = parts[0], parts[1]
            base = jobid.split(".")[0].split("_")[0]
            if user:
                mapping.setdefault(base, user)
    return mapping


def ipa_email(user):
    """Return the email address for *user* from FreeIPA (``ipa user-show``), or None."""
    try:
        res = subprocess.run(
            ["ipa", "user-show", user],
            capture_output=True, text=True,
        )
    except FileNotFoundError:
        return None
    if res.returncode != 0:
        return None  # user not found in IPA, or no Kerberos ticket
    m = re.search(r"Email address:\s*(\S+)", res.stdout)
    return m.group(1) if m else None


def resolve_emails(users):
    """Map each username -> IPA email address (or None if not resolvable)."""
    emails = {}
    for user in tqdm(users, total=len(users), desc="ipa user-show", unit="user"):
        emails[user] = ipa_email(user)
    return emails


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="+", help="text files of Slurm job IDs")
    ap.add_argument("-o", "--output", default="slurm_user_emails.csv",
                    help="combined CSV output path (default: slurm_user_emails.csv)")
    ap.add_argument("--no-email", action="store_true",
                    help="skip the IPA email lookup; list usernames only")
    ap.add_argument("--dry-run", action="store_true",
                    help="only parse/count job IDs per file; do not call Slurm "
                         "(useful for testing off-cluster)")
    ap.add_argument("--batch", type=int, default=500,
                    help="sacct job-id batch size (default: 500)")
    args = ap.parse_args()

    # 1. Extract job IDs per file.
    file_jobs = {}
    all_ids = []
    seen = set()
    for path in args.files:
        ids = read_job_ids(path)
        file_jobs[path] = ids
        for jid in ids:
            if jid not in seen:
                seen.add(jid)
                all_ids.append(jid)
        print(f"{path}: {len(ids)} unique job IDs", file=sys.stderr)
    print(f"total unique job IDs across all files: {len(all_ids)}", file=sys.stderr)

    if args.dry_run:
        print("\n--dry-run: parsed job IDs only, no Slurm calls made.",
              file=sys.stderr)
        return

    # 2. job -> user via sacct.
    print("querying sacct for usernames...", file=sys.stderr)
    job_user = sacct_users(all_ids, batch=args.batch)
    print(f"sacct returned a user for {len(job_user)}/{len(all_ids)} jobs", file=sys.stderr)

    # user -> ordered jobs (for probing) and per-file user sets.
    user_to_jobs = defaultdict(list)
    for jid in all_ids:
        u = job_user.get(jid)
        if u:
            user_to_jobs[u].append(jid)

    file_users = {}
    for path, ids in file_jobs.items():
        users = sorted({job_user[j] for j in ids if j in job_user})
        file_users[path] = users

    # 3. Resolve emails via FreeIPA (optional).
    if args.no_email:
        emails = {u: None for u in user_to_jobs}
    else:
        if which("ipa") is None:
            print("warning: 'ipa' not found; emails will fall back to usernames",
                  file=sys.stderr)
        print("looking up emails via FreeIPA (ipa user-show)...", file=sys.stderr)
        emails = resolve_emails(list(user_to_jobs))
        n_found = sum(1 for v in emails.values() if v)
        print(f"resolved an email for {n_found}/{len(emails)} users",
              file=sys.stderr)

    # user -> which files they appear in
    user_files = defaultdict(list)
    for path, users in file_users.items():
        for u in users:
            user_files[u].append(path)

    # 4a. Per-file report to stdout.
    for path in args.files:
        print("\n" + "=" * 70)
        print(f"FILE: {path}")
        print("=" * 70)
        users = file_users[path]
        if not users:
            print("  (no users resolved — jobs may be purged from sacct)")
            continue
        print(f"  {len(users)} distinct user(s):")
        for u in users:
            email = emails.get(u)
            shown = email if email else f"{u} (no email; username only)"
            print(f"    {u:<20} -> {shown}")

    # 4b. De-duplicated unique contact list (each email/username once).
    contacts = sorted({(emails.get(u) or u) for u in user_to_jobs})
    print("\n" + "=" * 70)
    print(f"UNIQUE CONTACTS: {len(contacts)} (de-duplicated)")
    print("=" * 70)
    for c in contacts:
        print(f"  {c}")
    unique_path = "unique_emails.txt"
    with open(unique_path, "w") as fh:
        fh.write("\n".join(contacts) + "\n")
    print(f"\nwrote unique contact list: {unique_path}", file=sys.stderr)

    # 4c. Combined CSV.
    with open(args.output, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["user", "email", "email_source", "n_jobs", "files"])
        for u in sorted(user_to_jobs):
            email = emails.get(u)
            source = "ipa" if email else "username-fallback"
            w.writerow([
                u,
                email if email else u,
                source,
                len(user_to_jobs[u]),
                ";".join(user_files.get(u, [])),
            ])
    print(f"\nwrote combined CSV: {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
