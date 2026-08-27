//@ pragma AppId org.omarchy.Software
//@ pragma ShellId omarchy-ultimate-software
//@ pragma DataDir $BASE/omarchy/software
//@ pragma StateDir $BASE/omarchy/software
//@ pragma CacheDir $BASE/omarchy/software

import QtQuick
import Quickshell
import "apps/shared" as Shared

Shared.ProductAppHost {
  applicationId: "software"
  appId: "org.omarchy.Software"
  displayName: "Software Center"
  ipcTarget: "omarchy.software"
  routeCatalogPath: "apps/ultimate-software/routes-v1.json"
  fabricIdentity: "omarchy-software"
  fabricAllowedMethods: ["provider.catalog", "provider.read"]
  applicationSourcePath: "apps/ultimate-software/SoftwareApplication.qml"
}
