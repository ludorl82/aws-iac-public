"""Post-upload processing for the numeriseur scanner pipeline.

Replaces the post-upload.sh action hook that used to run inside the SFTPGo
container (imagemagick + rclone + awscli). SFTPGo writes scans straight to S3;
EventBridge fires this function on Object Created; it pushes to Google Drive.

Why this moved out of the container at all: the hook was the entire reason that
image was custom. sftpgo also strips the parent environment before running
action hooks, which is why credentials had to be written to /etc/aws/credentials
and a bucket.env at container start -- a workaround that disappears with the
hook itself.

Key layout, unchanged from the SFTPGo side:

    <username>/<vdir>/<filename>

where vdir is pdf, jpg or photos. `photos` was silently dropped by the old
hook's catch-all (it only matched /pdf/* and /jpg/*), so scans uploaded there
never reached Drive -- three of them are still sitting in the bucket. It is
handled here as a synonym for jpg.

DERIVATIVES ARE NEVER WRITTEN BACK TO S3. The old hook uploaded the processed
JPEG to ${USERNAME}/jpg/$JPGNAME, the same prefix that triggered it. Under a
polling hook that was merely redundant; under S3 events it is an infinite loop,
and for a .jpg input the output key is byte-identical to the input key. Images
are processed in memory and uploaded straight to Drive. If a cleaned copy is
ever wanted in S3, it goes in a different bucket, not a different prefix.

Two invocation shapes:

  EventBridge  -- {"detail-type": "Object Created", "detail": {...}}
  backfill     -- {"backfill": {"prefix": "lea/", "accounts": ["lea"]}}

The backfill mode exists because the Google credentials are rotated one account
at a time: until lea re-authorizes, anything bound for her Drive lands in S3 and
is not delivered. S3 is the queue; this replays it. `accounts` restricts
delivery so replaying ludoetlea/ after her re-auth does not push a second copy
to ludo, who already got it.
"""

import io
import json
import logging
import os
import time
import urllib.error
import urllib.parse
import urllib.request

import boto3
from PIL import Image, ImageChops, ImageOps

log = logging.getLogger()
log.setLevel(logging.INFO)

BUCKET = os.environ["BUCKET"]
SECRET_ID = os.environ["SECRET_ID"]

TOKEN_URL = "https://oauth2.googleapis.com/token"
UPLOAD_URL = "https://www.googleapis.com/upload/drive/v3/files"
FILES_URL = "https://www.googleapis.com/drive/v3/files"

# (username, vdir) -> (drive accounts, folder key within each account)
#
# Mirrors the case statements in the old post-upload.sh exactly, except that
# `photos` as a vdir is now accepted alongside `jpg` (see module docstring).
ROUTES = {
    ("ludo", "pdf"): (["ludo"], "documents"),
    ("lea", "pdf"): (["lea"], "documents"),
    ("ludoetlea", "pdf"): (["ludo", "lea"], "documents"),
    ("photos", "jpg"): (["ludo", "lea"], "photos"),
    ("cartes", "jpg"): (["ludo", "lea"], "photos"),
}

s3 = boto3.client("s3")
secrets = boto3.client("secretsmanager")

# Warm-invocation caches. Both are per-container and deliberately not persisted:
# a cold start just pays for one GetSecretValue and one token exchange.
_config = None
_tokens = {}  # account -> (access_token, expires_at)


# --- credentials -----------------------------------------------------------


def config():
    """The whole Google side, from one secret.

    One secret rather than one per account so that adding lea later is an edit
    to a JSON document rather than new infrastructure. Shape:

        {"client_id": "...", "client_secret": "...",
         "accounts": {"ludo": {"refresh_token": "...",
                               "folders": {"documents": "<id>",
                                           "photos": "<id>"}}}}

    An account that is absent is not an error -- it is the expected state
    between the two halves of the credential rotation.
    """
    global _config
    if _config is None:
        _config = json.loads(secrets.get_secret_value(SecretId=SECRET_ID)["SecretString"])
    return _config


