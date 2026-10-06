#!/usr/bin/env bash
set -euo pipefail
umask 077

: "${AWS_REGION:?}" "${PARAMETER_NAME:?}" "${KUBECONFIG_PATH:?}" "${EXPECTED_SERVER:?}"
for tool in aws kubectl; do
  command -v "$tool" >/dev/null || { echo "$tool is required." >&2; exit 1; }
done

mkdir -p "$(dirname "$KUBECONFIG_PATH")"
candidate=$(mktemp "${KUBECONFIG_PATH}.XXXXXX")
error_file=$(mktemp "${KUBECONFIG_PATH}.error.XXXXXX")
trap 'rm -f "$candidate" "$error_file"' EXIT
export AWS_PAGER=""

# EC2 creation finishes before cloud-init publishes the parameter. Also reject
# a parameter left behind by an older instance until the new master uploads it.
echo "Waiting for $PARAMETER_NAME in $AWS_REGION and the Kubernetes API..."
for ((attempt = 1; attempt <= 90; attempt++)); do
  if aws ssm get-parameter --name "$PARAMETER_NAME" --with-decryption \
    --region "$AWS_REGION" --query 'Parameter.Value' --output text \
    --cli-connect-timeout 5 --cli-read-timeout 10 >"$candidate" 2>"$error_file"; then
    server=$(kubectl --kubeconfig "$candidate" config view --minify \
      -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null) || server=""
    if [[ "$server" == "$EXPECTED_SERVER" ]] && \
      kubectl --kubeconfig "$candidate" --request-timeout=5s \
        get --raw=/readyz >/dev/null 2>&1; then
      context=$(kubectl --kubeconfig "$candidate" config current-context)
      kubectl --kubeconfig "$candidate" config use-context "$context" >/dev/null
      chmod 600 "$candidate"
      mv -f "$candidate" "$KUBECONFIG_PATH"
      echo "Kubeconfig saved to $KUBECONFIG_PATH; Kubernetes API is ready."
      exit 0
    fi
  else
    error_message=$(cat "$error_file")
    if [[ "$error_message" == *"ParameterNotFound"* ]]; then
      if (( attempt == 1 || attempt % 6 == 0 )); then
        echo "Master has not published the kubeconfig yet; waiting for cloud-init (attempt $attempt/90)."
      fi
    elif [[ "$error_message" == *"AccessDenied"* || "$error_message" == *"UnrecognizedClient"* || "$error_message" == *"ExpiredToken"* ]]; then
      cat "$error_file" >&2
      exit 1
    else
      cat "$error_file" >&2
    fi
  fi
  sleep 10
done

echo "Timed out waiting for $PARAMETER_NAME in $AWS_REGION. On the master, check: sudo cloud-init status --long; sudo tail -n 100 /var/log/cloud-init-output.log. Also check the local AWS account, SSM/KMS permissions, and TCP 6443 access from ssh_cidr." >&2
exit 1
