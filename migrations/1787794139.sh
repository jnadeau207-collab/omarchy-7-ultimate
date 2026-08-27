echo "Enable the per-user Fabric service with version and state safeguards"

fabric_service="$OMARCHY_PATH/bin/omarchy-fabric-service"

if [[ -x $fabric_service ]]; then
  "$fabric_service" install
else
  echo "Fabric lifecycle helper is missing: $fabric_service" >&2
  false
fi
