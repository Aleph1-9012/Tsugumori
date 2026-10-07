from __future__ import annotations

import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import textwrap
import unittest


REPO_ROOT = Path(__file__).parents[3]
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
        installer_args: tuple[str, ...] = (),
    ) -> subprocess.CompletedProcess[str]:
        env = self.env.copy()
        if extra_env:
            env.update(extra_env)
        script = 'source "$INSTALLER_UNDER_TEST" "$@"\n' + textwrap.dedent(body)
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
            ["/usr/bin/bash", "-c", script, "installer-test", *installer_args],
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

    def test_fish_installation_is_opt_in_and_honors_cli_flag(self) -> None:
        cases = (
            ("n", (), "false"),
            ("", (), "false"),
            ("y", (), "true"),
            (None, ("--fish",), "true"),
        )
        for answer, args, expected in cases:
            with self.subTest(answer=answer, args=args):
                answers = ["n", "n", "n"]
                if answer is not None:
                    answers.append(answer)
                answers.extend(["n", "n", "n"])
                body = "collect_choices <<'ANSWERS'\n" + "\n".join(answers)
                body += '\nANSWERS\nprintf "fish=%s\\n" "$INSTALL_FISHRC"\n'
                result = self.run_installer_shell(
                    body,
                    extra_env={"TSUGUMORI_VM": "0"},
                    installer_args=args,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.splitlines()[-1], f"fish={expected}")

    def collect_bashrc(self, answers: list[str]) -> subprocess.CompletedProcess:
        body = "collect_choices <<'ANSWERS'\n" + "\n".join(answers)
        body += '\nANSWERS\nprintf "bashrc=%s\\n" "$INSTALL_BASHRC"\n'
        return self.run_installer_shell(
            body, extra_env={"TSUGUMORI_VM": "0"})

    def test_bashrc_replacement_without_backups_requires_confirmation(self) -> None:
        (self.home / ".bashrc").write_text("# personal\n", encoding="utf-8")
        # backup=n, wallpapers=n, bashrc=y, confirm=<default n>, fish, nautilus, services, vm
        result = self.collect_bashrc(["n", "n", "y", "", "n", "n", "n", "n"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[-1], "bashrc=false")

        result = self.collect_bashrc(["n", "n", "y", "y", "n", "n", "n", "n"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[-1], "bashrc=true")

    def test_bashrc_prompt_is_skipped_with_backups_or_no_existing_file(self) -> None:
        (self.home / ".bashrc").write_text("# personal\n", encoding="utf-8")
        # Backups on: the extra question is never asked.
        result = self.collect_bashrc(["y", "n", "y", "n", "n", "n", "n"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[-1], "bashrc=true")

        (self.home / ".bashrc").unlink()
        # Backups off but nothing to replace: still no extra question.
        result = self.collect_bashrc(["n", "n", "y", "n", "n", "n", "n"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines()[-1], "bashrc=true")

    def test_services_prompt_mentions_bluetooth(self) -> None:
        prompt = re.search(r'ask_yn "([^"]*services[^"]*)"', INSTALLER.read_text())
        self.assertIsNotNone(prompt)
        self.assertIn("Bluetooth", prompt[1])

    def test_bashrc_adds_local_bin_once_and_before_personal_overrides(self) -> None:
        bashrc = REPO_ROOT / "config/bash/.bashrc"
        (self.home / ".bashrc.local").write_text(
            'export PATH="/custom/bin:$PATH"\n', encoding="utf-8")
        local_bin = f"{self.home}/.local/bin"
        for already_present in (False, True):
            with self.subTest(already_present=already_present):
                path = "/usr/bin:/bin"
                if already_present:
                    path = f"{local_bin}:{path}"
                env = {**os.environ, "HOME": str(self.home),
                       "XDG_CONFIG_HOME": str(self.config_home),
                       "PATH": path, "TERM": "dumb"}
                result = subprocess.run(
                    ["bash", "--rcfile", str(bashrc), "-i", "-c",
                     'printf "%s\\n" "$PATH"'],
                    env=env, capture_output=True, text=True, timeout=10)
                entries = result.stdout.strip().splitlines()[-1].split(":")
                self.assertEqual(entries[0], "/custom/bin")
                self.assertEqual(entries[1], local_bin)
                self.assertEqual(entries.count(local_bin), 1)

    def test_package_install_uses_nautilus_without_removed_apps(self) -> None:
        package_log = self.root / "installed-packages"
        self.write_executable("pacman", "#!/bin/sh\nexit 1\n")
        self.write_executable(
            "sudo",
            '#!/bin/sh\nprintf \'%s\\n\' "$@" >"$PACKAGE_LOG"\n',
        )
        result = self.run_installer_shell(
            """
            mkdir -p "$CLONE_DIR/packages"
            cp "$PACKAGE_MANIFEST" "$CLONE_DIR/packages/pacman.txt"
            install_packages
            """,
            extra_env={
                "PATH": f"{self.fake_bin}{os.pathsep}{self.env['PATH']}",
                "PACKAGE_LOG": str(package_log),
                "PACKAGE_MANIFEST": str(REPO_ROOT / "packages/pacman.txt"),
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        args = package_log.read_text().splitlines()
        self.assertEqual(args[:4], ["pacman", "-S", "--needed", "--noconfirm"])
        packages = set(args[4:])
        self.assertTrue({"nautilus", "gtk3", "python-gobject"} <= packages)
        removed = {
            "1password", "1password-beta", "aether", "alacritty", "brave-bin",
            "xournalpp", "yazi", "vivaldi", "vivaldi-ffmpeg-codecs",
            "signal-desktop", "kdeconnect",
        }
        self.assertFalse(packages & removed)

    @unittest.skipUnless(shutil.which("xdg-mime"), "xdg-mime is not installed")
    def test_default_file_manager_keeps_other_mime_associations(self) -> None:
        associations = self.config_home / "mimeapps.list"
        associations.write_text(
            "[Default Applications]\n"
            "inode/directory=yazi.desktop\n"
            "text/plain=editor.desktop\n"
        )
        result = self.run_installer_shell("configure_file_manager")
        self.assertEqual(result.returncode, 0, result.stderr)
        settings = associations.read_text()
        self.assertIn("inode/directory=org.gnome.Nautilus.desktop", settings)
        self.assertIn("text/plain=editor.desktop", settings)

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

    def test_install_lock_background_prefers_the_bundled_tsugumori_asset(self) -> None:
        result = self.run_installer_shell(
            """
            mkdir -p "$CLONE_DIR/assets/wallpapers" "$CONFIG_HOME/hypr"
            printf '%s\n' 'bundled-tsugumori-lock' >"$CLONE_DIR/assets/wallpapers/Aleph1.png"
            install_lock_background
            printf 'mode=%s\n' "$(stat -c '%a' "$CONFIG_HOME/hypr/lockbg.png")"
            """
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Installed Hyprlock background", result.stdout)
        self.assertIn("mode=644\n", result.stdout)
        self.assertEqual(
            (self.config_home / "hypr/lockbg.png").read_bytes(),
            b"bundled-tsugumori-lock\n",
        )

    def test_bundled_font_assets_are_installed_per_user(self) -> None:
        data_home = self.root / "data"
        cache_log = self.root / "font-cache.log"
        self.write_executable(
            "fc-cache",
            """
            #!/bin/sh
            printf '%s\n' "$@" >"$FAKE_FONT_CACHE_LOG"
            """,
        )

        result = self.run_installer_shell(
            """
            source_dir="$CLONE_DIR/assets/fonts/share-tech-mono"
            mkdir -p "$source_dir"
            printf '%s\n' 'font-bytes' >"$source_dir/ShareTechMono-Regular.ttf"
            printf '%s\n' 'license-text' >"$source_dir/OFL.txt"
            plex_source="$CLONE_DIR/config/quickshell/assets/fonts/ibm-plex-mono"
            mkdir -p "$plex_source"
            for asset in IBMPlexMono-Regular.ttf IBMPlexMono-Medium.ttf OFL.txt; do
                printf '%s\n' "$asset" >"$plex_source/$asset"
            done
            install_font_assets
            font_dir="$XDG_DATA_HOME/fonts/Tsugumori"
            stat -c 'font-mode=%a' "$font_dir/ShareTechMono-Regular.ttf"
            stat -c 'license-mode=%a' "$font_dir/OFL.txt"
            shopt -s nullglob
            leftovers=("$font_dir"/.*.??????)
            printf 'temporary-files=%s\n' "${#leftovers[@]}"
            """,
            extra_env={
                "XDG_DATA_HOME": str(data_home),
                "PATH": f"{self.fake_bin}{os.pathsep}{self.env['PATH']}",
                "FAKE_FONT_CACHE_LOG": str(cache_log),
            },
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        font_dir = data_home / "fonts/Tsugumori"
        self.assertEqual(
            (font_dir / "ShareTechMono-Regular.ttf").read_bytes(), b"font-bytes\n"
        )
        self.assertEqual((font_dir / "OFL.txt").read_bytes(), b"license-text\n")
        for asset in ("IBMPlexMono-Regular.ttf", "IBMPlexMono-Medium.ttf", "OFL.txt"):
            installed = font_dir / "ibm-plex-mono" / asset
            self.assertEqual(installed.read_text(), asset + "\n")
            self.assertEqual(installed.stat().st_mode & 0o777, 0o644)
        self.assertFalse(list((font_dir / "ibm-plex-mono").glob(".*")))
        self.assertIn("font-mode=644\n", result.stdout)
        self.assertIn("license-mode=644\n", result.stdout)
        self.assertIn("temporary-files=0\n", result.stdout)
        self.assertIn(str(font_dir), cache_log.read_text(encoding="utf-8"))

    def test_missing_bundled_font_leaves_installed_fonts_unchanged(self) -> None:
        data_home = self.root / "data"
        result = self.run_installer_shell(
            """
            source_dir="$CLONE_DIR/assets/fonts/share-tech-mono"
            mkdir -p "$source_dir"
            printf '%s\\n' 'new-font' >"$source_dir/ShareTechMono-Regular.ttf"
            printf '%s\\n' 'license' >"$source_dir/OFL.txt"
            plex_source="$CLONE_DIR/config/quickshell/assets/fonts/ibm-plex-mono"
            mkdir -p "$plex_source"
            printf '%s\\n' 'new-plex-font' >"$plex_source/IBMPlexMono-Regular.ttf"
            printf '%s\\n' 'license' >"$plex_source/OFL.txt"
            font_dir="$XDG_DATA_HOME/fonts/Tsugumori"
            mkdir -p "$font_dir"
            printf '%s\\n' 'keep-installed-font' >"$font_dir/ShareTechMono-Regular.ttf"
            install_font_assets
            """,
            extra_env={"XDG_DATA_HOME": str(data_home)},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Bundled IBM Plex Mono asset is missing or empty: IBMPlexMono-Medium.ttf",
                      result.stderr)
        font_dir = data_home / "fonts/Tsugumori"
        self.assertEqual((font_dir / "ShareTechMono-Regular.ttf").read_bytes(),
                         b"keep-installed-font\n")
        self.assertEqual([p.name for p in font_dir.iterdir()], ["ShareTechMono-Regular.ttf"])

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

    def make_deployment_fixture(self) -> Path:
        fixture = self.root / "fixture"
        files = {
            "hypr/hyprland.lua": "new-managed-config\n",
            "hypr/user.lua": "bundled-user\n",
            "quickshell/settings/Settings.qml": "bundled-settings\n",
            "waybar/config": "new-bar\n",
            "kitty/kitty.conf": "new-kitty\n",
        }
        for rel, contents in files.items():
            target = fixture / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(contents)
        for rel in ("hypr/user.lua", "hypr/user.conf", "quickshell/settings/Settings.qml"):
            target = self.config_home / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("keep-" + rel + "\n")
        (self.config_home / "hypr/hyprland.lua").write_text("old-managed-config\n")
        return fixture

    def test_failed_deployment_restores_preserved_files_without_backups(self) -> None:
        fixture = self.make_deployment_fixture()
        result = self.run_installer_shell(
            """
            mkdir -p "$CLONE_DIR"
            cp -r "$FIXTURE" "$CLONE_DIR/config"
            cp() {
                if [[ "$1" == "-r" && "$2" == "$CLONE_DIR/config/waybar" ]]; then
                    printf '%s' "$PRESERVED_STASH" >"$STASH_LOG"
                    return 73
                fi
                command cp "$@"
            }
            BACKUP_OLD=false
            deploy_configs
            """,
            extra_env={"FIXTURE": str(fixture), "STASH_LOG": str(self.root / "stash-path")},
        )
        self.assertEqual(result.returncode, 73, result.stderr)
        self.assertEqual((self.config_home / "hypr/hyprland.lua").read_text(), "new-managed-config\n")
        for rel in ("hypr/user.lua", "hypr/user.conf", "quickshell/settings/Settings.qml"):
            self.assertEqual((self.config_home / rel).read_text(), "keep-" + rel + "\n")
        self.assertFalse(Path((self.root / "stash-path").read_text()).exists())
        self.assertFalse(list(self.home.glob(".config-backup-*")))

    def test_failed_recovery_retains_all_preserved_copies(self) -> None:
        fixture = self.make_deployment_fixture()
        result = self.run_installer_shell(
            """
            mkdir -p "$CLONE_DIR"
            cp -r "$FIXTURE" "$CLONE_DIR/config"
            cp() {
                if [[ "$1" == "-r" && "$2" == "$CLONE_DIR/config/waybar" ]]; then
                    printf '%s' "$PRESERVED_STASH" >"$STASH_LOG"
                    return 73
                fi
                command cp "$@"
            }
            mv() {
                if [[ "${*: -1}" == "$CONFIG_HOME/hypr/user.lua" ]]; then
                    return 74
                fi
                command mv "$@"
            }
            BACKUP_OLD=false
            deploy_configs
            """,
            extra_env={"FIXTURE": str(fixture), "STASH_LOG": str(self.root / "stash-path")},
        )
        self.assertEqual(result.returncode, 73, result.stderr)
        stash = Path((self.root / "stash-path").read_text())
        self.assertIn(str(stash), result.stdout)
        for rel in ("hypr/user.lua", "hypr/user.conf", "quickshell/settings/Settings.qml"):
            self.assertEqual((stash / rel).read_text(), "keep-" + rel + "\n")

    def test_dangling_managed_destination_fails_before_replacing_configs(self) -> None:
        fixture = self.make_deployment_fixture()
        (self.config_home / "kitty").symlink_to(self.root / "missing-kitty")
        result = self.run_installer_shell(
            """
            mkdir -p "$CLONE_DIR"
            cp -r "$FIXTURE" "$CLONE_DIR/config"
            BACKUP_OLD=false
            deploy_configs
            """,
            extra_env={"FIXTURE": str(fixture)},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("dangling symlink", result.stderr)
        self.assertEqual((self.config_home / "hypr/hyprland.lua").read_text(), "old-managed-config\n")
        self.assertEqual((self.config_home / "hypr/user.lua").read_text(), "keep-hypr/user.lua\n")

    def test_qshare_keeps_or_backs_up_foreign_commands(self) -> None:
        script = self.config_home / "quickshell/scripts/qshare.py"
        script.parent.mkdir(parents=True)
        script.write_text("# bundled qshare\n")
        for backup in (False, True):
            for symlink in (False, True):
                with self.subTest(backup=backup, symlink=symlink):
                    home = self.root / f"qshare-{backup}-{symlink}"
                    command = home / ".local/bin/qshare"
                    command.parent.mkdir(parents=True)
                    if symlink:
                        target = home / "personal-qshare"
                        target.write_text("personal command\n")
                        command.symlink_to("../../personal-qshare")
                    else:
                        command.write_text("personal command\n")
                    result = self.run_installer_shell(
                        """
                        BACKUP_OLD="$BACKUP_CHOICE"
                        deploy_qshare_symlink
                        printf 'backup=%s\n' "$BACKUP_DIR/bin/qshare"
                        """,
                        extra_env={"HOME": str(home), "BACKUP_CHOICE": str(backup).lower()},
                    )
                    self.assertEqual(result.returncode, 0, result.stderr)
                    saved = Path(result.stdout.split("backup=", 1)[1].strip())
                    if backup:
                        self.assertEqual(os.readlink(command), str(script))
                        if symlink:
                            self.assertTrue(saved.is_symlink())
                            self.assertEqual(os.readlink(saved), "../../personal-qshare")
                            self.assertEqual(target.read_text(), "personal command\n")
                        else:
                            self.assertEqual(saved.read_text(), "personal command\n")
                    else:
                        self.assertEqual(command.read_text(), "personal command\n")
                        self.assertEqual(command.is_symlink(), symlink)
                        self.assertFalse(saved.exists())

    def test_fish_fragment_preserves_existing_config_and_uses_xdg_home(self) -> None:
        fish_dir = self.config_home / "fish"
        fish_dir.mkdir()
        personal = self.root / "personal.fish"
        personal.write_text("set -gx PERSONAL_SETTING keep\n")
        (fish_dir / "config.fish").symlink_to(personal)
        override = fish_dir / "config.fish.local"
        override.write_text("set -gx PERSONAL_OVERRIDE keep\n")
        self.write_executable("fish", "#!/bin/sh\nexit 0\n")
        result = self.run_installer_shell(
            """
            mkdir -p "$CLONE_DIR/config/fish/conf.d"
            cp "$FISH_FRAGMENT" "$CLONE_DIR/config/fish/conf.d/tsugumori.fish"
            INSTALL_FISHRC=true
            BACKUP_OLD=false
            deploy_fish_config
            """,
            extra_env={
                "PATH": f"{self.fake_bin}{os.pathsep}{self.env['PATH']}",
                "FISH_FRAGMENT": str(REPO_ROOT / "config/fish/conf.d/tsugumori.fish"),
            },
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((fish_dir / "config.fish").is_symlink())
        self.assertEqual(personal.read_text(), "set -gx PERSONAL_SETTING keep\n")
        self.assertEqual(override.read_text(), "set -gx PERSONAL_OVERRIDE keep\n")
        self.assertTrue((fish_dir / "conf.d/tsugumori.fish").is_file())
        self.assertFalse((self.home / ".config/fish").exists())

    @unittest.skipUnless(shutil.which("fish"), "Fish is not installed")
    def test_fish_fragment_loads_xdg_override_and_allows_personal_config(self) -> None:
        fish_dir = self.config_home / "fish"
        (fish_dir / "conf.d").mkdir(parents=True)
        shutil.copyfile(REPO_ROOT / "config/fish/conf.d/tsugumori.fish", fish_dir / "conf.d/tsugumori.fish")
        (fish_dir / "config.fish.local").write_text("set -gx TSUGUMORI_TEST_OVERRIDE loaded\n")
        (fish_dir / "config.fish").write_text("function ls; printf 'personal-ls\\n'; end\n")
        env = {**self.env, "TERM": "xterm-256color"}
        result = subprocess.run(
            [shutil.which("fish"), "-i", "-c", "printf '%s\\n' $TSUGUMORI_TEST_OVERRIDE; ls"],
            env=env, text=True, capture_output=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "loaded\npersonal-ls\n")
        result = subprocess.run(
            [shutil.which("fish"), "-c", "printf command-ran"],
            env=env, text=True, capture_output=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "command-ran")

    def test_pinned_missing_manifest_fails_before_package_changes(self) -> None:
        self.write_executable("git", "#!/bin/sh\nexit 0\n")
        self.write_executable("sudo", '#!/bin/sh\nprintf called >"$PACKAGE_LOG"\n')
        result = self.run_installer_shell(
            """
            clone_repo() {
                mkdir -p "$CLONE_DIR/packages"
                printf 'hyprland\n' >"$CLONE_DIR/packages/pacman.txt"
            }
            PINNED_MODE=true
            prepare_repository
            install_packages
            """,
            extra_env={
                "PATH": f"{self.fake_bin}{os.pathsep}{self.env['PATH']}",
                "PACKAGE_LOG": str(self.root / "packages-called"),
            },
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pinned-pacman.txt", result.stderr)
        self.assertFalse((self.root / "packages-called").exists())

    def test_main_prepares_options_before_validation_and_deployment(self) -> None:
        source = INSTALLER.read_text(encoding="utf-8")
        main_body = source.split("main() {", 1)[1].split("\n}", 1)[0]

        render = main_body.index('write_tsugumori_options "$CLONE_DIR/config/hypr/tsugumori_options.lua"')
        validate_font = main_body.index("validate_font_assets")
        install_font = main_body.index("install_font_assets")
        validate = main_body.index("validate_hyprland_config")
        deploy = main_body.index("deploy_configs")
        finalize = main_body.index("finalize")
        self.assertLess(main_body.index("prepare_repository"), main_body.index("install_packages"))
        self.assertLess(validate_font, deploy)
        self.assertLess(deploy, install_font)
        self.assertLess(install_font, finalize)
        self.assertLess(render, validate)
        self.assertLess(validate, deploy)

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
