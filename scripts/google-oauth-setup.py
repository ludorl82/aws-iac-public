#!/usr/bin/env python3
"""Authorize one Google account for the numeriseur pipeline and store it.

Run once per Drive account:

    ./scripts/google-oauth-setup.py --account ludo
    ./scripts/google-oauth-setup.py --account lea     # needs its owner at the browser

It MERGES into numeriseur/google-drive rather than replacing it, so authorizing
lea later does not clobber ludo's token. That is the whole reason this is a
script and not a documented curl sequence.

Why drive.file, and why it CANNOT use your existing folders
-----------------------------------------------------------
The scope is drive.file, which grants per-file access strictly to what the app
itself created. The Numerisations/ and Photos/ folders rclone has been writing
to are therefore invisible to it, permanently -- they cannot be adopted, shared
to the app, or looked up by name. This script creates its own destinations.

Read that twice before trusting any folder name you see. The app's view of
Drive is a strict SUBSET of yours, so a files.list for "Numerisations" that
returns a hit has NOT found your folder -- it has found one this app made
earlier. That distinction cost a misdirected cutover on 2026-08-05: two
identically-named folders, and scans delivered to the wrong one. Use --inspect,
which prints createdTime and parents, rather than trusting a name match.

Full `drive` would lift the restriction, but it is a restricted scope, and
a dedicated OAuth client left in "Testing" publishing status is issued refresh
tokens that expire after 7 DAYS. Getting long-lived tokens means publishing to
production, which for a restricted scope requires Google verification plus a
paid annual CASA security assessment; for drive.file it is free and immediate.
rclone only got away with `drive` because its shared client is already verified
-- which is exactly the shared-credential arrangement this replaces.

So: publish the consent screen to production BEFORE running this, or the
pipeline will quietly stop working a week later.

No secret ever touches the filesystem: the client secret is read from the
environment or prompted for, and the assembled document is piped to the AWS CLI
on stdin rather than passed as an argument, where it would show up in ps.
"""

import argparse
import getpass
import json
import os
import subprocess
import sys
import urllib.parse
import urllib.request

SECRET_ID = "numeriseur/google-drive"
SCOPE = "https://www.googleapis.com/auth/drive.file"

# Not a real listener. Google redirects the browser here, nothing answers, and
# the code sits in the address bar for copy-paste. Beats standing up a server
# the browser could not reach anyway -- it runs on your laptop, this runs on the
# console shell.
REDIRECT_URI = "http://localhost:8765/"

AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
TOKEN_URL = "https://oauth2.googleapis.com/token"
FILES_URL = "https://www.googleapis.com/drive/v3/files"

# folder key in the secret -> folder name in Drive. The keys are what
# handler.py's ROUTES table refers to.
FOLDERS = {"documents": "Numerisations", "photos": "Photos"}


