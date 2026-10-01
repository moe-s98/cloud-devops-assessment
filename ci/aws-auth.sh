#!/bin/sh
# Usage: . ci/aws-auth.sh plan|deploy
#
# Turns the CI user's long-lived key (which can ONLY call sts:AssumeRole) into
# a 1-hour role session via a shared-config profile. Works for both the AWS
# CLI and Terraform. The key never appears in env vars that SDKs would pick up
# directly, and never in job logs (variables are masked).
set -eu
role="$1"
case "$role" in
  plan)   key="${AWS_PLAN_ACCESS_KEY_ID:?missing}";   secret="${AWS_PLAN_SECRET_ACCESS_KEY:?missing}" ;;
  deploy) key="${AWS_DEPLOY_ACCESS_KEY_ID:?missing (protected variable: only on protected branches)}"
          secret="${AWS_DEPLOY_SECRET_ACCESS_KEY:?missing}" ;;
  *) echo "usage: . ci/aws-auth.sh plan|deploy" >&2; return 1 ;;
esac

mkdir -p "$HOME/.aws"
umask 077
cat > "$HOME/.aws/credentials" <<CREDS
[ci-base]
aws_access_key_id = ${key}
aws_secret_access_key = ${secret}
CREDS
cat > "$HOME/.aws/config" <<CONF
[profile ci]
role_arn = arn:aws:iam::${AWS_ACCOUNT_ID:?missing}:role/guestbook-ci-${role}
source_profile = ci-base
role_session_name = gitlab-${CI_PROJECT_ID:-local}-${CI_PIPELINE_ID:-0}-${CI_JOB_ID:-0}
duration_seconds = 3600
region = ${AWS_REGION:-eu-north-1}
CONF
unset key secret
export AWS_PROFILE=ci
echo "AWS: using role guestbook-ci-${role} (1h session)"
