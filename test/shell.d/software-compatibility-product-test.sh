#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

software_application="$ROOT/shell/apps/ultimate-software/SoftwareApplication.qml"
software_model="$ROOT/shell/apps/ultimate-software/SoftwareModel.js"
software_entrypoint="$ROOT/shell/ultimate-software.qml"
compatibility_application="$ROOT/shell/apps/ultimate-compatibility/CompatibilityApplication.qml"
compatibility_model="$ROOT/shell/apps/ultimate-compatibility/CompatibilityModel.js"
compatibility_entrypoint="$ROOT/shell/ultimate-compatibility.qml"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-software/SoftwareModel.js')

const revA = `sha256.${'a'.repeat(64)}`
const digestA = `sha256:${'a'.repeat(64)}`
const digestB = `sha256:${'b'.repeat(64)}`

function readAction(capability) {
  return {
    capability,
    mode: 'read',
    risk: 'read-only',
    effects: [],
    arguments: { id: 'contract.arguments', version: 'v0' },
    result: { id: 'contract.result', version: 'v0' },
    preflight: null,
    state: null,
    supportsRollback: false,
    supportsCancellation: false
  }
}

function packagesCatalog() {
  const actions = {
    'catalog.search': readAction('packages.catalog.inspect'),
    'inventory.inspect': readAction('packages.inventory.inspect'),
    'adoption.inspect': readAction('packages.adoption.inspect'),
    'operations.inspect': readAction('packages.operations.inspect')
  }
  return {
    providers: [{
      manifest: {
        schemaVersion: 'v0',
        provider: 'packages.provider',
        providerVersion: 'v0',
        minFabricProtocol: 0,
        maxFabricProtocol: 0,
        capabilities: Object.values(actions).map(action => action.capability),
        actions
      },
      fingerprint: 'a'.repeat(64),
      generation: 4,
      registrationOrder: 1,
      state: 'available',
      detail: '',
      registeredAt: 1,
      changedAt: 2
    }]
  }
}

function catalogSearch(observedAt) {
  return {
    provider: 'packages.provider',
    providerVersion: 'v0',
    generation: 4,
    action: 'catalog.search',
    capability: 'packages.catalog.inspect',
    observedAt,
    value: {
      schemaVersion: 'v0',
      provider: 'packages.provider',
      assurance: 'release-verified',
      revision: revA,
      entries: [{
        id: 'software.curated.neovim',
        sourceId: 'source.omarchy.curated',
        sourceType: 'curated',
        packageRef: 'neovim',
        displayName: 'Neovim',
        summary: 'Curated editor',
        version: '0.11',
        architecture: 'x86_64',
        keywords: ['editor'],
        provenance: {
          assurance: 'release-verified',
          publisher: 'Omarchy',
          origin: 'https://example.invalid/neovim',
          artifactDigest: digestA,
          reviewRevision: digestB,
          trustLevel: 'core',
          signature: { status: 'verified', keyId: 'omarchy.release' }
        },
        install: { requiredBytes: 1024, permissions: [], conflicts: [] }
      }]
    }
  }
}

let sent = []
let serial = 0
const controller = Model.createController({
  send: (method, params) => {
    const id = `request.${++serial}`
    sent.push({ id, method, params })
    return id
  },
  cancel: () => true
})

controller.activate('software.catalog', {})
assertEqual(controller.refreshWhenSurfaceVisible(), false, 'an offline Software surface does not reread')
assertEqual(sent.length, 0, 'offline Software surface-visible refresh issues no Fabric request')

assert(controller.setConnected(true), 'connecting starts the Software catalog read')
assertEqual(controller.state.phase, 'catalog-loading', 'connect waits on the package catalog')
assertEqual(controller.refreshWhenSurfaceVisible(), false, 'a catalog-loading Software surface does not start a second reread')
assertEqual(sent.length, 1, 'catalog-loading Software surface-visible refresh does not duplicate the catalog request')

const catalogRequest = sent.at(-1)
assert(controller.receiveResult(catalogRequest.id, packagesCatalog()), 'current Software catalog response is accepted')
assertEqual(controller.state.phase, 'loading', 'catalog selection advances to inspect')
assertEqual(controller.refreshWhenSurfaceVisible(), false, 'a loading Software surface does not start a second reread')
assertEqual(sent.length, 2, 'in-flight Software inspect is not duplicated by surface-visible refresh')

const inspectRequest = sent.at(-1)
assertEqual(inspectRequest.method, 'provider.read', 'catalog selection issues catalog.search')
assert(controller.receiveResult(inspectRequest.id, catalogSearch(11)), 'current Software inspect is accepted')
assertEqual(controller.state.phase, 'ready', 'non-empty Software inspect reaches current state')

assert(controller.refreshWhenSurfaceVisible(), 'a ready Software surface rereads when it becomes visible')
const visibleReread = sent.at(-1)
assertEqual(visibleReread.method, 'provider.catalog', 'surface-visible refresh reuses controller.refresh catalog plus inspect')
assertEqual(controller.refreshWhenSurfaceVisible(), false, 'a loading Software surface does not start a second reread')
assertEqual(sent.at(-1).id, visibleReread.id, 'in-flight Software surface reread is not duplicated')
JS
pass "Software rereads inspect when the surface becomes visible and skips while loading"

run_node_test <<'JS'
const Model = requireFromRoot('shell/apps/ultimate-compatibility/CompatibilityModel.js')

