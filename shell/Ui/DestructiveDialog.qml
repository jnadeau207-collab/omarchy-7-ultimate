import QtQuick

// Consequential confirmation specialization. It states the consequence and
// recovery policy in both visible copy and the accessibility description;
// cancel remains the default action inherited from OperationDialog.
OperationDialog {
  id: root

  property string targetName: "this item"
  property string consequence: "This action cannot be completed without changing the current state."
  property string recovery: ""
  property string destructiveActionText: "Delete"

  stateId: "failure"
  toneOverride: "danger"
  destructive: true
  title: "Delete " + targetName + "?"
  message: consequence
  recoveryText: recovery !== "" ? recovery : "This action cannot be undone."
  primaryText: destructiveActionText
}
