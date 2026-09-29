# aws-terraform-infra

Serverless AWS infrastructure, fully automated with Terraform: a public HTTPS API backed by Lambda and DynamoDB, deployed through a zero-static-credential CI/CD pipeline, monitored end-to-end, and designed to run at **$0/month** using AWS's Always Free tier only.

**Live endpoint:** `https://dz4cbpzyxt5dux7qbyvg474otu0pkyww.lambda-url.eu-west-3.on.aws/`

---

## Architecture

```
                              ┌─────────────────────────────────────────┐
                              │                Internet                 │
                              └───────────────────┬───────────────────┬─┘
                                                   │                   │
                                          HTTPS (Function URL)         │ IGW (unused by app;
                                                   │                   │ public subnets kept
                                                   ▼                   │ for future use)
┌──────────────────────────────────────────────────────────────────┐  │
│  VPC (10.x.0.0/16) — eu-west-3                                    │  │
│                                                                    │  │
│   ┌────────────────────────┐        ┌────────────────────────┐    │  │
│   │  Public Subnet (AZ-a)   │        │  Public Subnet (AZ-b)   │◄───┘
│   │  auto-assign IP: off    │        │  auto-assign IP: off    │
│   └────────────────────────┘        └────────────────────────┘
│                                                                    │
│   ┌────────────────────────┐        ┌────────────────────────┐   │
│   │ Private Subnet (AZ-a)   │        │ Private Subnet (AZ-b)   │   │
│   │                         │        │                         │   │
│   │   ┌─────────────────────┴────────┴─────────────────────┐  │   │
│   │   │  Lambda: aws-terraform-infra-app  (nodejs22.x)      │  │   │
│   │   │  SG: egress-only, no inbound                        │  │   │
│   │   └───────────────────┬──────────────────────────────┬─┘  │   │
│   └───────────────────────┼──────────────────────────────┼────┘   │
│                            │                              │        │
│                    VPC Gateway Endpoint            VPC Gateway     │
│                        (S3)                     Endpoint (DynamoDB)│
│                            │                              │        │
│   Default SG: locked down, unused by any resource                 │
└────────────────────────────┼──────────────────────────────┼───────┘
                              │                              │
                              ▼                              ▼
                    ┌───────────────────┐        ┌───────────────────────┐
                    │  S3 (state only,   │        │  DynamoDB              │
                    │  not app data)     │        │  aws-terraform-infra-  │
                    └───────────────────┘        │  app-table (5/5 WCU/RCU)│
                                                   └───────────────────────┘

CloudWatch Alarms (Lambda Errors, Lambda Throttles, DynamoDB Throttles)
        │
        ▼
   SNS Topic (KMS-encrypted, AWS-managed key) ──► Email subscription
```

No NAT Gateway, no ALB, no API Gateway, no EC2 — every hop that costs money hourly has been deliberately designed out.

---

## Module tree

```
aws-terraform-infra/
├── bootstrap.tf              # S3 state bucket + DynamoDB lock table (bootstrapped locally)
├── vpc.tf                    # wires modules/vpc
├── compute.tf                # wires modules/compute
├── database.tf               # wires modules/database
├── monitoring.tf              # wires modules/monitoring
├── oidc.tf                   # GitHub OIDC provider + CI IAM role/policy
├── locals.tf                 # common tags
├── versions.tf                # provider version constraints
├── variables.tf               # alert_email (no default — sourced from tfvars/CI secret)
├── .checkov.yaml              # project-wide accepted-risk skip list
├── .github/
│   ├── workflows/terraform.yml   # guard → fmt/validate/plan-on-PR → apply-on-merge
│   └── dependabot.yml            # terraform + github-actions, weekly
└── modules/
    ├── vpc/          # 2 public + 2 private subnets, IGW, Gateway Endpoints, default SG lockdown
    ├── compute/      # Lambda, execution role, security group, Function URL
    ├── database/     # DynamoDB app table
    └── monitoring/   # SNS topic, CloudWatch alarms, dashboard
```

---

## Security decisions