def access_token(account):
    """Exchange the stored refresh token for an access token, with caching.

    Deliberately plain urllib rather than google-api-python-client: the only
    two operations needed are this exchange and a multipart upload, and pulling
    in the Google client libraries would roughly triple a deployment package
    whose only binary dependency today is Pillow.
    """
    cached = _tokens.get(account)
    if cached and cached[1] > time.time() + 60:
        return cached[0]

    cfg = config()
    acct = cfg["accounts"][account]
    body = urllib.parse.urlencode(
        {
            "grant_type": "refresh_token",
            "refresh_token": acct["refresh_token"],
            "client_id": cfg["client_id"],
            "client_secret": cfg["client_secret"],
        }
    ).encode()

    req = urllib.request.Request(
        TOKEN_URL,
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.load(resp)

    token = payload["access_token"]
    _tokens[account] = (token, time.time() + int(payload.get("expires_in", 3600)))
    return token


# --- Google Drive ----------------------------------------------------------


def drive_find(account, folder_id, name):
    """Return the id of an existing file with this name in this folder, if any.

    Only used to make backfill re-runs idempotent -- Drive is perfectly happy to
    hold ten files with the same name in the same folder, so replaying a prefix
    twice would otherwise duplicate everything.
    """
    query = f"name = '{name}' and '{folder_id}' in parents and trashed = false"
    url = FILES_URL + "?" + urllib.parse.urlencode({"q": query, "fields": "files(id)"})
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {access_token(account)}"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        files = json.load(resp).get("files", [])
    return files[0]["id"] if files else None


def drive_upload(account, folder_id, name, data, mime):
    """Multipart upload: one request carrying metadata and bytes together.

    Fine for scans -- multipart is documented up to 5 MB and the largest thing
    the flatbed produces is a few hundred KB. A resumable upload would be the
    right answer for anything larger.
    """
    boundary = "numeriseur-boundary-7f3a1c"
    metadata = json.dumps({"name": name, "parents": [folder_id]}).encode()

    body = b"".join(
        [
            f"--{boundary}\r\n".encode(),
            b"Content-Type: application/json; charset=UTF-8\r\n\r\n",
            metadata,
            f"\r\n--{boundary}\r\n".encode(),
            f"Content-Type: {mime}\r\n\r\n".encode(),
            data,
            f"\r\n--{boundary}--\r\n".encode(),
        ]
    )

    req = urllib.request.Request(
        UPLOAD_URL + "?uploadType=multipart&fields=id",
        data=body,
        headers={
            "Authorization": f"Bearer {access_token(account)}",
            "Content-Type": f"multipart/related; boundary={boundary}",
        },
    )
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.load(resp)["id"]


# --- image processing ------------------------------------------------------


def process_photo(data):
    """Pillow port of the imagemagick pipeline the `photos` user got:

        convert x[0] -auto-orient -auto-level \\
                -bordercolor white -border 10x10 -fuzz 85% -trim +repage \\
                -shave 10x10 -density 300 out.jpg

    Not a bit-for-bit reproduction, and the trim is where it differs most:
    imagemagick's -fuzz is a distance in colour space against the corner pixel,
    while this thresholds the per-pixel difference from white. At 85% both are
    aggressive enough that the flatbed lid gets cut and the scan does not, which
    is the behaviour that was actually tuned for (the fuzz was raised 70% -> 85%
    precisely because the lid background was not uniform enough).
    """
    img = Image.open(io.BytesIO(data))
    img.load()

    # -auto-orient: honour the EXIF rotation flag, then drop it, so the pixels
    # and the metadata cannot disagree later.
    img = ImageOps.exif_transpose(img)
    img = img.convert("RGB")

    # -auto-level
    img = ImageOps.autocontrast(img)

    # -bordercolor white -border 10x10: a guaranteed-white frame, so the trim
    # below has something to bite on even when the scan runs to the edge.
    img = ImageOps.expand(img, border=10, fill="white")

    # -fuzz 85% -trim +repage
    white = Image.new("RGB", img.size, (255, 255, 255))
    diff = ImageChops.difference(img, white).convert("L")
    mask = diff.point(lambda p: 255 if p > int(255 * 0.85) else 0)
    bbox = mask.getbbox()
    if bbox:
        img = img.crop(bbox)
    else:
        # Everything is within the fuzz of white -- a blank or near-blank scan.
        # imagemagick leaves the image alone in that case rather than producing
        # a zero-size crop, and so do we.
        log.warning("trim found no content above the fuzz threshold, keeping full frame")

    # -shave 10x10, guarded: shaving an image smaller than the shave is a crash
    # in imagemagick and a negative-size crop here.
    w, h = img.size
    if w > 20 and h > 20:
        img = img.crop((10, 10, w - 10, h - 10))

    out = io.BytesIO()
    img.save(out, format="JPEG", quality=92, dpi=(300, 300))  # -density 300
    return out.getvalue()


# --- routing ---------------------------------------------------------------


def parse_key(key):
    """<username>/<vdir>/<filename> -> (username, vdir, filename).

    Anything else returns None: SFTPGo only ever writes this shape, so a key
    that does not match is either hand-placed or a bug, and both deserve a log
    line rather than a guess.
    """
    parts = key.split("/")
    if len(parts) != 3 or not all(parts):
        return None
    username, vdir, filename = parts
    # `photos` as a vdir is a synonym for jpg -- see module docstring.
    return username, ("jpg" if vdir == "photos" else vdir), filename


def process_key(key, only_accounts=None, skip_if_exists=False):
    """Fetch one object, transform it if needed, deliver it to Drive.

    Returns a short status string for the invocation summary.
    """
    parsed = parse_key(key)
    if not parsed:
        log.warning("unroutable key %s", key)
        return "unroutable"
    username, vdir, filename = parsed

    route = ROUTES.get((username, vdir))
    if not route:
        log.warning("no route for user=%s vdir=%s (%s)", username, vdir, key)
        return "no-route"
    accounts, folder_key = route

    if only_accounts is not None:
        accounts = [a for a in accounts if a in only_accounts]
        if not accounts:
            return "filtered"

    data = s3.get_object(Bucket=BUCKET, Key=key)["Body"].read()
    if not data:
        log.error("empty object %s", key)
        return "empty"

    if folder_key == "documents":
        # The old hook checked the magic bytes and skipped non-PDFs rather than
        # pushing whatever the printer produced. Keep that.
        if data[:4] != b"%PDF":
            log.warning("%s is not a PDF, skipping", key)
            return "not-a-pdf"
        payload, name, mime = data, filename, "application/pdf"

    elif username == "photos":
        if data[:4] == b"%PDF":
            # imagemagick's [0] frame selector implied a PDF could arrive here;
            # Pillow cannot rasterize one and adding Ghostscript to get back a
            # capability nothing has exercised is not worth it. Refuse loudly.
            log.error("%s is a PDF on the image path, cannot process", key)
            return "pdf-on-image-path"
        payload = process_photo(data)
        name, mime = with_jpg_suffix(filename), "image/jpeg"

    else:  # cartes: format-normalised, not enhanced
        if data[:4] == b"%PDF":
            log.error("%s is a PDF on the image path, cannot process", key)
            return "pdf-on-image-path"
        payload, name, mime = normalise_to_jpeg(data, filename)

    delivered = []
    for account in accounts:
        if account not in config()["accounts"]:
            # The expected state mid-rotation. The object stays in S3 and the
            # backfill mode replays it once the credential exists.
            log.warning("no credentials for account %s yet, %s not delivered", account, key)
            continue
        folder_id = config()["accounts"][account]["folders"][folder_key]
        if skip_if_exists and drive_find(account, folder_id, name):
            log.info("%s already in %s/%s, skipping", name, account, folder_key)
            delivered.append(f"{account}:exists")
            continue
        file_id = drive_upload(account, folder_id, name, payload, mime)
        log.info("delivered %s to %s/%s as %s", key, account, folder_key, file_id)
        delivered.append(f"{account}:{file_id}")

    return ",".join(delivered) if delivered else "pending-credentials"


def with_jpg_suffix(filename):
    """foo.bmp -> foo.jpg, foo -> foo.jpg.

    The old hook used ${FILENAME%???}jpg, which chops exactly three characters
    and so mangles any extension that is not three long (foo.jpeg -> foo.jjpg).
    Every file in the bucket today has a three-character extension so it never
    bit, but there is no reason to port the bug.
    """
    base = filename.rsplit(".", 1)[0] if "." in filename else filename
    return base + ".jpg"


def normalise_to_jpeg(data, filename):
    """The cartes path: no enhancement, but the output is always a JPEG.

    The old hook copied the bytes through untouched while renaming the
    extension to .jpg, which is how cartes/jpg/testcarte2.bmp ended up beside a
    testcarte2.jpg that was still a BMP inside. Re-encode instead of lying about
    the format; a file that is already JPEG is passed through as-is.
    """
    if data[:3] == b"\xff\xd8\xff":
        return data, with_jpg_suffix(filename), "image/jpeg"
    img = Image.open(io.BytesIO(data))
    img.load()
    img = ImageOps.exif_transpose(img).convert("RGB")
    out = io.BytesIO()
    img.save(out, format="JPEG", quality=92)
    return out.getvalue(), with_jpg_suffix(filename), "image/jpeg"


# --- entry point -----------------------------------------------------------


def lambda_handler(event, context):
    if "backfill" in event:
        spec = event["backfill"]
        prefix = spec["prefix"]
        only = spec.get("accounts")
        results = {}
        paginator = s3.get_paginator("list_objects_v2")
        for page in paginator.paginate(Bucket=BUCKET, Prefix=prefix):
            for obj in page.get("Contents", []):
                key = obj["Key"]
                try:
                    # skip_if_exists: a backfill is replayed by hand, possibly
                    # more than once, and Drive will not deduplicate for us.
                    results[key] = process_key(key, only_accounts=only, skip_if_exists=True)
                except Exception:
                    log.exception("backfill failed for %s", key)
                    results[key] = "error"
        log.info("backfill %s: %d objects", prefix, len(results))
        return {"backfill": prefix, "results": results}

    # EventBridge "Object Created". Let exceptions escape: the invocation is
    # async, so Lambda retries twice and then parks the event on the DLQ, which
    # is exactly the behaviour wanted. The old hook's failures went to a
    # hook.log file inside the container that nobody read.
    key = urllib.parse.unquote_plus(event["detail"]["object"]["key"])
    log.info("processing %s", key)
    return {"key": key, "status": process_key(key)}
