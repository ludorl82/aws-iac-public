# aws-iac

OpenTofu configuration for AWS account `123456789012`, region `ca-central-1`.

## Scope boundary

**This repo owns everything outside the instance. `nixos-iac` owns everything inside it.**

No `user_data`, no provisioners, no AMI baking. OpenTofu creates the ENI, EIP,
security group and volume; `nixos-anywhere` and the fleet flake handle the OS.
If you ever find yourself writing shell in a `.tf` file, the boundary has been
crossed and the fix belongs in `nixos-iac`.

## Layout

```
bootstrap/   state bucket only, local state, run once
live/        the account: network now, more per phase below
```

## Getting started

```sh
nix develop            # opentofu + awscli2 + jq, AWS_REGION preset

cd bootstrap
tofu init && tofu apply        # creates tfstate-example-com

cd ../live
tofu init                      # picks up the S3 backend
tofu plan                      # review carefully — see below
```

## What the first `live` plan should show

Every attribute in `network.tf` was read off the live account, so the plan
should contain **no destroys and no replacements**. What it *will* show:

- `default_tags` (`ManagedBy`, `Repo`, `Root`) added to every resource.
- A `Name = "principal"` tag added to the main route table, which is currently
  untagged.
- A `Name = "default-unused"` tag added to the default security group, also
  currently untagged.

Phase 3 adds one more expected class: `default_tags` on all 8 buckets.

Those are intentional additions. **Anything else — especially a destroy, a
replace, or a security-group rule being removed — means the config is wrong.
Fix the file, never the account.** An SG rule silently dropped here is a k3s
outage; the EIP being replaced is an unrecoverable IP loss; a bucket replaced
is data loss.

## Phase 3 gotchas

- **The scans bucket moved us-east-1 → ca-central-1 on 2026-07-25**, keeping the
  name `numeriseur-scans-example-com`. A bucket's region is immutable, so
  this was a delete-and-recreate. AWS then held the name for roughly an hour
  after the delete (`CreateBucket` → `OperationAborted`, with no way to check
  progress or hurry it), so the bucket ran temporarily as
  `numeriseur-scans-ca-example-com` until the original freed up and was
  reclaimed. **Next time, create the new bucket first and delete the old one
  last** — deleting first buys nothing and costs an outage of unbounded length.
  `get-bucket-location` reports `None` for us-east-1, which reads as "no region"
  if you skim it.
- **Access keys are not managed.** `aws_iam_access_key` would write secrets in
  plaintext into the state bucket. The five pipeline keys were created out of
  band and live in KeePass; `iam-pipelines.tf` lists the key IDs and dates for
  reference only. Rotation stays a manual, out-of-band operation.
- **Sub-resources are declared only where the live bucket has them.** Three
  buckets have no ownership controls and `shrt.example` has no public access block at
  all. Adding those resources would be a change to the account, not an
  adoption, so they are omitted — most importantly on `shrt.example`, where the
  short-URL lambdas depend on the current object-ACL behaviour. Revisit with
  CloudFront in phase 5.
- **`aws_s3_bucket_versioning` is omitted for never-versioned buckets.**
  `Disabled` is a write-once state you cannot return to once you enable or
  suspend, so declaring it on a fresh bucket is a one-way door. Only
  `homelab-backups` (Enabled) and `loki-logs` (Suspended) declare it.
- **`labodeludo.dev` has public access block all-false on purpose** — it serves
  the public site and its bucket policy requires public policies to be allowed.
  Do not "harden" it without first moving the origin behind an OAI.

## Retention worth knowing about

`homelab-backups-example-com` expires **every object at 30 days**, whole
bucket, no prefix filter, with noncurrent versions gone at 7. There is no
long-term copy of anything in that bucket anywhere in this account. That is a
deliberate policy if you meant it and a nasty surprise if you did not — worth a
decision now that it is written down rather than the next time you need a
restore.

## Pre-commit hook

`hooks/pre-commit` runs on every commit once `core.hooksPath` points at
`hooks/` — `nix develop` sets that for you, or do it by hand:

```sh
git config core.hooksPath hooks
```

It checks staged content (not the working tree, so partial staging is judged on
what is actually being committed) for:

