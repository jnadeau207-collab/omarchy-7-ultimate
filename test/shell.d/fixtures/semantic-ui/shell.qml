import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Gallery" as Gallery

ShellRoot {
  id: root

  function fail(message) {
    console.log("RESULT fail " + message)
    Qt.quit()
  }

  function require(condition, message) {
    if (!condition) {
      fail(message)
      return false
    }
    return true
  }

  function finitePositive(value) {
    return isFinite(value) && value > 0
  }

  function runChecks() {
    if (!require(Semantics.operationStates.length === 8, "operation vocabulary is incomplete")) return
    if (!require(compactProfile.minimumTarget === 28, "compact target is not 28")) return
    if (!require(touchProfile.minimumTarget >= 44, "touch target is below 44")) return
    if (!require(reducedProfile.duration(400) === 0, "reduced motion did not remove duration")) return
    if (!require(largeProfile.font(12) >= 15, "large text did not scale typography")) return
    if (!require(compactButton.implicitHeight >= compactProfile.minimumTarget, "compact button target is undersized")) return
    if (!require(touchButton.implicitHeight >= touchProfile.minimumTarget, "touch button target is undersized")) return
    if (!require(finitePositive(operation.implicitWidth) && finitePositive(operation.implicitHeight), "operation status geometry is invalid")) return
    if (!require(finitePositive(search.implicitHeight) && search.implicitHeight >= touchProfile.minimumTarget, "text input target is invalid")) return
    if (!require(finitePositive(progress.implicitWidth) && finitePositive(progress.implicitHeight), "progress geometry is invalid")) return
    if (!require(!labeledToggle.Accessible.ignored && labeledToggle.Accessible.checked,
      "labeled toggle row lost its accessible checked node")) return
    if (!require(presentationSwitch.Accessible.ignored,
      "presentation-only toggle switch exported a duplicate accessible node")) return
    if (!require(!standaloneSwitch.Accessible.ignored,
      "standalone toggle switch was removed from the accessibility tree")) return
    if (!require(longChoice.implicitWidth <= 300 && longChoice.implicitHeight >= touchProfile.minimumTarget,
      "wrapped choice control exceeds its declared bounds")) return
    if (!require(destructive.selectedIndex === 0, "destructive dialog did not default to cancel")) return
    if (!require(pseudoProfile.text("Apply %1").indexOf("%1") >= 0, "pseudo locale damaged a placeholder")) return
    if (!require(rtlProfile.logicalEdges(4, 12).left === 12, "RTL logical edges did not mirror")) return
    var galleryFixtures = [darkFixture, pseudoFixture, touchFixture, twoXFixture]
    for (var index = 0; index < galleryFixtures.length; index++) {
      if (!require(galleryFixtures[index].targetSizesPass, "gallery fixture target sizing failed at index " + index)) return
      if (!require(galleryFixtures[index].contentFits, "gallery fixture content overflowed at index " + index)) return
    }
    console.log("RESULT pass")
    Qt.quit()
  }

  Component.onCompleted: Qt.callLater(runChecks)

  SemanticProfile { id: compactProfile; densityMode: "compact" }
  SemanticProfile { id: touchProfile; densityMode: "touch"; scaleFactor: 1.5 }
  SemanticProfile { id: reducedProfile; reducedMotion: true }
  SemanticProfile { id: largeProfile; largeText: true; textScale: 1.25 }
  SemanticProfile { id: pseudoProfile; pseudoLocale: true }
  SemanticProfile { id: rtlProfile; rtl: true }

  Item {
    Button {
      id: compactButton
      text: "Compact"
      semanticProfile: compactProfile
    }

    Button {
      id: touchButton
      text: "Touch"
      semanticProfile: touchProfile
    }

    TextField {
      id: search
      semanticProfile: touchProfile
      semanticPlaceholderText: "Search settings"
    }

    ProgressBar {
      id: progress
      semanticProfile: reducedProfile
      indeterminate: true
    }

    Checkbox {
      id: longChoice
      semanticProfile: touchProfile
      label: "Include optional items in this deliberately extended localization fixture"
      labelMaximumWidth: 220
    }

    Toggle {
      id: labeledToggle
      width: 320
      label: "Automatic recovery"
      description: "Restore the previous settings if applying changes fails."
      checked: true
      semanticProfile: largeProfile
    }

    ToggleSwitch {
      id: presentationSwitch
      checked: true
      interactive: false
      semanticProfile: compactProfile
    }

    ToggleSwitch {
      id: standaloneSwitch
      checked: true
      semanticProfile: compactProfile
    }

    OperationStatus {
      id: operation
      width: 320
      height: implicitHeight
      semanticProfile: largeProfile
      stateId: "recovery"
      secondaryActionText: "Details"
    }

    DestructiveDialog {
      id: destructive
      width: 600
      height: 400
      semanticProfile: rtlProfile
      targetName: "saved profile"
    }

    Gallery.SemanticFixture {
      id: darkFixture
      width: 420
      dark: true
      density: "comfortable"
      profileScale: 1
    }

    Gallery.SemanticFixture {
      id: pseudoFixture
      width: 420
      dark: false
      density: "compact"
      profileScale: 1.25
      highContrast: true
      reducedMotion: true
      largeText: true
      locale: "pseudo"
      focusMode: "keyboard"
    }

    Gallery.SemanticFixture {
      id: touchFixture
      width: 420
      dark: true
      density: "touch"
      profileScale: 1.5
      highContrast: true
      reducedMotion: true
      largeText: true
      locale: "long"
      rtl: true
      focusMode: "keyboard"
    }

    Gallery.SemanticFixture {
      id: twoXFixture
      width: 420
      dark: false
      density: "comfortable"
      profileScale: 2
      rtl: true
    }
  }
}
