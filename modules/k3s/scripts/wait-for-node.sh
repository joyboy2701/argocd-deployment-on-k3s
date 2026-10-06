#!/usr/bin/env bash
set -euo pipefail
: "${AWS_REGION:?}" "${INSTANCE_ID:?}" "${NODE_NAME:?}"
export AWS_PAGER=""

case "$NODE_NAME" in
  k3s-master|k3s-worker) ;;
  *) echo "Unsupported node name: $NODE_NAME" >&2; exit 1 ;;
esac

error_file=$(mktemp)
trap 'rm -f "$error_file"' EXIT

# SSM registration can lag behind EC2 creation. The remote check also waits
# for the master to finish publishing its token and kubeconfig before proceeding.
parameters=$(cat <<EOF
{"commands":["set -eu", "for attempt in \$(seq 1 90); do if test -f /var/lib/k3s-bootstrap-complete && /usr/local/bin/k3s kubectl wait --for=condition=Ready --timeout=5s node/$NODE_NAME; then exit 0; fi; sleep 10; done; echo 'Bootstrap/node readiness timed out; inspect cloud-init-output.log' >&2; exit 1"],"executionTimeout":["1500"]}
EOF
)

echo "Waiting for $NODE_NAME through SSM on $INSTANCE_ID..."
command_id=""
for ((attempt = 1; attempt <= 90; attempt++)); do
  if command_id=$(aws ssm send-command --region "$AWS_REGION" \
    --instance-ids "$INSTANCE_ID" --document-name AWS-RunShellScript \
    --parameters "$parameters" --query Command.CommandId --output text \
    --cli-connect-timeout 5 --cli-read-timeout 10 2>"$error_file"); then
    break
  fi
  error_message=$(cat "$error_file")
  if [[ "$error_message" != *"InvalidInstanceId"* ]]; then
    cat "$error_file" >&2
    exit 1
  fi
  sleep 10
done

if [[ -z "$command_id" ]]; then
  echo "Master did not become available in SSM; check its IAM profile, SSM agent, and network." >&2
  exit 1
fi

for ((attempt = 1; attempt <= 180; attempt++)); do
  if status=$(aws ssm get-command-invocation --region "$AWS_REGION" \
    --command-id "$command_id" --instance-id "$INSTANCE_ID" \
    --query Status --output text --cli-connect-timeout 5 --cli-read-timeout 10 \
    2>"$error_file"); then
    case "$status" in
      Success) echo "$NODE_NAME is Ready."; exit 0 ;;
      Pending|InProgress|Delayed) ;;
      *)
        aws ssm get-command-invocation --region "$AWS_REGION" \
          --command-id "$command_id" --instance-id "$INSTANCE_ID" \
          --query '{Status:Status,Error:StandardErrorContent,Output:StandardOutputContent}'
        exit 1
        ;;
    esac
  elif [[ "$(cat "$error_file")" != *"InvocationDoesNotExist"* ]]; then
    cat "$error_file" >&2
    exit 1
  fi
  sleep 10
done
echo "Timed out waiting for $NODE_NAME. Check cloud-init-output.log and the SSM command $command_id." >&2
exit 1