- **Files that must never be committed** — `*.tfstate`, `*.tfvars`, `.terraform/`,
  `*.pem`, `id_rsa`, kubeconfigs
- **Credential shapes** — AWS access/secret keys, Google refresh and access
  tokens, GitHub tokens, PEM private keys, Cloudflare `api_token`/`cf_key`
- **`tofu fmt`**, and `tofu validate` in any directory that is already
  initialised (it will not download providers just to run a commit)
- **Syntax** — `bash -n` for shell, parse checks for JSON and YAML

Bypass with `git commit --no-verify` when you genuinely need to. A hook nobody
can bypass is a hook somebody deletes.

The blocked-file list exists because `tpp-iac` has carried `terraform.tfstate`
and a `.tfvars` holding a Cloudflare key in its history since 2024. Git history
is permanent; this is the cheap way not to repeat it.

## CI: plan on PR, apply on merge

`.github/workflows/` closes the loop the drift check only observes:

- **`plan.yml`** (pull requests): read-only plan via OIDC role
  `gha-aws-iac-plan` (ReadOnlyAccess, `live/iam-github-oidc.tf`), posted as a
  sticky PR comment. `-lock=false` — the plan role cannot write anything.
- **`apply.yml`** (push to cp-1): re-plans fresh via `gha-aws-iac-apply`,
  then applies — unless the plan contains **any destroy**, in which case the
  job fails and waits for a human. Destructive changes are applied
  deliberately from the console shell; the workflow never does them.

The apply role is AdministratorAccess assumable only from this repo's cp-1
branch — the trust policy and the destroy gate are the guards, not the policy
document. No AWS keys are stored on GitHub. The nightly drift check (Kuma 40) stays as
the verification half of the loop.

## Phases

| # | Scope | Status |
|---|---|---|
| 1 | State bucket | **applied** |
| 2 | VPC, subnets, IGW, routing, SGs, EIP | **applied** |
| 3 | S3 buckets + the IAM users behind the data pipelines | **applied** |
| 4 | Live IAM (roles, policies, admin user) | **applied** |
| 5 | Route53 `shrt.example` + CloudFront + ACM (us-east-1) | **applied** |
| 6 | EC2 instance, 5 Lambdas, EventBridge, SNS sub | **applied** |

One phase per PR. `tofu plan` must be clean before starting the next.

For phases 3–6, draft the HCL rather than hand-writing it:

```sh
# add import blocks with no matching resource, then:
tofu plan -generate-config-out=generated.tf
```

Review and fold `generated.tf` into real files, then delete it — it is
gitignored so it cannot be committed raw.

### Phase 4 note

Imported **as-is, including the dead parts**, on purpose — doing the import and
the cleanup together makes "I broke it" and "the import was wrong"
indistinguishable. `live/iam.tf` ends with a CLEANUP INVENTORY listing what has
no consumer; deleting it is the next commit, not this one.

What is actually live: `RoleAws` (the EC2 instance), `RoleBackup` (two snapshot
lambdas), `RoleCloudFrontIps`, `short_url_lambda_iam` (the shrt.example lambdas), the
`ludorl82` user, and the phase 3 pipeline users. Everything else has no
consumer.

Two findings worth acting on rather than filing:

- **`RoleAdmin` and `RoleOrchestre` both carry `AdministratorAccess` and both
  have EC2 instance profiles.** Nothing uses them, but anything that could
  attach an instance profile to an instance would get full account access.
- **The `administrateurs` group grants `AdministratorAccess` and has zero
  members.** Adding a user to it is a one-step path to full access.

Also inventoried: three policies attached to the *live* `RoleAws` reference
things that no longer exist — a `tpp-numeriseur` bucket, hosted zone
`Z2JK7DWF2FL0X9` (confirmed `NoSuchHostedZone`), and volume
`vol-0aaaaaaaaaaaaaaa2`. Those want detaching, not deleting the role.

## Finishing the phase 4 cleanup

The dead IAM was adopted (`31185bd`) and then removed from the config. The
managed-policy **detachments are already done** — including the two
`AdministratorAccess` grants on `RoleAdmin` and `RoleOrchestre`, which was the
part that actually mattered.

The objects themselves still exist in AWS and are no longer described by any
config, so finish with:

