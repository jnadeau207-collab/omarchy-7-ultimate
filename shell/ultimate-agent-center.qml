//@ pragma AppId org.omarchy.AgentCenter
//@ pragma ShellId omarchy-ultimate-agent-center
//@ pragma DataDir $BASE/omarchy/agent-center
//@ pragma StateDir $BASE/omarchy/agent-center
//@ pragma CacheDir $BASE/omarchy/agent-center

import QtQuick
import Quickshell
import "apps/shared" as Shared

Shared.ProductAppHost {
  applicationId: "agent-center"
  appId: "org.omarchy.AgentCenter"
  displayName: "Agent Center"
  ipcTarget: "omarchy.agent-center"
  routeCatalogPath: "apps/ultimate-agent-center/routes-v1.json"
  fabricIdentity: "omarchy-agent-center"
  fabricAllowedMethods: ["managed-work.query", "managed-work.task.create", "managed-work.task.cancel", "managed-work.task.recover", "managed-work.context.capture", "managed-work.run.execute"]
  applicationSourcePath: "apps/ultimate-agent-center/AgentCenterApplication.qml"
}
