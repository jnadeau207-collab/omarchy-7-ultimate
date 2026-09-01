//@ pragma AppId org.omarchy.Files
//@ pragma ShellId omarchy-ultimate-files
//@ pragma DataDir $BASE/omarchy/files
//@ pragma StateDir $BASE/omarchy/files
//@ pragma CacheDir $BASE/omarchy/files

import QtQuick
import Quickshell
import "apps/shared" as Shared

Shared.ProductAppHost {
  applicationId: "files"
  appId: "org.omarchy.Files"
  displayName: "Files"
  ipcTarget: "omarchy.files"
  routeCatalogPath: "apps/ultimate-files/routes-v1.json"
  fabricIdentity: "omarchy-files"
  fabricAllowedMethods: ["provider.catalog", "provider.read", "operation.preflight", "operation.approve", "operation.start", "operation.get"]
  applicationSourcePath: "apps/ultimate-files/FilesApplication.qml"
}