```sh
# instance profiles must lose their role before they can be deleted
for r in ecsInstanceRole RoleAdmin RoleOrchestre RoleBastion \
         RolePorteCles RoleSonde RoleS3Admin; do
  aws iam remove-role-from-instance-profile --instance-profile-name "$r" --role-name "$r"
  aws iam delete-instance-profile --instance-profile-name "$r"
done

for r in ecsInstanceRole RoleAdmin RoleOrchestre RoleBastion \
         RolePorteCles RoleSonde RoleS3Admin RoleGestionSSM; do
  aws iam delete-role --role-name "$r"
done

A=arn:aws:iam::123456789012:policy
for p in policygen-201710221013 policygen-201711011046 policygen-201711011810 \
         strategie-portecles-1 terraform-policy; do
  aws iam delete-policy --policy-arn "$A/$p"
done
aws iam delete-policy --policy-arn "$A/service-role/AWSLambdaBasicExecutionRole-b4e12542-251b-4606-b0ab-56fad753a3b9"

aws iam detach-group-policy --group-name administrateurs \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
aws iam delete-group --group-name administrateurs
```

Verify with `aws iam get-account-authorization-details` — what remains should
match `live/iam.tf` plus `live/iam-pipelines.tf` exactly.

If any of this turns out to have been a mistake, every deleted object is
defined in commit `31185bd`; `git show 31185bd:live/iam.tf` has the lot.

### Still attached to the live RoleAws

Three policies reference resources that no longer exist and could be detached
and deleted separately — deliberately not bundled above, because unlike the
rest this touches a role that is in use:

```sh
for p in tpp-numeriseur tpp-numeriseur-route53 StrategieDocsNumeriseur; do
  aws iam detach-role-policy --role-name RoleAws --policy-arn "$A/$p"
  aws iam delete-policy --policy-arn "$A/$p"
done
```

They grant nothing reachable (a bucket, a hosted zone and a volume that are all
gone), so this is low risk — but remove them from `live/iam.tf` in the same
commit if you do it.

## The numeriseur Lambda

`live/numeriseur.tf` plus `live/numeriseur/`. It replaced the SFTPGo action
hook, which is what allowed that workload to go back to the stock
`drakkan/sftpgo` image.

**Its code IS managed here**, unlike the three legacy functions in
`lambdas.tf`. It follows the `deadman` pattern, with one addition: Pillow is a
binary dependency, so the package is assembled by `live/numeriseur/build.sh`
before tofu runs. Both CI workflows call it; locally you must too.

```sh
cd live && ./numeriseur/build.sh && tofu plan
```

`build.sh` normalises permissions before `archive_file` sees the directory. That
is not tidiness. `archive_file` normalises mtimes but bakes each file's
permission bits into the archive, so the package hash depends on the umask of
whoever ran pip — see the cleanup note below for what that costs.

### The secret

`numeriseur/google-drive` is created by tofu; its **value is not**. Populate it
with `scripts/google-oauth-setup.py`, once per Drive account:

```sh
./scripts/google-oauth-setup.py --account ludo
./scripts/google-oauth-setup.py --account lea    # needs its owner at the browser
```

It merges rather than replaces, so authorizing `lea` later does not clobber
`ludo`. Resulting shape:

```json
{
  "client_id": "...",
  "client_secret": "...",
  "accounts": {
    "ludo": {
      "refresh_token": "...",
      "folders": {"documents": "<folder id>", "photos": "<folder id>"}
    }
  }
}
```

An account absent from `accounts` is not an error: the function logs that the
destination has no credentials yet and leaves the object in S3, to be replayed
later. That is the expected state while the two accounts are rotated one at a
time.

**Publish the OAuth consent screen to production before running this.** A
client left in "Testing" status is issued refresh tokens that expire after
**7 days**, and the pipeline would stop a week later with no obvious cause.
For `drive.file` publishing is free and immediate — no verification.

**The scope is `drive.file`, and that is a real constraint, not a preference.**
It grants per-file access only to what the app itself created. Full `drive`
would lift that, but it is a *restricted* scope: publishing to production then
requires Google verification plus a paid annual CASA assessment, and not
publishing means the 7-day expiry above. rclone only avoided all this because
its shared, already-verified client was doing the asking — the arrangement
being retired here.

