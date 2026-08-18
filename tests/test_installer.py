from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest


REPO_ROOT = Path(__file__).parents[1]
INSTALLER = REPO_ROOT / "install.sh"


class InstallerLuaMigrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory(prefix="tsugumori-installer-test-")
        self.root = Path(self.tempdir.name)
        self.home = self.root / "home"
        self.config_home = self.root / "config"
        self.runtime_dir = self.root / "runtime"
        self.fake_bin = self.root / "bin"
        self.home.mkdir()
        self.config_home.mkdir()
        self.runtime_dir.mkdir(mode=0o700)
        self.fake_bin.mkdir()

        self.env = os.environ.copy()
        self.env.update(
            {
                "HOME": str(self.home),
                "XDG_CONFIG_HOME": str(self.config_home),
                "XDG_RUNTIME_DIR": str(self.runtime_dir),
                "TMPDIR": str(self.root),
                "INSTALLER_UNDER_TEST": str(INSTALLER),
            }
        )

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def run_installer_shell(
        self,
        body: str,
        *,
        extra_env: dict[str, str] | None = None,
        drop_root_privileges: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        env = self.env.copy()
        if extra_env:
            env.update(extra_env)
        script = 'source "$INSTALLER_UNDER_TEST"\n' + textwrap.dedent(body)
        identity: dict[str, object] = {}
        if drop_root_privileges and os.geteuid() == 0:
            # GitHub's Arch container runs as root, while the installer requires
            # a normal user. Let this preflight test exercise the next guard.
            self.root.chmod(0o755)
            installer_copy = self.root / "install.sh"
            shutil.copyfile(INSTALLER, installer_copy)
            installer_copy.chmod(0o644)
            env["INSTALLER_UNDER_TEST"] = str(installer_copy)
            identity = {"user": 65534, "group": 65534, "extra_groups": []}
        return subprocess.run(
            ["/usr/bin/bash", "-c", script],
            env=env,
            cwd=self.root,
            text=True,
            capture_output=True,
            check=False,
            **identity,
        )

    def write_executable(self, name: str, source: str) -> None:
        path = self.fake_bin / name
        path.write_text(textwrap.dedent(source).lstrip(), encoding="utf-8")
        path.chmod(0o755)

    def install_fake_hyprland_tools(self) -> Path:
        verify_log = self.root / "hyprland-verify.log"
        self.write_executable(
            "pacman",
            """
            #!/bin/sh
            if [ "$1" = "-Q" ] && [ "$2" = "hyprland" ]; then
                printf 'hyprland %s\n' "${FAKE_HYPRLAND_VERSION:-0.55.2-1}"
                exit 0
            fi
            exit 2
            """,
        )
        self.write_executable(
            "vercmp",
            """
            #!/bin/sh
            printf '%s\n' "${FAKE_VERCMP_RESULT:-0}"
            """,
        )
        self.write_executable(
            "Hyprland",
            """
            #!/usr/bin/env bash
            set -eu
            config=""
            while (( $# > 0 )); do
                if [[ "$1" == "--config" ]]; then
                    shift
                    config="$1"
                fi
                shift
            done
            [[ -n "$config" ]]
            config_dir=$(dirname -- "$config")
            user=$(tr '\n' ';' <"$config_dir/user.lua")
            options=$(tr '\n' ';' <"$config_dir/tsugumori_options.lua")
            printf '%s|%s|%s\n' "$config" "$user" "$options" >>"$FAKE_VERIFY_LOG"
            if grep -q 'INVALID_OVERRIDE' "$config_dir/user.lua"; then
                exit 23
            fi
            """,
        )
        return verify_log

    def test_sourcing_is_side_effect_free_and_repo_url_is_overridable(self) -> None:
        candidate = self.root / "candidate-repository"
        git_log = self.root / "git.log"
        self.write_executable(
            "git",
            """
            #!/bin/sh
            printf '%s\n' "$@" >"$FAKE_GIT_LOG"
            """,
        )
        result = self.run_installer_shell(
            """
            declare -F main >/dev/null
            clone_repo
            """,
            extra_env={
                "PATH": f"{self.fake_bin}{os.pathsep}{self.env['PATH']}",
                "FAKE_GIT_LOG": str(git_log),
                "TSUGUMORI_REPO_URL": str(candidate),
                "TSUGUMORI_BRANCH": "lua-candidate",
            },
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        git_args = git_log.read_text(encoding="utf-8").splitlines()
        self.assertEqual(
            git_args[:-1],
            [
                "clone",
                "--depth=1",
                "--branch",
                "lua-candidate",
                str(candidate),
            ],
        )
        self.assertTrue(git_args[-1].startswith(str(self.root / "Tsugumori-install-")))

    def test_lua_and_legacy_overrides_are_both_preserved(self) -> None:
        result = self.run_installer_shell("printf '%s\n' \"${PRESERVED_FILES[@]}\"")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout.splitlines(),
            [
                "hypr/user.lua",
                "hypr/user.conf",
                "quickshell/settings/Settings.qml",
            ],
        )

    def test_active_legacy_config_without_user_lua_fails_closed(self) -> None:
        legacy = self.config_home / "hypr/user.conf"
        legacy.parent.mkdir(parents=True)
        legacy.write_text("monitor = DP-1, preferred, auto, 1\n", encoding="utf-8")

        result = self.run_installer_shell(
            """
            BACKUP_OLD=false
            inspect_legacy_user_config
            """
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Migrate active hypr/user.conf overrides", result.stderr)
        self.assertEqual(
            legacy.read_text(encoding="utf-8"),
            "monitor = DP-1, preferred, auto, 1\n",
        )

    def test_active_legacy_config_with_user_lua_is_preserved_for_migration(self) -> None:
        hypr_dir = self.config_home / "hypr"
        hypr_dir.mkdir(parents=True)
        (hypr_dir / "user.conf").write_text(
            "bind = SUPER, B, exec, firefox\n", encoding="utf-8"
        )
        (hypr_dir / "user.lua").write_text("-- migrated\n", encoding="utf-8")

        result = self.run_installer_shell(
            """
            BACKUP_OLD=false
            inspect_legacy_user_config
            printf 'active=%s\n' "$LEGACY_USER_CONF_ACTIVE"
            """
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("active=true\n", result.stdout)
        self.assertEqual(
            (hypr_dir / "user.lua").read_text(encoding="utf-8"), "-- migrated\n"
        )
        self.assertEqual(
            (hypr_dir / "user.conf").read_text(encoding="utf-8"),
            "bind = SUPER, B, exec, firefox\n",
        )

    def test_options_are_atomic_reversible_and_do_not_modify_user_lua(self) -> None:
        result = self.run_installer_shell(
            """
            target="$CONFIG_HOME/hypr/tsugumori_options.lua"
            user="$CONFIG_HOME/hypr/user.lua"
            mkdir -p "$CONFIG_HOME/hypr"
            printf '%s\n' 'user-sentinel' >"$user"
            VM_GL_TWEAKS=true
            BOOT_WALLPAPER_VM=true
            write_tsugumori_options "$target" false
            grep -q 'vm_software_gl = true' "$target"
            grep -q 'boot_wallpaper = true' "$target"
            VM_GL_TWEAKS=false
            BOOT_WALLPAPER_VM=false
            write_tsugumori_options "$target" false
            cat "$target"
            printf 'mode=%s\n' "$(stat -c '%a' "$target")"
            printf 'user=%s\n' "$(cat "$user")"
            shopt -s nullglob
            leftovers=("$CONFIG_HOME/hypr"/.tsugumori_options.lua.*)
            printf 'temporary-files=%s\n' "${#leftovers[@]}"
            """
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("vm_software_gl = false,\n", result.stdout)
        self.assertIn("boot_wallpaper = false,\n", result.stdout)
        self.assertIn("mode=644\n", result.stdout)
        self.assertIn("user=user-sentinel\n", result.stdout)
        self.assertIn("temporary-files=0\n", result.stdout)

    def test_deploy_restores_lua_legacy_and_quickshell_user_files(self) -> None:
        result = self.run_installer_shell(
            """
            mkdir -p "$CLONE_DIR/config/hypr" "$CLONE_DIR/config/quickshell/settings"
            mkdir -p "$CONFIG_HOME/hypr" "$CONFIG_HOME/quickshell/settings"
            printf '%s\n' 'managed-config' >"$CLONE_DIR/config/hypr/hyprland.lua"
            printf '%s\n' 'bundled-user' >"$CLONE_DIR/config/hypr/user.lua"
            printf '%s\n' 'return {}' >"$CLONE_DIR/config/hypr/tsugumori_options.lua"
            printf '%s\n' 'bundled-settings' >"$CLONE_DIR/config/quickshell/settings/Settings.qml"
            printf '%s\n' 'preserved-lua' >"$CONFIG_HOME/hypr/user.lua"
            printf '%s\n' 'preserved-legacy' >"$CONFIG_HOME/hypr/user.conf"
            printf '%s\n' 'preserved-settings' >"$CONFIG_HOME/quickshell/settings/Settings.qml"
            BACKUP_OLD=false
            deploy_configs
            printf 'lua=%s\n' "$(cat "$CONFIG_HOME/hypr/user.lua")"
            printf 'legacy=%s\n' "$(cat "$CONFIG_HOME/hypr/user.conf")"
            printf 'settings=%s\n' "$(cat "$CONFIG_HOME/quickshell/settings/Settings.qml")"
            printf 'managed=%s\n' "$(cat "$CONFIG_HOME/hypr/hyprland.lua")"
            """
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("lua=preserved-lua\n", result.stdout)
        self.assertIn("legacy=preserved-legacy\n", result.stdout)
        self.assertIn("settings=preserved-settings\n", result.stdout)
        self.assertIn("managed=managed-config\n", result.stdout)

    def test_deploy_preserves_exact_relative_symlinks_for_all_user_files(self) -> None:
        custom_dir = self.config_home / "custom"
        custom_dir.mkdir()
        targets = {
            "hypr/user.lua": ("../custom/user.lua", "preserved-lua\n"),
            "hypr/user.conf": ("../custom/user.conf", "preserved-legacy\n"),
            "quickshell/settings/Settings.qml": (
                "../../custom/Settings.qml",
                "preserved-settings\n",
            ),
        }
        for _, (link_text, contents) in targets.items():
            target = (custom_dir / Path(link_text).name)
            target.write_text(contents, encoding="utf-8")

        hypr_dir = self.config_home / "hypr"
        settings_dir = self.config_home / "quickshell/settings"
        hypr_dir.mkdir()
        settings_dir.mkdir(parents=True)
        for rel, (link_text, _) in targets.items():
            (self.config_home / rel).symlink_to(link_text)

        result = self.run_installer_shell(
            """
            mkdir -p "$CLONE_DIR/config/hypr" "$CLONE_DIR/config/quickshell/settings"
            printf '%s\n' 'managed-config' >"$CLONE_DIR/config/hypr/hyprland.lua"
            printf '%s\n' 'bundled-user' >"$CLONE_DIR/config/hypr/user.lua"
            printf '%s\n' 'return {}' >"$CLONE_DIR/config/hypr/tsugumori_options.lua"
            printf '%s\n' 'bundled-settings' >"$CLONE_DIR/config/quickshell/settings/Settings.qml"
            BACKUP_OLD=false
            deploy_configs
            """
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        for rel, (link_text, contents) in targets.items():
            with self.subTest(rel=rel):
                restored = self.config_home / rel
                self.assertTrue(restored.is_symlink())
                self.assertEqual(os.readlink(restored), link_text)
                self.assertEqual(restored.read_text(encoding="utf-8"), contents)

    def test_external_target_shared_with_managed_alias_survives(self) -> None:
        external_kitty = self.root / "external-kitty"
        external_kitty.mkdir()
        target = external_kitty / "user.lua"
        target.write_text("external-user\n", encoding="utf-8")

        hypr_dir = self.config_home / "hypr"
        hypr_dir.mkdir()
        preserved = hypr_dir / "user.lua"
        preserved.symlink_to(target)
        kitty_alias = self.config_home / "kitty"
        kitty_alias.symlink_to("../external-kitty", target_is_directory=True)

        result = self.run_installer_shell(
            """
            mkdir -p "$CLONE_DIR/config/hypr" "$CLONE_DIR/config/kitty"
            printf '%s\n' 'managed-config' >"$CLONE_DIR/config/hypr/hyprland.lua"
            printf '%s\n' 'bundled-user' >"$CLONE_DIR/config/hypr/user.lua"
            printf '%s\n' 'return {}' >"$CLONE_DIR/config/hypr/tsugumori_options.lua"
            printf '%s\n' 'managed-kitty' >"$CLONE_DIR/config/kitty/kitty.conf"
            BACKUP_OLD=false
            deploy_configs
            """
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(preserved.is_symlink())
        self.assertEqual(os.readlink(preserved), str(target))
        self.assertEqual(preserved.read_text(encoding="utf-8"), "external-user\n")
        self.assertEqual(target.read_text(encoding="utf-8"), "external-user\n")
        self.assertFalse(kitty_alias.is_symlink())
        self.assertEqual(
            (kitty_alias / "kitty.conf").read_text(encoding="utf-8"),
            "managed-kitty\n",
        )

    def test_path_is_within_requires_a_path_component_boundary(self) -> None:
        result = self.run_installer_shell(
            """
            root="$CONFIG_HOME/hypr"
            path_is_within "$root" "$root"
            path_is_within "$root/user.lua" "$root"
            ! path_is_within "$CONFIG_HOME/hypr-old/user.lua" "$root"
            path_is_within "/" "/"
            path_is_within "/etc/file" "/"
            """
        )

        self.assertEqual(result.returncode, 0, result.stderr)

    def test_managed_path_symlink_dependencies_fail_before_deployment(self) -> None:
        cases = (
            (
                "same-managed-directory",
                "hypr/user.lua",
                "local-user.lua",
                "direct",
            ),
            (
                "cross-managed-directory",
                "hypr/user.conf",
                "../quickshell/local-user.conf",
                "direct",
            ),
            (
                "managed-intermediate-link",
                "quickshell/settings/Settings.qml",
                "../settings-source.qml",
                "intermediate",
            ),
            (
                "outside-alias-into-managed-directory",
                "hypr/user.lua",
                "../outside-alias/aliased-user.lua",
                "outside-alias",
            ),
            (
                "outside-through-managed-link-to-external-target",
                "hypr/user.lua",
                "../outside-chain/user.lua",
                "outside-managed-outside",
            ),
            (
                "managed-root-alias-changes-relative-link-anchor",
                "hypr/user.lua",
                "../external-user.lua",
                "managed-root-alias",
            ),
        )

        for name, preserved_rel, link_text, setup_kind in cases:
            with self.subTest(case=name):
                case_root = self.root / name
                config_home = case_root / "config"
                hypr_dir = config_home / "hypr"
                settings_dir = config_home / "quickshell/settings"
                if setup_kind == "managed-root-alias":
                    external_hypr = case_root / "external-hypr"
                    external_hypr.mkdir(parents=True)
                    config_home.mkdir()
                    hypr_dir.symlink_to("../external-hypr", target_is_directory=True)
                else:
                    hypr_dir.mkdir(parents=True)
                settings_dir.mkdir(parents=True)

                sentinel = hypr_dir / "managed-sentinel"
                sentinel.write_bytes(b"original-managed-state\n")
                if setup_kind == "intermediate":
                    target = config_home / "external/Settings.qml"
                    target.parent.mkdir()
                    intermediate = config_home / "quickshell/settings-source.qml"
                    intermediate.symlink_to("../external/Settings.qml")
                elif setup_kind == "outside-alias":
                    target = hypr_dir / "aliased-user.lua"
                    alias = config_home / "outside-alias"
                    alias.symlink_to("hypr", target_is_directory=True)
                elif setup_kind == "outside-managed-outside":
                    target = case_root / "external/user.lua"
                    target.parent.mkdir()
                    managed_bridge = hypr_dir / "bridge"
                    managed_bridge.symlink_to(
                        "../../external", target_is_directory=True
                    )
                    alias = config_home / "outside-chain"
                    alias.symlink_to("hypr/bridge", target_is_directory=True)
                elif setup_kind == "managed-root-alias":
                    target = case_root / "external-user.lua"
                else:
                    target = (config_home / preserved_rel).parent / link_text
                    target = target.resolve(strict=False)

                target.write_bytes(f"target-for-{name}\n".encode())
                preserved = config_home / preserved_rel
                preserved.parent.mkdir(parents=True, exist_ok=True)
                preserved.symlink_to(link_text)

                original_sentinel = sentinel.read_bytes()
                original_target = target.read_bytes()
                original_link_text = os.readlink(preserved)
                result = self.run_installer_shell(
                    """
                    mkdir -p "$CLONE_DIR/config/hypr" "$CLONE_DIR/config/quickshell/settings"
                    printf '%s\n' 'replacement-config' >"$CLONE_DIR/config/hypr/hyprland.lua"
                    printf '%s\n' 'bundled-user' >"$CLONE_DIR/config/hypr/user.lua"
                    printf '%s\n' 'return {}' >"$CLONE_DIR/config/hypr/tsugumori_options.lua"
                    printf '%s\n' 'bundled-settings' >"$CLONE_DIR/config/quickshell/settings/Settings.qml"
                    BACKUP_OLD=false
                    deploy_configs
                    """,
                    extra_env={"XDG_CONFIG_HOME": str(config_home)},
                )

                self.assertNotEqual(result.returncode, 0)
                self.assertIn(str(preserved), result.stderr)
                self.assertIn(link_text, result.stderr)
                self.assertIn("deployment would remove", result.stderr)
                self.assertIn("Move the target outside", result.stderr)
                self.assertEqual(sentinel.read_bytes(), original_sentinel)
                self.assertTrue(preserved.is_symlink())
                self.assertEqual(os.readlink(preserved), original_link_text)
                self.assertEqual(target.read_bytes(), original_target)
                if setup_kind == "intermediate":
                    self.assertTrue(intermediate.is_symlink())
                    self.assertEqual(
                        os.readlink(intermediate), "../external/Settings.qml"
                    )
                elif setup_kind == "outside-alias":
                    self.assertTrue(alias.is_symlink())
                    self.assertEqual(os.readlink(alias), "hypr")
                elif setup_kind == "outside-managed-outside":
                    self.assertTrue(alias.is_symlink())
                    self.assertEqual(os.readlink(alias), "hypr/bridge")
                    self.assertTrue(managed_bridge.is_symlink())
                    self.assertEqual(os.readlink(managed_bridge), "../../external")
                elif setup_kind == "managed-root-alias":
                    self.assertTrue(hypr_dir.is_symlink())
                    self.assertEqual(os.readlink(hypr_dir), "../external-hypr")
                if preserved_rel != "hypr/user.lua":
                    user_lua = hypr_dir / "user.lua"
                    self.assertFalse(user_lua.exists())
                    self.assertFalse(user_lua.is_symlink())

    def assert_unsafe_preserved_symlink_fails_before_replacement(
        self, link_text: str
    ) -> subprocess.CompletedProcess[str]:
        hypr_dir = self.config_home / "hypr"
        hypr_dir.mkdir(parents=True)
        managed = hypr_dir / "hyprland.lua"
        managed.write_text("original-config\n", encoding="utf-8")
        (hypr_dir / "user.lua").symlink_to(link_text)

        result = self.run_installer_shell(
            """
            mkdir -p "$CLONE_DIR/config/hypr"
            printf '%s\n' 'replacement-config' >"$CLONE_DIR/config/hypr/hyprland.lua"
            printf '%s\n' 'bundled-user' >"$CLONE_DIR/config/hypr/user.lua"
            printf '%s\n' 'return {}' >"$CLONE_DIR/config/hypr/tsugumori_options.lua"
            BACKUP_OLD=false
            deploy_configs
            """
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(managed.read_text(encoding="utf-8"), "original-config\n")
        self.assertTrue((hypr_dir / "user.lua").is_symlink())
        self.assertEqual(os.readlink(hypr_dir / "user.lua"), link_text)
        return result

    def test_dangling_preserved_symlink_fails_before_config_replacement(self) -> None:
        result = self.assert_unsafe_preserved_symlink_fails_before_replacement(
            "../missing-user.lua"
        )

        self.assertIn("dangling symlink", result.stderr)

    def test_preserved_symlink_to_directory_fails_before_config_replacement(self) -> None:
        directory_target = self.config_home / "custom-directory"
        directory_target.mkdir()
        result = self.assert_unsafe_preserved_symlink_fails_before_replacement(
            "../custom-directory"
        )

        self.assertIn("does not resolve to a regular file", result.stderr)

    def test_preflight_rejects_incompatible_realpath_before_sudo(self) -> None:
        sudo_log_dir = self.root / "sudo-log"
        sudo_log_dir.mkdir()
        sudo_log_dir.chmod(0o777)
        sudo_log = sudo_log_dir / "calls"
        self.write_executable("pacman", "#!/bin/sh\nexit 0\n")
        self.write_executable("curl", "#!/bin/sh\nexit 0\n")
        self.write_executable(
            "sudo",
            """
            #!/bin/sh
            printf 'called\n' >"$FAKE_SUDO_LOG"
            exit 99
            """,
        )
        self.write_executable("realpath", "#!/bin/sh\nexit 64\n")

        result = self.run_installer_shell(
            f'PATH="{self.fake_bin}"\npreflight\n',
            extra_env={"FAKE_SUDO_LOG": str(sudo_log)},
            drop_root_privileges=True,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("GNU realpath with --canonicalize-missing", result.stderr)
        self.assertFalse(sudo_log.exists())

    def run_fake_validation(
        self,
        user_source: str,
        *,
        relative_symlink: bool = False,
        extra_env: dict[str, str] | None = None,
    ) -> tuple[subprocess.CompletedProcess[str], list[str]]:
        verify_log = self.install_fake_hyprland_tools()
        (self.config_home / "hypr").mkdir(parents=True, exist_ok=True)
        user_lua = self.config_home / "hypr/user.lua"
        if relative_symlink:
            target = self.config_home / "external-user.lua"
            target.write_text(user_source, encoding="utf-8")
            user_lua.symlink_to("../external-user.lua")
        else:
            user_lua.write_text(user_source, encoding="utf-8")
        env = {
            "PATH": f"{self.fake_bin}{os.pathsep}{self.env['PATH']}",
            "FAKE_VERIFY_LOG": str(verify_log),
        }
        if extra_env:
            env.update(extra_env)
        result = self.run_installer_shell(
            """
            mkdir -p "$CLONE_DIR/config/hypr"
            printf '%s\n' 'bundled-config' >"$CLONE_DIR/config/hypr/hyprland.lua"
            printf '%s\n' 'bundled-user' >"$CLONE_DIR/config/hypr/user.lua"
            VM_GL_TWEAKS=true
            BOOT_WALLPAPER_VM=true
            write_tsugumori_options "$CLONE_DIR/config/hypr/tsugumori_options.lua" false
            validate_hyprland_config
            """,
            extra_env=env,
        )
        lines = verify_log.read_text(encoding="utf-8").splitlines() if verify_log.exists() else []
        return result, lines

    def test_hyprland_validates_bundled_then_effective_candidate(self) -> None:
        result, lines = self.run_fake_validation("preserved-user\n")

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(lines), 2)
        self.assertIn("bundled-user;", lines[0])
        self.assertIn("preserved-user;", lines[1])
        for line in lines:
            self.assertIn("vm_software_gl = true", line)
            self.assertIn("boot_wallpaper = true", line)

    def test_invalid_preserved_user_lua_fails_candidate_validation(self) -> None:
        result, lines = self.run_fake_validation("INVALID_OVERRIDE\n")

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(lines), 2)
        self.assertIn("candidate Lua configuration", result.stderr)

    def test_relative_user_lua_symlink_is_dereferenced_only_for_validation(self) -> None:
        result, lines = self.run_fake_validation(
            "relative-symlink-user\n", relative_symlink=True
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(lines), 2)
        self.assertIn("relative-symlink-user;", lines[1])
        user_lua = self.config_home / "hypr/user.lua"
        self.assertTrue(user_lua.is_symlink())
        self.assertEqual(os.readlink(user_lua), "../external-user.lua")

    def test_hyprland_below_native_lua_floor_is_rejected(self) -> None:
        result, lines = self.run_fake_validation(
            "preserved-user\n",
            extra_env={
                "FAKE_HYPRLAND_VERSION": "0.54.0-1",
                "FAKE_VERCMP_RESULT": "-1",
            },
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(lines, [])
        self.assertIn("0.55.2 or newer", result.stderr)

    def test_main_prepares_options_before_validation_and_deployment(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        main_body = source.split("main() {", 1)[1].split("\n}", 1)[0]

        render = main_body.index('write_tsugumori_options "$CLONE_DIR/config/hypr/tsugumori_options.lua"')
        validate = main_body.index("validate_hyprland_config")
        deploy = main_body.index("deploy_configs")
        self.assertLess(render, validate)
        self.assertLess(validate, deploy)
        self.assertNotIn("apply_vm_software_gl_tweaks_deployed", source)
        self.assertNotIn("exec-once = sleep 4 && awww img", source)
        self.assertNotIn("hyprland.conf", source)

    def test_wallpaper_client_and_daemon_are_both_required(self) -> None:
        empty_bin = self.root / "empty-bin"
        empty_bin.mkdir()
        missing = self.run_installer_shell(
            f'PATH="{empty_bin}"\nvalidate_wallpaper_runtime\n'
        )
        self.assertNotEqual(missing.returncode, 0)
        self.assertIn("awww was not installed", missing.stderr)

        self.write_executable("awww", "#!/bin/sh\nexit 0\n")
        self.write_executable("awww-daemon", "#!/bin/sh\nexit 0\n")
        present = self.run_installer_shell(
            f'PATH="{self.fake_bin}"\nvalidate_wallpaper_runtime\n'
        )
        self.assertEqual(present.returncode, 0, present.stderr)


if __name__ == "__main__":
    unittest.main()
