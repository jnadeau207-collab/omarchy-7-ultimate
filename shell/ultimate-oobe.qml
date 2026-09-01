//@ pragma AppId org.omarchy.Setup
//@ pragma ShellId omarchy-ultimate-oobe
//@ pragma DataDir $BASE/omarchy/setup
//@ pragma StateDir $BASE/omarchy/setup
//@ pragma CacheDir $BASE/omarchy/setup

import QtQuick
import Quickshell
import "apps/shared" as Shared

Shared.ProductAppHost {
  applicationId: "oobe"
  appId: "org.omarchy.Setup"
  displayName: "Set up this computer"
  ipcTarget: "omarchy.setup"
  routeCatalogPath: "apps/ultimate-oobe/routes-v1.json"
  fabricIdentity: "omarchy-setup"
  fabricAllowedMethods: ["provider.catalog", "provider.read"]
  applicationSourcePath: "apps/ultimate-oobe/SetupApplication.qml"
}
