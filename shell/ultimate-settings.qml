//@ pragma AppId org.omarchy.Settings
//@ pragma ShellId omarchy-ultimate-settings
//@ pragma DataDir $BASE/omarchy/settings
//@ pragma StateDir $BASE/omarchy/settings
//@ pragma CacheDir $BASE/omarchy/settings

import QtQuick
import Quickshell
import "apps/shared" as Shared

Shared.ProductAppHost {
  applicationId: "settings"
  appId: "org.omarchy.Settings"
  displayName: "Settings"
  ipcTarget: "omarchy.settings"
  routeCatalogPath: "apps/ultimate-settings/routes-v1.json"
  fabricIdentity: "omarchy-settings"
  fabricAllowedMethods: ["provider.catalog", "provider.read"]
  applicationSourcePath: "apps/ultimate-settings/SettingsApplication.qml"
}
