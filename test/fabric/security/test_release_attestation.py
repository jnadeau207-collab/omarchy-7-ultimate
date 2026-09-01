from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "default" / "fabric"))

from omarchy_fabric.models import FabricError
from omarchy_fabric.providers.packages.catalog import PackageCatalog, catalog_revision
from omarchy_fabric.providers.compatibility.recipes import RecipeCatalog
from omarchy_fabric.providers.packages.identity import revision
from omarchy_fabric.security.errors import SecurityValidationError
from omarchy_fabric.security.release_attestation import (
    default_release_attestation,
    parse_release_attestation,
)


def catalog_document():
    return json.loads((ROOT / "default" / "ultimate" / "software" / "catalog-v0.json").read_text(encoding="utf-8"))


def recipe_document():
    return json.loads((ROOT / "default" / "ultimate" / "compatibility" / "recipes-v0.json").read_text(encoding="utf-8"))


class ReleaseAttestationTests(unittest.TestCase):
    def test_checked_in_attestation_admits_no_product_revisions(self) -> None:
        attestation = default_release_attestation(ROOT / "default")
        self.assertEqual(attestation.attestation_id, "omarchy.release-attestation.default")
        self.assertEqual(attestation.admitted_revisions("packages-catalog"), frozenset())
        self.assertEqual(attestation.admitted_revisions("compatibility-recipes"), frozenset())

    def test_seed_catalog_cannot_become_release_verified_via_empty_attestation(self) -> None:
        attestation = default_release_attestation(ROOT / "default")
        value = catalog_document()
        value["assurance"] = "release-verified"
        for entry in value["entries"]:
            entry["provenance"]["assurance"] = "release-verified"
            entry["provenance"]["signature"]["status"] = (
                "reviewed" if entry["sourceType"] == "reviewed-aur" else "verified"
            )
        value["revision"] = catalog_revision(value)
        with self.assertRaises(FabricError) as unattested:
            PackageCatalog(value, verified_catalog_revisions=attestation.admitted_revisions("packages-catalog"))
        self.assertEqual(unattested.exception.code, "packages.catalog-unattested")

    def test_exact_revision_admission_unlocks_release_verified_documents(self) -> None:
        value = catalog_document()
        value["assurance"] = "release-verified"
        for entry in value["entries"]:
            entry["provenance"]["assurance"] = "release-verified"
            entry["provenance"]["signature"]["status"] = (
                "reviewed" if entry["sourceType"] == "reviewed-aur" else "verified"
            )
        value["revision"] = catalog_revision(value)
        recipes = recipe_document()
        recipes["assurance"] = "release-verified"
        for recipe in recipes["recipes"]:
            recipe["signature"]["status"] = "verified"
        unsigned = copy.deepcopy(recipes)
        unsigned["revision"] = "sha256." + "0" * 64
        recipes["revision"] = revision(unsigned)
        attestation = parse_release_attestation(
            {
                "schemaVersion": "v0",
                "attestationId": "omarchy.release-attestation.test",
                "admittedRevisions": [
                    {
                        "kind": "packages-catalog",
                        "revision": value["revision"],
                        "documentId": "software.catalog.v0",
                    },
                    {
                        "kind": "compatibility-recipes",
                        "revision": recipes["revision"],
                        "documentId": "compatibility.recipes.v0",
                    },
                ],
            }
        )
        catalog = PackageCatalog(
            value,
            verified_catalog_revisions=attestation.admitted_revisions("packages-catalog"),
        )
        admitted_recipes = RecipeCatalog(
            recipes,
            verified_recipe_revisions=attestation.admitted_revisions("compatibility-recipes"),
        )
        self.assertEqual(catalog.assurance, "release-verified")
        self.assertEqual(admitted_recipes.assurance, "release-verified")
        wrong = parse_release_attestation(
            {
                "schemaVersion": "v0",
                "attestationId": "omarchy.release-attestation.wrong",
                "admittedRevisions": [
                    {
                        "kind": "compatibility-recipes",
                        "revision": value["revision"],
                        "documentId": "software.catalog.v0",
                    }
                ],
            }
        )
        with self.assertRaises(FabricError) as mismatched:
            PackageCatalog(value, verified_catalog_revisions=wrong.admitted_revisions("packages-catalog"))
        self.assertEqual(mismatched.exception.code, "packages.catalog-unattested")

    def test_unknown_kind_and_malformed_document_fail_closed(self) -> None:
        attestation = default_release_attestation(ROOT / "default")
        with self.assertRaisesRegex(SecurityValidationError, "not recognized"):
            attestation.admitted_revisions("firmware-bundle")
        with self.assertRaisesRegex(SecurityValidationError, "closed schema"):
            parse_release_attestation(
                {
                    "schemaVersion": "v0",
                    "attestationId": "omarchy.release-attestation.bad",
                    "admittedRevisions": [{"kind": "packages-catalog"}],
                }
            )


if __name__ == "__main__":
    unittest.main()