def post_form(url, fields):
    body = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(
        url, data=body, headers={"Content-Type": "application/x-www-form-urlencoded"}
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def drive(token, method, url, payload=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    if data:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def ensure_folder(token, name):
    """Find an app-created folder by this name, or make one. Idempotent so the
    script can be re-run after a failure without littering Drive."""
    query = urllib.parse.urlencode(
        {
            "q": (
                "mimeType = 'application/vnd.google-apps.folder' "
                f"and name = '{name}' and trashed = false"
            ),
            "fields": "files(id,name)",
        }
    )
    found = drive(token, "GET", f"{FILES_URL}?{query}").get("files", [])
    if found:
        # Say WHOSE folder this is. The old wording here was "reusing existing
        # folder", which reads as "found the folder you already had" -- and it
        # cannot be that, because drive.file only ever returns folders this app
        # created. That ambiguity sent a real cutover at the wrong destination.
        print(f"  reusing {name} ({found[0]['id']}) — created by THIS app on an "
              f"earlier run, not your pre-existing {name} folder")
        return found[0]["id"]
    created = drive(
        token,
        "POST",
        FILES_URL + "?fields=id",
        {"name": name, "mimeType": "application/vnd.google-apps.folder"},
    )
    print(f"  created folder {name} ({created['id']})")
    return created["id"]


def read_secret():
    """Current document, or an empty one if the secret has no value yet.

    Existence is checked with describe-secret rather than inferred from
    get-secret-value's error. GetSecretValue raises ResourceNotFoundException
    for BOTH a secret that does not exist and one that exists with no version
    yet -- so keying off that error makes the very first run, the one this
    script exists for, indistinguishable from a missing secret.
    """
    described = subprocess.run(
        ["aws", "secretsmanager", "describe-secret", "--secret-id", SECRET_ID,
         "--query", "Name", "--output", "text"],
        capture_output=True, text=True,
    )
    if described.returncode != 0:
        sys.exit(f"secret {SECRET_ID} does not exist -- apply aws-iac first\n"
                 f"{described.stderr.strip()}")

    result = subprocess.run(
        ["aws", "secretsmanager", "get-secret-value", "--secret-id", SECRET_ID,
         "--query", "SecretString", "--output", "text"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        # The secret exists (checked above), so this is the never-populated
        # case: first run. Start from an empty document.
        print("note: secret has no value yet, creating the first version")
        return {}
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        print("note: existing secret is not valid JSON, replacing it")
        return {}


def write_secret(document):
    # file:///dev/stdin, not --secret-string "$json": an argument would be
    # visible to anyone running ps while this executes.
    proc = subprocess.run(
        ["aws", "secretsmanager", "put-secret-value", "--secret-id", SECRET_ID,
         "--secret-string", "file:///dev/stdin", "--output", "text",
         "--query", "VersionId"],
        input=json.dumps(document), capture_output=True, text=True,
    )
    if proc.returncode != 0:
        sys.exit(f"put-secret-value failed: {proc.stderr.strip()}")
    print(f"stored version {proc.stdout.strip()}")


def inspect(account):
    """Show every folder this app can actually see, and where it sits.

    Exists because "the app found a folder called Numerisations" turned out not
    to mean "the app found YOUR folder called Numerisations". drive.file makes
    the app's view of Drive a strict subset of the user's, so the console and
    this script disagree about what exists, and only this view decides where a
    scan lands. Prints parents and creation time so a stray folder can be told
    apart from the real destination.
    """
    cfg = config_from_secret()
    token = access_token_for(cfg, account)

    query = urllib.parse.urlencode({
        "q": "mimeType = 'application/vnd.google-apps.folder' and trashed = false",
        "fields": "files(id,name,createdTime,parents,ownedByMe)",
        "pageSize": "100",
    })
    files = drive(token, "GET", f"{FILES_URL}?{query}").get("files", [])

    print(f"folders visible to this app as {account}: {len(files)}")
    for f in files:
        parent = (f.get("parents") or ["<none>"])[0]
        print(f"  {f['name']:30} id={f['id']}")
        print(f"  {'':30} created={f.get('createdTime')} ownedByMe={f.get('ownedByMe')} parent={parent}")

    configured = cfg.get("accounts", {}).get(account, {}).get("folders", {})
    if configured:
        print("\ncurrently configured as destinations:")
        for key, fid in configured.items():
            match = next((f["name"] for f in files if f["id"] == fid), "NOT VISIBLE")
            print(f"  {key:12} -> {fid}  ({match})")
    print("\nOpen a folder in Drive to identify it: "
          "https://drive.google.com/drive/folders/<id>")


def config_from_secret():
    doc = read_secret()
    if not doc.get("accounts"):
        sys.exit("secret has no accounts yet -- run without --inspect first")
    return doc


def access_token_for(cfg, account):
    if account not in cfg.get("accounts", {}):
        sys.exit(f"account {account} is not in the secret yet")
    payload = post_form(TOKEN_URL, {
        "grant_type": "refresh_token",
        "refresh_token": cfg["accounts"][account]["refresh_token"],
        "client_id": cfg["client_id"],
        "client_secret": cfg["client_secret"],
    })
    return payload["access_token"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--account", required=True, choices=["ludo", "lea"],
                        help="which Drive account is being authorized")
    parser.add_argument("--inspect", action="store_true",
                        help="list the folders this app can see and exit; "
                             "uses the stored token, no re-consent")
    parser.add_argument("--set-folder", nargs=2, metavar=("KEY", "FOLDER_ID"),
                        help="point a destination (documents|photos) at a "
                             "specific folder id, without re-authorizing")
    args = parser.parse_args()

    if args.inspect:
        inspect(args.account)
        return

    if args.set_folder:
        key, folder_id = args.set_folder
        if key not in FOLDERS:
            sys.exit(f"folder key must be one of {', '.join(FOLDERS)}")
        doc = config_from_secret()
        # Verify the app can actually see it first. Writing an id the app
        # cannot reach would fail later, inside the Lambda, on a real scan.
        token = access_token_for(doc, args.account)
        try:
            info = drive(token, "GET", f"{FILES_URL}/{folder_id}?fields=id,name")
        except urllib.error.HTTPError as exc:
            sys.exit(f"this app cannot access folder {folder_id} ({exc.code}). "
                     "drive.file only reaches files the app created -- an "
                     "existing folder cannot be adopted this way.")
        doc["accounts"][args.account]["folders"][key] = folder_id
        write_secret(doc)
        print(f"{args.account}/{key} -> {info['name']} ({folder_id})")
        return

    # Read the secret FIRST, before asking for anything or burning a consent.
    # An authorization code is single-use and a refresh token is only issued
    # once per consent, so any check that can fail must fail before the user
    # goes near the browser -- otherwise a trivial misconfiguration costs a
    # whole re-authorization, which for the lea account means finding its owner
    # again.
    document = read_secret()

    client_id = os.environ.get("GOOGLE_CLIENT_ID") or input("OAuth client id: ").strip()
    client_secret = os.environ.get("GOOGLE_CLIENT_SECRET") or getpass.getpass("OAuth client secret: ").strip()

    consent = AUTH_URL + "?" + urllib.parse.urlencode({
        "client_id": client_id,
        "redirect_uri": REDIRECT_URI,
        "response_type": "code",
        "scope": SCOPE,
        # offline + consent together are what actually return a refresh token.
        # Without prompt=consent Google omits it on re-authorization, which is
        # the classic "it worked the first time" trap.
        "access_type": "offline",
        "prompt": "consent",
    })

    print(f"\n1. Sign in as the {args.account.upper()} account and open:\n\n{consent}\n")
    print("2. Approve. The browser will fail to load localhost:8765 -- that is expected.")
    print("3. Copy the whole address bar (or just the code= value) and paste it here.\n")
    pasted = input("redirect URL or code: ").strip()

    if "code=" in pasted:
        code = urllib.parse.parse_qs(urllib.parse.urlparse(pasted).query)["code"][0]
    else:
        code = pasted

    tokens = post_form(TOKEN_URL, {
        "code": code,
        "client_id": client_id,
        "client_secret": client_secret,
        "redirect_uri": REDIRECT_URI,
        "grant_type": "authorization_code",
    })

    if "refresh_token" not in tokens:
        sys.exit("no refresh_token returned -- revoke the app's access at "
                 "myaccount.google.com and retry, Google only issues one on first consent")

    print("\nsetting up folders:")
    folders = {key: ensure_folder(tokens["access_token"], name) for key, name in FOLDERS.items()}

    document["client_id"] = client_id
    document["client_secret"] = client_secret
    document.setdefault("accounts", {})[args.account] = {
        "refresh_token": tokens["refresh_token"],
        "folders": folders,
    }

    write_secret(document)
    print(f"\naccount {args.account} authorized. accounts now in the secret: "
          f"{', '.join(sorted(document['accounts']))}")


if __name__ == "__main__":
    main()
