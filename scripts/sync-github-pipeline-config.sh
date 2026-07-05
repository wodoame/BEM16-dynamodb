#!/usr/bin/env bash
# Reads the pipeline-resources CloudFormation stack outputs for each
# environment and writes them into the matching GitHub Environment as
# secrets (role ARNs) and variables (bucket name), so the deploy-dev.yml /
# deploy-prod.yml workflows have what they need.
#
# Requires: aws cli (logged in), gh cli (authenticated with repo admin
# access), jq.
#
# Usage:
#   ./scripts/sync-github-pipeline-config.sh [owner/repo]
#
# If owner/repo is omitted, it's inferred from the "origin" git remote.

set -euo pipefail

ORIGIN_URL="$(git config --get remote.origin.url)"
REPO="wodoame/BEM16-dynamodb"
REGION="${AWS_REGION:-us-east-1}"

declare -A STACK_TO_GH_ENV=(
  [music-table-pipeline-dev]=dev
  [music-table-pipeline-prod]=production
)

for cmd in aws gh jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Error: $cmd is required but not installed." >&2; exit 1; }
done

echo "Target repo: $REPO"

for stack in "${!STACK_TO_GH_ENV[@]}"; do
  gh_env="${STACK_TO_GH_ENV[$stack]}"
  echo
  echo "== $stack -> GitHub environment '$gh_env' =="

  gh api --method PUT "repos/$REPO/environments/$gh_env" >/dev/null

  outputs=$(aws cloudformation describe-stacks \
    --stack-name "$stack" \
    --region "$REGION" \
    --query "Stacks[0].Outputs" \
    --output json)

  bucket=$(jq -r '.[] | select(.OutputKey=="ArtifactsBucketName") | .OutputValue' <<<"$outputs")
  cfn_role_arn=$(jq -r '.[] | select(.OutputKey=="CloudFormationExecutionRoleArn") | .OutputValue' <<<"$outputs")
  deployer_role_arn=$(jq -r '.[] | select(.OutputKey=="DeployerRoleArn") | .OutputValue' <<<"$outputs")

  for name in bucket cfn_role_arn deployer_role_arn; do
    if [[ -z "${!name}" ]]; then
      echo "Error: could not read $name from $stack outputs." >&2
      exit 1
    fi
  done

  gh secret set PIPELINE_EXECUTION_ROLE --repo "$REPO" --env "$gh_env" --body "$deployer_role_arn"
  gh secret set CLOUDFORMATION_EXECUTION_ROLE --repo "$REPO" --env "$gh_env" --body "$cfn_role_arn"
  gh variable set ARTIFACTS_BUCKET --repo "$REPO" --env "$gh_env" --body "$bucket"

  echo "  PIPELINE_EXECUTION_ROLE (secret)      = $deployer_role_arn"
  echo "  CLOUDFORMATION_EXECUTION_ROLE (secret) = $cfn_role_arn"
  echo "  ARTIFACTS_BUCKET (variable)            = $bucket"
done

echo
echo "Done."
