"""Evaluate URL assignments only; never run packaging or appcast signing."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
REPO = "https://github.com/advaitpaliwal/sidekick"


def assignment(script, variable, overrides=None):
    line = next(
        line for line in (ROOT / "Scripts" / script).read_text().splitlines()
        if line.startswith(f"{variable}=")
    )
    env = {
        key: value for key, value in os.environ.items()
        if not key.startswith(("SIDEKICK_", "CLIPPY_", "SPARKLE_"))
        and key not in ("BASH_ENV", "ENV")
    }
    env.update(overrides or {})
    return subprocess.check_output(
        ["/bin/bash", "--noprofile", "--norc", "-c",
         f'release_tag=v0.1.23\n{line}\nprintf "%s" "${{{variable}}}"'],
        env=env, text=True
    )


class RepositoryLinksTests(unittest.TestCase):
    def test_default_feed_and_generator_destinations(self):
        for script, variable, suffix in (
            ("package-sidekick-app.sh", "sparkle_feed_url", "/releases/latest/download/appcast.xml"),
            ("generate-sparkle-appcast.sh", "download_prefix", "/releases/download/v0.1.23/"),
            ("generate-sparkle-appcast.sh", "product_link", "/releases/latest"),
        ):
            with self.subTest(variable=variable):
                self.assertEqual(assignment(script, variable), REPO + suffix)

    def test_legacy_overrides_remain_and_personal_names_take_precedence(self):
        for script, variable, suffix in (
            ("package-sidekick-app.sh", "sparkle_feed_url", "SPARKLE_FEED_URL"),
            ("generate-sparkle-appcast.sh", "download_prefix", "DOWNLOAD_URL_PREFIX"),
            ("generate-sparkle-appcast.sh", "product_link", "PRODUCT_LINK"),
        ):
            with self.subTest(variable=variable):
                overrides = {f"CLIPPY_{suffix}": "https://legacy.example.test/"}
                self.assertEqual(assignment(script, variable, overrides), overrides[f"CLIPPY_{suffix}"])
                overrides[f"SIDEKICK_{suffix}"] = "https://custom.example.test/"
                self.assertEqual(assignment(script, variable, overrides), overrides[f"SIDEKICK_{suffix}"])

    def test_readme_advertises_actual_legacy_asset(self):
        readme = (ROOT / "README.md").read_text()
        self.assertIn(f"{REPO}/releases/download/v0.1.23/Clippy.dmg", readme)
        self.assertIn("legacy Clippy v0.1.23", readme)
        self.assertIn("not a release of the current Sidekick source", readme)
        self.assertNotIn("/download/Sidekick.dmg", readme)
        self.assertNotIn("companion-inc/sidekick", readme)

    def test_signed_feed_requirement_and_app_identity_remain(self):
        package = (ROOT / "Scripts/package-sidekick-app.sh").read_text()
        self.assertIn("<key>SURequireSignedFeed</key>\n  <true/>", package)
        self.assertIn("<string>ai.companion.sidekick</string>", package)
        generator = (ROOT / "Scripts/generate-sparkle-appcast.sh").read_text()
        self.assertIn('"$tools_dir/bin/generate_appcast"', generator)


if __name__ == "__main__":
    unittest.main()