| Decision | Chosen | Rejected | Why |
|---|---|---|---|
| Compute | Lambda | EC2 | Zero idle cost, no patching or AMI management, scales to zero between requests |
| Database | DynamoDB (provisioned) | RDS | RDS's smallest instance still bills hourly with no permanent free tier; DynamoDB's provisioned mode is Always Free within a fixed 25 RCU/25 WCU pool |
| Private-subnet AWS access | VPC Gateway Endpoints (S3, DynamoDB) | NAT Gateway | NAT Gateway bills ~$32+/month with no free tier; Gateway Endpoints are Always Free and cover the only two AWS services this Lambda actually needs to reach |
| DynamoDB billing mode | Provisioned, fixed capacity | On-demand | Only provisioned mode is Always Free; on-demand bills per request with no permanent free allowance |
| CI/CD authentication | OIDC (GitHub → AWS STS) | Static IAM access keys as GitHub secrets | No long-lived credentials stored anywhere; short-lived tokens scoped to `repo:amine-hassoun/aws-terraform-infra:*` — no other repo can assume this role |
| CI IAM policy shape | Narrow Allow list, no explicit Deny | Broad Allow + explicit Deny (as used for the personal IAM user) | The policy's Allow list never grants EC2/NAT/ALB/RDS/EKS actions in the first place — nothing to deny, since it was never grantable |
| Public API entry point | Lambda Function URL | API Gateway | No API Gateway needed for a single public endpoint with no routing/auth requirements; Function URL is free and sufficient for this use case |

---

## Cost — confirmed $0/month

| Service | Usage here | Always Free? |
|---|---|---|
| Lambda | 1 function, low invocation volume | Yes, permanently |
| DynamoDB | 1 table, 5/5 RCU/WCU (6/25 combined with the lock table) | Yes, provisioned mode only |
| CloudWatch | 3 alarms (10 free), 1 dashboard (3 free) | Yes |
| SNS | Near-zero monthly volume, AWS-managed KMS key (no flat fee) | Yes |
| VPC Gateway Endpoints | S3 + DynamoDB | Yes |
| S3 (state file) | One small `.tfstate` object, versioned | **Not** Always Free — a fraction of a cent/month even at full price; a lifecycle rule keeps old versions and stalled uploads from accumulating indefinitely |

No NAT Gateway, ALB, RDS, EC2, or EKS exist anywhere in this design — three separate safety nets (an IAM Deny policy on the hands-on IAM user, a CI static guard that greps every `.tf` file for forbidden resource types, and this architecture itself) keep it that way.

---

## State bootstrap sequence

Terraform's state backend can't manage itself — it has to exist before Terraform can use it as a backend. The order that broke this circularity:

1. `bootstrap.tf`'s S3 bucket + DynamoDB lock table applied with **local** state.
2. Backend block uncommented, `terraform init -migrate-state` moves state into S3.
3. `oidc.tf`'s IAM OIDC provider + CI role applied **locally** (with the personal IAM user) — CI can't create the very role it needs to authenticate as.
4. `terraform output github_actions_role_arn` copied into two separate GitHub secret stores: **Actions secrets** (for normal PRs) and **Dependabot secrets** (a GitHub security restriction blocks Dependabot-triggered workflow runs from reading regular Actions secrets).
5. From here on: every change flows through a PR (`guard` → `fmt`/`validate`/`plan` posts a bot comment) → merge to `main` (`guard` → `apply`).

---

## CI/CD pipeline

- **OIDC, not static keys** — GitHub's OIDC token is exchanged for short-lived AWS credentials via `aws-actions/configure-aws-credentials`, scoped to a role only this repo's workflows can assume.
- **Cost-safety guard** — a grep-based check fails the build if any forbidden resource type (`aws_nat_gateway`, `aws_instance`, `aws_db_instance`, etc.) appears in any `.tf` file, before Terraform even runs.
- **Plan on PR, apply on merge** — every PR gets a bot-posted plan comment; only a merge to `main` actually applies. A shared `concurrency` group (`terraform-state`) serializes `plan`/`apply` jobs so simultaneous PRs never race for the same DynamoDB state lock.
- **checkov** — static analysis on every PR, hard-fails on any new finding (see below).
- **Dependabot** — weekly scans for `terraform` and `github-actions` ecosystem updates, running through the exact same guard/plan/checkov gates as any other PR.

---

## checkov — static analysis

Initial discovery scan: **57 passed, 28 failed**. Final state: **62 passed, 0 failed**, hard-fail enabled.

