#!/bin/bash
#
# Writes the licence notices shown in the About window.
#
#     ./Config/make-acknowledgements.sh
#
# Run it after adding, removing or updating a package, and commit the result.
# Build the app once first, so the packages are checked out.
#
# Every package the app ships is listed with its full licence text, because
# both licences in play ask for it: MIT wants its notice kept in copies of the
# software, and Apache 2.0 wants the licence and any NOTICE file passed on.
# Packages that only run while building, and never end up in the app, are left
# out. So are the licences of libraries vendored inside a package, which are
# listed under the package that carries them.

set -euo pipefail
cd "$(dirname "$0")/.."

RESOLVED=Typoless.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
OUTPUT=Typoless/Resources/Acknowledgements.txt

source Config/derived-data.sh
CHECKOUTS="$(source_packages_dir)/checkouts"

mkdir -p "$(dirname "$OUTPUT")"

python3 - "$RESOLVED" "$CHECKOUTS" "$OUTPUT" <<'PYTHON'
import json, os, sys

resolved, checkouts, output = sys.argv[1:]

# Macros and command-line tooling: used by the compiler, absent from the app.
BUILD_ONLY = {"swift-syntax", "swift-argument-parser"}

# Folders in which a package vendors other libraries, one folder each, every
# one carrying its own licence file. Found by looking rather than listed, so a
# library added in a later version is picked up instead of silently missing.
# The names are only for display; a folder without one shows its own name.
VENDOR_ROOTS = {"mlx-swift": "Source/Cmlx"}
VENDOR_NAMES = {"mlx": "MLX", "mlx-c": "MLX C", "json": "JSON for Modern C++"}

# Vendored code whose licence lives in a comment at the top of a source file
# rather than in a licence file, so no search for licence files can find it.
# pocketfft is compiled into MLX's CPU backend, and its BSD licence asks for the
# notice in every binary copy.
HEADER_NOTICES = {
    "mlx-swift": [("pocketfft", "Source/Cmlx/mlx/mlx/3rdparty/pocketfft.h")],
}

# Vendored trees checked and found absent from the app, so the warning below
# only speaks up for something new. swift-crypto builds BoringSSL only off
# Apple platforms and uses CryptoKit here; the app binary has no BoringSSL or
# fiat symbols.
NOT_SHIPPED = ("swift-crypto/Sources/CCryptoBoringSSL/",)

LICENCE_NAMES = ("LICENSE", "LICENSE.txt", "LICENSE.md", "LICENCE", "COPYING")
NOTICE_NAMES = ("NOTICE", "NOTICE.txt", "NOTICE.md")

def first_file(directory, names):
    for name in names:
        path = os.path.join(directory, name)
        if os.path.isfile(path):
            return path
    return None

def read(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read().strip()

def checkout_for(identity):
    """Checkouts are named after the repository, which can differ in case."""
    for entry in os.listdir(checkouts):
        if entry.lower() == identity.lower():
            return os.path.join(checkouts, entry)
    return None

def leading_comment(path):
    """The block comment a source file opens with, which is where a licence sits."""
    text = read(path)
    if not text.startswith("/*") or "*/" not in text:
        return None
    return text[2:text.index("*/")].strip()

def unlisted_third_party(directory, covered):
    """
    Source files kept in a 3rdparty or vendor folder that nothing above covers.

    Reported rather than fatal: such a folder often holds build tooling that
    never reaches the app. A new entry is still worth a look, because the one
    that was missed before was exactly this: a licence in a header comment,
    in a 3rdparty folder, compiled into the app.
    """
    found = []
    for base, folders, files in os.walk(directory):
        folders[:] = [folder for folder in folders if folder not in (".git", "Tests", "tests")]
        parts = set(base.split(os.sep))
        if not parts & {"3rdparty", "third_party", "vendor"}:
            continue
        for name in files:
            path = os.path.join(base, name)
            relative = os.path.relpath(path, checkouts)
            if path in covered or relative.startswith(NOT_SHIPPED):
                continue
            if name.endswith((".h", ".hpp", ".c", ".cc", ".cpp")):
                found.append(relative)
    return found

pins = json.load(open(resolved))["pins"]
sections = []
missing = []
unlisted = []

for pin in sorted(pins, key=lambda pin: pin["identity"].lower()):
    identity = pin["identity"]
    if identity in BUILD_ONLY:
        continue

    directory = checkout_for(identity)
    licence = directory and first_file(directory, LICENCE_NAMES)
    if not licence:
        missing.append(identity)
        continue

    version = pin["state"].get("version") or pin["state"].get("revision", "")[:12]
    parts = [f"{identity} {version}\n{pin['location']}", read(licence)]

    notice = first_file(directory, NOTICE_NAMES)
    if notice:
        parts.append(read(notice))

    root = VENDOR_ROOTS.get(identity)
    if root:
        for folder in sorted(os.listdir(os.path.join(directory, root))):
            vendored = first_file(os.path.join(directory, root, folder), LICENCE_NAMES + ("LICENSE.MIT",))
            if vendored:
                name = VENDOR_NAMES.get(folder, folder)
                parts.append(f"{name}, included in {identity}\n\n{read(vendored)}")

    for name, relative in HEADER_NOTICES.get(identity, []):
        path = os.path.join(directory, relative)
        notice = leading_comment(path) if os.path.isfile(path) else None
        if not notice:
            missing.append(f"{identity}/{relative}")
            continue
        parts.append(f"{name}, included in {identity}\n\n{notice}")

    sections.append("\n\n".join(parts))

    covered = {os.path.join(directory, relative) for _, relative in HEADER_NOTICES.get(identity, [])}
    unlisted.extend(unlisted_third_party(directory, covered))

if missing:
    sys.exit("No licence found for: " + ", ".join(missing))

rule = "\n\n" + "-" * 60 + "\n\n"
with open(output, "w", encoding="utf-8") as handle:
    handle.write(rule.join(sections) + "\n")

print(f"Wrote {len(sections)} packages to {output}")

if unlisted:
    print("Third-party sources without a notice here, check whether the app includes them:")
    for path in unlisted:
        print(f"  {path}")
PYTHON
