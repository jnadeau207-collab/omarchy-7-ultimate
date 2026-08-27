from __future__ import annotations

import os
import socket
import sys
import tempfile
import unittest
from contextlib import nullcontext
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "default" / "fabric"))

from sandbox.builder import (
    FIXED_AGENT_RUNNER,
    NetworkScope,
    SandboxSpec,
    SandboxUnavailable,
    SandboxViolation,
    ScopedBind,
    TaskProxy,
    build_bwrap_command,
    require_bwrap,
    validate_runner_argv,
)
from sandbox.profiles import DEFAULT_EXPOSURE, ProfileValidationError, default_profile, validate_profile_document


class SandboxTests(unittest.TestCase):
    def runner(self, task_id: str = "task.one") -> tuple[str, ...]:
        return (FIXED_AGENT_RUNNER, "--task-id", task_id, "--manifest-fd", "3")

    def test_default_command_unshares_every_namespace_and_exposes_no_session_state(self) -> None:
        command = build_bwrap_command(SandboxSpec("task.one", self.runner()))
        self.assertIn("--unshare-all", command)
        self.assertIn("--clearenv", command)
        self.assertNotIn("--share-net", command)
        self.assertNotIn("WAYLAND_DISPLAY", command)
        self.assertNotIn("DBUS_SESSION_BUS_ADDRESS", command)
        self.assertNotIn("SSH_AUTH_SOCK", command)
        self.assertNotIn("fabric.sock", " ".join(command))
        home_index = command.index("/home")
        self.assertEqual(command[home_index - 1], "--tmpfs")
        self.assertEqual(command[-5:], self.runner())

    def test_only_explicit_scoped_workspace_and_artifact_binds_are_built(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            workspace = root / "workspace"
            artifact = root / "artifact"
            protected_home = root / "home"
            workspace.mkdir()
            artifact.mkdir()
            protected_home.mkdir()
            spec = SandboxSpec(
                "task.one",
                self.runner(),
                binds=(
                    ScopedBind(workspace, workspace, "/workspace/task.one", writable=True),
                    ScopedBind(artifact, artifact, "/artifacts/task.one", writable=False),
                ),
            )
            command = build_bwrap_command(spec, protected_home=protected_home)
            self.assertIn(str(workspace.resolve()), command)
            self.assertIn(str(artifact.resolve()), command)
            self.assertIn("/workspace/task.one", command)
            self.assertIn("/artifacts/task.one", command)

    def test_path_traversal_outside_scope_and_general_home_are_denied(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            scope = root / "scope"
            outside = root / "outside"
            home = root / "home"
            scope.mkdir()
            outside.mkdir()
            home.mkdir()
            cases = (
                ScopedBind(outside, scope, "/workspace/task.one"),
                ScopedBind(scope, scope, "/workspace/../home"),
                ScopedBind(home, home, "/workspace/task.one"),
                ScopedBind(scope, scope, "/run/user/1000"),
                ScopedBind(scope, Path(scope.anchor), "/workspace/task.one"),
            )
            for bind in cases:
                with self.subTest(bind=bind):
                    with self.assertRaises(SandboxViolation):
                        build_bwrap_command(
                            SandboxSpec("task.one", self.runner(), binds=(bind,)),
                            protected_home=home,
                        )

    def test_symlink_sensitive_and_secret_sources_are_denied_without_skipping(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            scope = root / "scope"
            target = scope / "real"
            link = scope / "link"
            secret = scope / ".ssh"
            home = root / "home"
            target.mkdir(parents=True)
            secret.mkdir()
            home.mkdir()
            try:
                os.symlink(target, link, target_is_directory=True)
            except OSError:
                # Windows without Developer Mode cannot create the adversarial
                # fixture. Exercise the same fail-closed branch explicitly; the
                # Linux/VM run creates and tests the real symlink.
                with mock.patch("sandbox.builder._has_symlink_component", return_value=True):
                    with self.assertRaises(SandboxViolation):
                        build_bwrap_command(
                            SandboxSpec(
                                "task.one",
                                self.runner(),
                                binds=(ScopedBind(target, scope, "/workspace/task.one"),),
                            ),
                            protected_home=home,
                        )
                sources = (secret,)
            else:
                sources = (link, secret)
            for source in sources:
                with self.subTest(source=source):
                    with self.assertRaises(SandboxViolation):
                        build_bwrap_command(
                            SandboxSpec(
                                "task.one",
                                self.runner(),
                                binds=(ScopedBind(source, scope, "/workspace/task.one"),),
                            ),
                            protected_home=home,
                        )

    def test_unsafe_runner_argv_and_environment_are_denied(self) -> None:
        bad_argv = (
            ("/bin/sh", "-c", "id"),
            (FIXED_AGENT_RUNNER, "--task-id", "task.one", "--manifest-fd", "3", "--command", "id"),
            (FIXED_AGENT_RUNNER, "--task-id", "task.two", "--manifest-fd", "3"),
            (FIXED_AGENT_RUNNER, "--task-id", "task.one", "--manifest-fd", "../../secret"),
            (FIXED_AGENT_RUNNER, "--task-id", "task.one\n--share-net", "--manifest-fd", "3"),
        )
        for argv in bad_argv:
            with self.subTest(argv=argv):
                with self.assertRaises(SandboxViolation):
                    validate_runner_argv(argv, task_id="task.one")
        for key in ("HOME", "WAYLAND_DISPLAY", "DBUS_SESSION_BUS_ADDRESS", "SSH_AUTH_SOCK", "LD_PRELOAD"):
            with self.subTest(key=key):
                with self.assertRaises(SandboxViolation):
                    SandboxSpec("task.one", self.runner(), environment={key: "/tmp/escape"})

    def test_task_proxy_is_exactly_scoped_and_never_shares_host_network(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            proxy_root = root / "proxy"
            proxy_root.mkdir()
            proxy = proxy_root / "task-one.sock"
            main_socket = proxy_root / "fabric.sock"
            home = root / "home"
            home.mkdir()
            listeners = []
            if hasattr(socket, "AF_UNIX"):
                for path in (proxy, main_socket):
                    listener = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                    listener.bind(str(path))
                    listeners.append(listener)
                socket_probe = nullcontext()
            else:
                proxy.touch()
                main_socket.touch()
                # This Python build cannot create AF_UNIX fixtures. Still prove
                # that the builder requires and handles the socket-type check;
                # Linux/VM runs exercise real socket inodes.
                socket_probe = mock.patch("sandbox.builder.stat.S_ISSOCK", return_value=True)
            try:
                with socket_probe:
                    spec = SandboxSpec(
                        "task.one",
                        self.runner(),
                    task_proxy=TaskProxy(
                        proxy,
                        proxy_root,
                        "task.one",
                        (NetworkScope("api.openai.com", 443),),
                        ),
                    )
                    command = build_bwrap_command(spec, protected_home=home)
                    self.assertIn("/run/omarchy/task-proxy.sock", command)
                    self.assertIn("https://api.openai.com:443", command)
                    self.assertNotIn("--share-net", command)
                    with self.assertRaises(SandboxViolation):
                        build_bwrap_command(
                            SandboxSpec(
                                "task.one",
                                self.runner(),
                        task_proxy=TaskProxy(main_socket, proxy_root, "task.one", (NetworkScope("example.com", 443),)),
                            ),
                            protected_home=home,
                        )
            finally:
                for listener in listeners:
                    listener.close()

    def test_task_proxy_cannot_cross_task_boundaries(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            proxy_root = root / "proxy"
            proxy_root.mkdir()
            proxy = proxy_root / "task-two.sock"
            proxy.touch()
            home = root / "home"
            home.mkdir()
            with mock.patch("sandbox.builder.stat.S_ISSOCK", return_value=True):
                with self.assertRaisesRegex(SandboxViolation, "does not match"):
                    build_bwrap_command(
                        SandboxSpec(
                            "task.one",
                            self.runner("task.one"),
                            task_proxy=TaskProxy(
                                proxy,
                                proxy_root,
                                "task.two",
                                (NetworkScope("example.com", 443),),
                            ),
                        ),
                        protected_home=home,
                    )

    def test_missing_or_untrusted_bubblewrap_fails_closed(self) -> None:
        with self.assertRaises(SandboxUnavailable):
            require_bwrap("/tmp/not-bwrap")
        if not Path("/usr/bin/bwrap").exists():
            with self.assertRaisesRegex(SandboxUnavailable, "fails closed"):
                require_bwrap()

    def test_profile_validator_rejects_exposure_and_malformed_network(self) -> None:
        profile = default_profile("task.one")
        self.assertEqual(validate_profile_document(profile)["network"]["mode"], "none")
        profile["exposure"]["home"] = True
        with self.assertRaises(ProfileValidationError):
            validate_profile_document(profile)
        profile["exposure"] = dict(DEFAULT_EXPOSURE)
        profile["network"] = {"mode": "none", "scopes": [{"host": "example.com"}]}
        with self.assertRaises(ProfileValidationError):
            validate_profile_document(profile)
        profile["network"] = {"mode": "host", "scopes": []}
        with self.assertRaises(ProfileValidationError):
            validate_profile_document(profile)
        profile["network"] = {
            "mode": "task-proxy",
            "scopes": [{"protocol": "http", "host": "localhost", "port": True}],
        }
        with self.assertRaises(ProfileValidationError):
            validate_profile_document(profile)

    def test_workspace_binds_cannot_smuggle_unix_sockets(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            scope = root / "scope"
            scope.mkdir()
            candidate = scope / "wayland-1"
            candidate.touch()
            home = root / "home"
            home.mkdir()
            with mock.patch("sandbox.builder.stat.S_ISSOCK", return_value=True):
                with self.assertRaisesRegex(SandboxViolation, "Sockets are forbidden"):
                    build_bwrap_command(
                        SandboxSpec(
                            "task.one",
                            self.runner(),
                            binds=(ScopedBind(candidate, scope, "/workspace/socket"),),
                        ),
                        protected_home=home,
                    )


if __name__ == "__main__":
    unittest.main()
