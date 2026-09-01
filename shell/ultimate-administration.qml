//@ pragma AppId org.omarchy.Administration
//@ pragma ShellId omarchy-ultimate-administration
//@ pragma DataDir $BASE/omarchy/administration
//@ pragma StateDir $BASE/omarchy/administration
//@ pragma CacheDir $BASE/omarchy/administration

import QtQuick
import Quickshell
import "apps/shared" as Shared

Shared.ProductAppHost {
  applicationId: "administration"
  appId: "org.omarchy.Administration"
  displayName: "Administration"
  ipcTarget: "omarchy.administration"
  routeCatalogPath: "apps/ultimate-administration/routes-v1.json"
  fabricIdentity: "omarchy-administration"
  fabricAllowedMethods: ["provider.catalog", "provider.read"]
  applicationSourcePath: "apps/ultimate-administration/AdministrationApplication.qml"
}