**5 findings fixed for real:**
- Lambda reserved concurrency — attempted, but this AWS account's total Lambda concurrency limit is only 10, and AWS reserves all 10 as an account-wide unreserved floor; no reservation was possible, so this was reverted and formally accepted instead.
- SNS topic encryption via the AWS-managed key `alias/aws/sns` (no flat monthly fee, unlike a customer-managed CMK).
- Public subnets' auto-assign-public-IP disabled.
- The VPC's unused default security group locked down.
- An S3 lifecycle rule added to the state bucket (expire noncurrent versions after 90 days, abort stalled multipart uploads after 7).

**22 findings formally accepted**, documented in `.checkov.yaml` (project-wide categories: DynamoDB CMK/PITR/autoscaling, Lambda X-Ray/DLQ/code-signing, public Function URL, S3 logging/replication/notifications) and as 4 inline `#checkov:skip` comments inside the CI role's IAM policy block (privilege-escalation/wildcard-resource findings — checkov's graph-based IAM checks only honor skip comments placed *inside* the flagged resource's own scope, not immediately above it).

---

## Lessons learned

- **A Lambda Function URL with `AuthType: NONE` isn't enough on its own** — it needs two separate resource-policy statements: a conditioned `lambda:InvokeFunctionUrl` *and* a separate, unconditioned `lambda:InvokeFunction`. Missing the second gives a persistent 403 despite a correct-looking policy.
- **Never hardcode a named AWS CLI profile in a `backend "s3" {}` or `provider "aws" {}` block** — it only exists on the machine that created it. Credentials now resolve from the environment (`AWS_PROFILE` locally, OIDC-exchanged temp credentials in CI), so the same config file works everywhere.
- **A CI role needs more than create-time permissions** — every `plan`/`apply` fully refreshes every attribute of every managed resource, which invokes read-only Describe/Get calls the role also needs. A resource must stay fully describable for the life of the pipeline, not just creatable.
- **A brand-new AWS account's Lambda concurrency limit can be far below the commonly-cited 1,000 default** — this account's total was 10, with all 10 reserved as an unremovable account-wide floor, leaving zero room for any function-level reservation.
- **A shared Terraform state lock needs a CI `concurrency` group, not just per-branch defaults** — a batch of 6 Dependabot PRs opening simultaneously exposed this immediately, with several `plan` jobs failing on the same DynamoDB `ConditionalCheckFailedException`.
- **Dependabot-triggered workflow runs can't read regular Actions secrets** — a GitHub security precaution against a compromised dependency update exfiltrating them. Anything the pipeline needs has to be duplicated into the separate Dependabot secrets store.
- **A major dependency bump deserves the actual plan output read, not just a green check** — the AWS provider's 5.x → 6.x bump showed `No changes`, confirming it was safe, but also surfaced a real deprecation (`data.aws_region.current.name` → `.region`) fixed the same day.

---

## Certifications applied directly to this build

AWS Certified Solutions Architect – Associate (SAA-C03) · HashiCorp Certified: Terraform Associate (004) — both practice-validated, with every concept here (IAM, VPC design, Lambda/serverless, DynamoDB, Terraform state/modules/lifecycle) applied directly rather than left as multiple-choice theory.

---

## Deploy your own

```bash
git clone https://github.com/amine-hassoun/aws-terraform-infra.git
cd aws-terraform-infra

# 1. Bootstrap the state backend (local state, one-time)
terraform init
terraform apply -target=aws_s3_bucket.terraform_state -target=aws_dynamodb_table.terraform_locks

# 2. Migrate to remote state, then apply everything else
terraform init -migrate-state
export AWS_PROFILE=<your-profile>
echo 'alert_email = "you@example.com"' > terraform.tfvars
terraform apply
```

CI/CD requires its own one-time setup: apply `oidc.tf` locally, then add `AWS_GITHUB_ACTIONS_ROLE_ARN` and `ALERT_EMAIL` to both GitHub's Actions secrets and Dependabot secrets.

---

## Contact

**Amine Hassoun** — [github.com/amine-hassoun](https://github.com/amine-hassoun) · [linkedin.com/in/amine-hassoun](https://linkedin.com/in/amine-hassoun) · m.amine.hassoun@gmail.com