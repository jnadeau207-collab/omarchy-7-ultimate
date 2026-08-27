//@ pragma AppId org.omarchy.Compatibility
//@ pragma ShellId omarchy-ultimate-compatibility
//@ pragma DataDir $BASE/omarchy/compatibility
//@ pragma StateDir $BASE/omarchy/compatibility
//@ pragma CacheDir $BASE/omarchy/compatibility

import QtQuick
import Quickshell
import "apps/shared" as Shared

Shared.ProductAppHost {
  applicationId: "compatibility"
  appId: "org.omarchy.Compatibility"
  displayName: "Compatibility Center"
  ipcTarget: "omarchy.compatibility"
  routeCatalogPath: "apps/ultimate-compatibility/routes-v1.json"
  fabricIdentity: "omarchy-compatibility"
  fabricAllowedMethods: ["provider.catalog", "provider.read"]
  applicationSourcePath: "apps/ultimate-compatibility/CompatibilityApplication.qml"
}