**The app cannot use your existing `Numerisations`/`Photos` folders, ever.**
They were created by rclone's client, so `drive.file` cannot see them, and
there is no way to hand them over — not by sharing, not by name lookup. The
script creates its own destinations and records the ids.

**The trap this produces bit a real cutover on 2026-08-05.** The app's view of
Drive is a strict *subset* of yours, so a name lookup that returns
`Numerisations` has not found your folder — it has found one the app created
earlier. The script said "reusing existing folder", that was read as "found the
pre-existing one", and scans were delivered to a second identically-named
folder for a while before anyone noticed. Two lessons, both now built in: the
script names the origin of a folder explicitly, and

```sh
./scripts/google-oauth-setup.py --account ludo --inspect
```

lists every folder the app can actually see with `createdTime` and parents.
**Trust that, not a name.** `--set-folder documents <id>` repoints a destination
without re-authorizing, and refuses an id the app cannot reach.

### Replaying

S3 is the queue. Anything not delivered — a destination whose credentials did
not exist yet, or a failure parked on the DLQ — is replayed by invoking the
function directly:

```sh
aws lambda invoke --function-name numeriseur-processor \
  --payload '{"backfill":{"prefix":"ludoetlea/","accounts":["lea"]}}' \
  --cli-binary-format raw-in-base64-out /dev/stdout
```

`accounts` restricts delivery, so replaying a shared prefix after one account
is rotated does not push a second copy to the account that already got it.
Backfill skips files already present in the target folder, so it is safe to run
twice.

## Known cleanup, not yet done

- **`deadman`'s package hash depends on your umask.** Planning from the console
  shell proposes a `source_code_hash` update to `aws_lambda_function.deadman`
  even though the deployed code is byte-identical to the repo (verified by
  downloading the deployed zip and diffing it). CI does not see the change.

  `archive_file` normalises mtimes but writes each file's permission bits into
  the archive, and git tracks only the executable bit — so the mode comes from
  the umask of whoever checked out. The GitHub runner's 022 gives `0644` and
  matches what was applied; the console shell's 002 gives `0664` and does not.
  Confirmed by isolating the two: `touch -t 200001010000` on the source changes
  nothing, `chmod 664` alone reproduces the diff.

  Harmless in that an apply re-uploads identical code, but it is a permanent
  phantom diff for anyone planning from a 002-umask host — including the
  nightly drift check, depending on where it runs. The fix is the one
  `numeriseur` already uses: normalise modes before archiving. For `deadman`
  that means copying the source file into a build directory and `chmod 644`
  there, rather than zipping it in place.

- **`sg-0aaaaaaaaaaaaaaa3` (`launch-wizard-1`)** — attached to nothing, allows
  SSH from `0.0.0.0/0` and `::/0`. Deliberately not imported. Delete it:
  ```sh
  aws ec2 delete-security-group --region ca-central-1 --group-id sg-0aaaaaaaaaaaaaaa3
  ```
- **Stale AMIs** — `aws-example-com-20240510` and
  `aws-example-com-202405071827` are from 2024 and almost certainly dead.
  `cp-1-example-com-preswap-20260721` is the rollback for the deleted
  cp-1 root volume; keep until you are confident, then deregister.

## Removed 2026-07-25

Residue of the decommissioned `cp-1` node, deleted before the import so it
would not be codified:

- `vol-0aaaaaaaaaaaaaaa1` (64 GB, unattached; data preserved in
  `ami-0089a2297c7c4da2f`)
- `eipalloc-0aaaaaaaaaaaaaaa1` / `192.0.2.7`
- `eni-0aaaaaaaaaaaaaaa1` / `203.0.113.130`

## Drift detection

Once phase 2 is applied, wire a scheduled `tofu plan -detailed-exitcode` into
Cronicle; exit code 2 means drift. Route the alert through the existing ntfy /
Uptime Kuma push setup rather than adding new monitoring.

## Credentials

Plans currently run as the `ludorl82` IAM user. Before wiring any automation,
create a dedicated `iac` role and assume it — do not put long-lived admin keys
in CI.

CI smoke-tested 2026-07-30: plan-on-PR comment, OIDC role assumption, destroy
gate verified in the sibling cloudflare-iac repo with a live record.
