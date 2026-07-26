# Sanitized snapshot

This is a **sanitized, read-only snapshot** of the private OpenTofu repository
that manages my AWS account, published as a companion to the
infrastructure-as-code writing on [labodeludo.dev](https://labodeludo.dev/).

It is the third of three: [nixos-iac-public](https://github.com/ludorl82/nixos-iac-public)
holds the machines, [k3s-iac-public](https://github.com/ludorl82/k3s-iac-public)
holds the workloads, this one holds the account underneath the one cloud node.

## What is fictional

The AWS account id, every account-scoped resource id (`vpc-`, `subnet-`,
`sg-`, `i-`, `vol-`, `eipalloc-`, …), every domain name, every IP address
(RFC 5737 / RFC 3849), and every code hash. Addresses keep their last octet,
so `198.51.100.7` is the machine that really ends in `.7`.

## What is real

Every comment, and every resource, IAM, bucket and Lambda **name**. That is
deliberate: the comments are the point. The reason `description` is set
verbatim on five IAM policies, the reason `aws_default_route_table` imports
by VPC id, the reason the scans bucket has a create-new-first rule written
above it — those are the parts worth reading, and they are all real.

Published to be read, not deployed. `tofu plan` against this will do nothing
useful, and the repository is not kept in sync with the private original.
