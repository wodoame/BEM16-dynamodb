# DynamoDB "Music" Table — AWS SAM + GitHub Actions Pipelines

Deploys a DynamoDB `Music` table via AWS SAM, with two independent, environment-scoped
GitHub Actions pipelines (dev / prod), each using its own dedicated S3 artifacts bucket
and IAM role assumed via GitHub OIDC (no static AWS keys stored in GitHub).

## Table design

| | |
|---|---|
| Partition key | `Artist` (String) |
| Sort key | `Song` (String) |
| Additional attributes | `Album` (String), `Genre` (String) |
| GSI 1 | `Album-Index` — HASH `Album`, RANGE `Song` |
| GSI 2 | `Genre-Index` — HASH `Genre`, RANGE `Artist` |
| Billing mode | `PAY_PER_REQUEST` (On-Demand) |
| Table class | `STANDARD_INFREQUENT_ACCESS` (non-default) |

`Environment` (`dev`/`prod`) is a stack parameter that namespaces the table name
(`Music-dev` / `Music-prod`) and, in `prod`, additionally enables point-in-time
recovery. Both environments use `DeletionPolicy: Delete` — the table is removed
if the stack or resource is deleted.

Any other item attribute (e.g. `Year`, `Price`) can be added freely at insert time —
DynamoDB only requires attributes that are used as table or index keys to be declared
in the schema.

## One-time setup

### 1. Prerequisites

- AWS account with permissions to create IAM roles, an OIDC provider, S3 buckets, and DynamoDB tables
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) installed and logged in (`aws sts get-caller-identity` should succeed)
- This repository pushed to GitHub, with a `main` branch (prod) and a `develop` branch (dev)

### 2. Bootstrap per-environment pipeline resources

Instead of the generic `sam pipeline bootstrap` CLI (which auto-generates
hard-to-read resource names), this repo has two hand-written CloudFormation
templates under `pipeline/` that create the same category of resources with
**dedicated, easy-to-remember names per environment**:

- `pipeline/oidc-provider.yaml` — the GitHub Actions OIDC identity provider.
  Account-wide; deploy **once**.
- `pipeline/pipeline-resources.yaml` — per stage: a dedicated S3 artifacts
  bucket, a `CloudFormationExecutionRole` scoped to only the `Music-<env>`
  table, and a `DeployerRole` trusted via OIDC and scoped to only that
  stage's stack + bucket. Deploy **once per stage** (`dev`, `prod`).

```bash
# One-time, account-wide
aws cloudformation deploy \
  --template-file pipeline/oidc-provider.yaml \
  --stack-name music-table-oidc-provider \
  --capabilities CAPABILITY_IAM

OIDC_ARN=$(aws cloudformation describe-stacks --stack-name music-table-oidc-provider \
  --query "Stacks[0].Outputs[?OutputKey=='OidcProviderArn'].OutputValue" --output text)

# Per stage
aws cloudformation deploy \
  --template-file pipeline/pipeline-resources.yaml \
  --stack-name music-table-pipeline-dev \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides Environment=dev GitHubOrg=<org> GitHubRepo=<repo> \
    GitHubEnvironmentName=dev OidcProviderArn="$OIDC_ARN"

aws cloudformation deploy \
  --template-file pipeline/pipeline-resources.yaml \
  --stack-name music-table-pipeline-prod \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides Environment=prod GitHubOrg=<org> GitHubRepo=<repo> \
    GitHubEnvironmentName=production OidcProviderArn="$OIDC_ARN"
```
If you fork this repo or move to a different AWS account, re-run the commands
above with your own `GitHubOrg`/`GitHubRepo` and read the new values with
`aws cloudformation describe-stacks --stack-name music-table-pipeline-<env> --query "Stacks[0].Outputs"`.

### 3. Configure GitHub Environments, secrets, and variables

In the GitHub repo: **Settings → Environments**, create two environments named
`dev` and `production` (names must match the `environment:` key used in the two
workflow files, and the `GitHubEnvironmentName` each role's trust policy was
scoped to). In each, add the following — role ARNs as **Environment secrets**,
bucket name as an **Environment variable** (it isn't sensitive). The AWS region
is hardcoded in each workflow's `env.AWS_REGION` rather than pulled from a
variable.

Optional but recommended: on the `production` environment, add required reviewers
so prod deploys need manual approval before running.

### 4. samconfig.toml (for local deploys)

`samconfig.toml` is already filled in with the bucket names and region above,
so `sam deploy --config-env dev` (or `prod`) works from your machine too, in
addition to CI — though it still requires the AWS SAM CLI to be installed
locally (only the AWS CLI was needed for the bootstrap step above).

## Deploying

- Push to `develop` → triggers `.github/workflows/deploy-dev.yml` → deploys stack
  `music-table-dev`
- Push to `main` → triggers `.github/workflows/deploy-prod.yml` → deploys stack
  `music-table-prod`
- Both workflows also support manual runs via the **Actions** tab (`workflow_dispatch`)

Each pipeline only builds and deploys its own environment — there is no shared,
auto-generated multi-stage workflow.

## Verifying in the AWS Console

1. Open **DynamoDB → Tables** and select `Music-dev` or `Music-prod`.
2. Under **Table details**, confirm capacity mode is **On-demand** and table class is
   **DynamoDB Standard-IA**.
3. Go to **Explore table items → Create item** and insert a few items, e.g.:

   | Artist | Song | Album | Genre | Year |
   |---|---|---|---|---|
   | No Doubt | Just a Girl | Tragic Kingdom | Rock | 1995 |
   | No Doubt | Spiderwebs | Tragic Kingdom | Rock | 1995 |
   | Nirvana | Come As You Are | Nevermind | Grunge | 1991 |

4. Query the base table by `Artist` (+ optional `Song`).
5. Under **Indexes**, select `Album-Index` and query by `Album` (e.g. all
   songs on *Tragic Kingdom*), then select `Genre-Index` and query by `Genre`.
