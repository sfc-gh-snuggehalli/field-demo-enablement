#!/usr/bin/env bash
# ACME Assist -> Snowpark Container Services. Not run automatically; run it yourself after
# snowflake/spcs/setup.sql, with a connection whose role is ACME_APP_ROLE:
#   CONNECTION=<conn> bash snowflake/spcs/deploy.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

CONNECTION="${CONNECTION:?set CONNECTION to a snow CLI connection using ACME_APP_ROLE}"
SERVICE="ACME_ASSIST_DEMO.APP.ACME_ASSIST_SERVICE"
POOL="ACME_ASSIST_POOL"
TAG="${TAG:-$(date +%Y%m%d%H%M%S)}"

sf() { snow sql -c "$CONNECTION" --format JSON -q "$1"; }

REPO_URL=$(sf "SHOW IMAGE REPOSITORIES LIKE 'ACME_REPO' IN SCHEMA ACME_ASSIST_DEMO.APP" | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["repository_url"])')
IMAGE="$REPO_URL/acme-assist:$TAG"

echo "1/4 docker build --platform linux/amd64 -> $IMAGE"
docker build --platform linux/amd64 -t "$IMAGE" .

echo "2/4 registry login + push"
snow spcs image-registry login -c "$CONNECTION"
docker push "$IMAGE"

echo "3/4 create or alter service"
SPEC=$(sed "s#\${IMAGE}#$IMAGE#" snowflake/spcs/service.yaml)
if sf "SHOW SERVICES LIKE 'ACME_ASSIST_SERVICE' IN SCHEMA ACME_ASSIST_DEMO.APP" | grep -q ACME_ASSIST_SERVICE; then
  sf "ALTER SERVICE $SERVICE FROM SPECIFICATION \$\$
$SPEC
\$\$"
else
  sf "CREATE SERVICE $SERVICE IN COMPUTE POOL $POOL MIN_INSTANCES = 1 MAX_INSTANCES = 1 QUERY_WAREHOUSE = ACME_ASSIST_WH FROM SPECIFICATION \$\$
$SPEC
\$\$"
fi

echo "4/4 ingress URL (may take a minute to provision)"
for _ in $(seq 1 30); do
  URL=$(sf "SHOW ENDPOINTS IN SERVICE $SERVICE" | python3 -c 'import json,sys; r=json.load(sys.stdin); print(next((e["ingress_url"] for e in r if e.get("ingress_url") and "provisioning" not in e["ingress_url"].lower()), ""))')
  if [ -n "$URL" ]; then echo "https://$URL"; exit 0; fi
  sleep 10
done
echo "Endpoint still provisioning; re-run: SHOW ENDPOINTS IN SERVICE $SERVICE"
