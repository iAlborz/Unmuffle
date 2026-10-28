"""Adds a release to a Sparkle appcast, newest first.
Usage: python3 scripts/appcast.py <appcast.xml> <zip> <version> <build> <download url> <release notes.md>
The zip is signed with the private key in the Keychain (account "unmuffle"). Only the "What's new" list of
the release notes goes into the appcast; Sparkle shows it in its update window."""
import datetime, html, re, subprocess, sys

appcast, zip_path, version, build, url, notes_path = sys.argv[1:7]
sign_update = ".build/artifacts/sparkle/Sparkle/bin/sign_update"
# Prints: sparkle:edSignature="..." length="..."
signature = subprocess.check_output([sign_update, "--account", "unmuffle", zip_path], text=True).strip()

notes = open(notes_path).read()
whats_new = re.search(r"^## What's new\n(.*?)(?=^## |\Z)", notes, re.S | re.M).group(1)
items = [re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", html.escape(m, quote=False))
         for m in re.findall(r"^- (.+)$", whats_new, re.M)]
notes_html = "<ul>" + "".join(f"<li>{i}</li>" for i in items) + "</ul>"

date = datetime.datetime.now(datetime.timezone.utc).strftime("%a, %d %b %Y %H:%M:%S +0000")
item = f"""    <item>
      <title>Unmuffle {version}</title>
      <pubDate>{date}</pubDate>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/iAlborz/Unmuffle/releases</sparkle:fullReleaseNotesLink>
      <description><![CDATA[{notes_html}]]></description>
      <enclosure url="{url}" type="application/octet-stream" {signature}/>
    </item>
"""
xml = open(appcast).read()
if f"<sparkle:version>{build}</sparkle:version>" in xml:
    sys.exit(f"build {build} is already in {appcast}")
xml = xml.replace("    <language>en</language>\n", "    <language>en</language>\n" + item, 1)
open(appcast, "w").write(xml)
print(f"added Unmuffle {version} ({build}) to {appcast}")