const revA = `sha256.${'a'.repeat(64)}`

function readAction(capability) {
  return {
    capability,
    mode: 'read',
    risk: 'read-only',
    effects: [],
    arguments: { id: 'contract.arguments', version: 'v0' },
    result: { id: 'contract.result', version: 'v0' },
    preflight: null,
    state: null,
    supportsRollback: false,
    supportsCancellation: false
  }
}

function compatibilityCatalog() {
  const actions = {
    'route.decide': readAction('compatibility.route.decide'),
    'deployments.inspect': readAction('compatibility.deployments.inspect')
  }
  return {
    providers: [{
      manifest: {
        schemaVersion: 'v0',
        provider: 'compatibility.provider',
        providerVersion: 'v0',
        minFabricProtocol: 0,
        maxFabricProtocol: 0,
        capabilities: Object.values(actions).map(action => action.capability),
        actions
      },
      fingerprint: 'a'.repeat(64),
      generation: 4,
      registrationOrder: 1,
      state: 'available',
      detail: '',
      registeredAt: 1,
      changedAt: 2
    }]
  }
}

function deploymentsInspect(observedAt) {
  return {
    provider: 'compatibility.provider',
    providerVersion: 'v0',
    generation: 4,
    action: 'deployments.inspect',
    capability: 'compatibility.deployments.inspect',
    observedAt,
    value: {
      schemaVersion: 'v0',
      provider: 'compatibility.provider',
      revision: revA,
      deployments: [{
        id: 'compatibility.deployment.reader',
        workloadId: 'workload.reader',
        displayName: 'Reader',
        decisionId: 'compatibility.decision.reader',
        decisionRevision: revA,
        route: 'native',
        recipeId: null,
        state: 'installed',
        permissions: ['network'],
        dataArtifacts: []
      }]
    }
  }
}

let sent = []
let serial = 0
const controller = Model.createController({
  send: (method, params) => {
    const id = `request.${++serial}`
    sent.push({ id, method, params })
    return id
  },
  cancel: () => true
})

controller.activate('compatibility.deployments', {})
assertEqual(controller.refreshWhenSurfaceVisible(), false, 'an offline Compatibility surface does not reread')
assertEqual(sent.length, 0, 'offline Compatibility surface-visible refresh issues no Fabric request')

assert(controller.setConnected(true), 'connecting starts the Compatibility catalog read')
assertEqual(controller.state.phase, 'catalog-loading', 'connect waits on the compatibility catalog')
assertEqual(controller.refreshWhenSurfaceVisible(), false, 'a catalog-loading Compatibility surface does not start a second reread')
assertEqual(sent.length, 1, 'catalog-loading Compatibility surface-visible refresh does not duplicate the catalog request')

const catalogRequest = sent.at(-1)
assert(controller.receiveResult(catalogRequest.id, compatibilityCatalog()), 'current Compatibility catalog response is accepted')
assertEqual(controller.state.phase, 'loading', 'catalog selection advances to deployments inspect')
assertEqual(controller.refreshWhenSurfaceVisible(), false, 'a loading Compatibility surface does not start a second reread')
assertEqual(sent.length, 2, 'in-flight Compatibility inspect is not duplicated by surface-visible refresh')

const inspectRequest = sent.at(-1)
assertEqual(inspectRequest.method, 'provider.read', 'catalog selection issues deployments.inspect')
assert(controller.receiveResult(inspectRequest.id, deploymentsInspect(11)), 'current Compatibility inspect is accepted')
assertEqual(controller.state.phase, 'ready', 'non-empty Compatibility inspect reaches current state')

assert(controller.refreshWhenSurfaceVisible(), 'a ready Compatibility surface rereads when it becomes visible')
const visibleReread = sent.at(-1)
assertEqual(visibleReread.method, 'provider.catalog', 'surface-visible refresh reuses controller.refresh catalog plus inspect')
assertEqual(controller.refreshWhenSurfaceVisible(), false, 'a loading Compatibility surface does not start a second reread')
assertEqual(sent.at(-1).id, visibleReread.id, 'in-flight Compatibility surface reread is not duplicated')
JS
pass "Compatibility rereads inspect when the surface becomes visible and skips while loading"

for spec in \
  "Software|$software_application|$software_model|$software_entrypoint" \
  "Compatibility|$compatibility_application|$compatibility_model|$compatibility_entrypoint"; do
  IFS='|' read -r label application model entrypoint <<<"$spec"
  grep -Fq 'refreshWhenSurfaceVisible()' "$application" \
    || fail "$label rereads Fabric inspect when the product surface becomes visible"
  grep -Fq 'function onSurfaceBecameActive()' "$application" \
    || fail "$label listens for host surface activation"
  grep -Fq 'if (!controller || !host || busy) return' "$application" \
    || fail "$label skips surface-visible reread while catalog or inspect is already in flight"
  grep -Fq 'signal surfaceBecameActive()' "$ROOT/shell/apps/shared/ProductAppHost.qml" \
    || fail "Product host publishes surface activation instead of a $label polling loop"
  if grep -Eq 'events[.](subscribe|unsubscribe)' "$application" "$model" "$entrypoint"; then
    fail "$label does not invent an events.subscribe path"
  fi
done
pass "Software and Compatibility listen for surface activation without events.subscribe or a polling daemon"
