#!/bin/dumb-init /bin/sh

rm -f /opt/healthcheck

#copypasta from upstream docker-entrypoint.sh

# VAULT_CONFIG_DIR isn't exposed as a volume but you can compose additional
# config files in there if you use this image as a base, or use
# VAULT_LOCAL_CONFIG below.
VAULT_CONFIG_DIR=/vault/config

VAULT_SECRETS_FILE=${VAULT_SECRETS_FILE:-"/opt/secrets.json"}
VAULT_APP_ID_FILE=${VAULT_APP_ID_FILE:-"/opt/app-id.json"}

# You can also set the VAULT_LOCAL_CONFIG environment variable to pass some
# Vault configuration JSON without having to bind any volumes.
if [ -n "$VAULT_LOCAL_CONFIG" ]; then
    echo "$VAULT_LOCAL_CONFIG" > "$VAULT_CONFIG_DIR/local.json"
fi

vault server \
        -config="$VAULT_CONFIG_DIR" \
        -dev-root-token-id="${VAULT_DEV_ROOT_TOKEN_ID:-root}" \
        -dev-listen-address="${VAULT_DEV_LISTEN_ADDRESS:-"0.0.0.0:8200"}" \
        -dev "$@" &

# end copypasta

sleep 1 # wait for Vault to come up

# parse JSON array, populate Vault
if [[ -f "$VAULT_SECRETS_FILE" ]]; then
  for path in $(jq -r 'keys[]' < "$VAULT_SECRETS_FILE"); do
    jq -rj ".\"${path}\"" < "$VAULT_SECRETS_FILE" > /tmp/value
    echo "writing value to ${path}"
    vault write "${path}" "value=@/tmp/value"
    rm -f /tmp/value
  done
else
  echo "$VAULT_SECRETS_FILE not found, skipping"
fi

# Optionally install the app id backend.
if [ -n "$VAULT_USE_APP_ID" ]; then
    vault auth-enable app-id

    if [[ -f "$VAULT_APP_ID_FILE" ]]; then
	for appID in $(jq -rc '.[]' < "$VAULT_APP_ID_FILE"); do
	    name=$(echo "$appID" | jq -r ".name")
	    policy=$(echo "$appID" | jq -r ".policy")
	    echo "creating AppID policy with user ID $name for policy $policy"
	    vault write auth/app-id/map/app-id/$name value=$policy display_name=$name
	done
    fi
fi

# docker healthcheck
touch /opt/healthcheck

# block forever
tail -f /dev/null
