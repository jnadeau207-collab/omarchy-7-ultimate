import QtQuick
QtObject {
  id: root

  property bool open: false

  function toggle() { open = !open }
  function show() { if (!open) open = true }
  function hide() { open = false }
}
