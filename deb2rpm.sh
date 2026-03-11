#!/usr/bin/env bash

set -euo pipefail

# ─────────────────────────────────────────────
# deb2rpm.sh — Convert a .deb package to .rpm
# Usage: ./deb2rpm.sh <package.deb>
# ─────────────────────────────────────────────

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLD='\033[1m'
RST='\033[0m'

info()  { echo -e "${BLD}[INFO]${RST}  $*"; }
ok()    { echo -e "${GRN}[OK]${RST}    $*"; }
warn()  { echo -e "${YLW}[WARN]${RST}  $*"; }
die()   { echo -e "${RED}[ERROR]${RST} $*" >&2; exit 1; }

# ── 1. Argument check ────────────────────────
[[ $# -lt 1 ]]         && die "No input file given.\n       Usage: $0 <package.deb>"
[[ ! -f "$1" ]]        && die "File not found: $1"
[[ "$1" != *.deb ]]    && warn "File does not have a .deb extension — continuing anyway."

DEB_FILE="$(realpath "$1")"
OUTPUT_DIR="$(dirname "$DEB_FILE")"

# ── 2. Dependency check ──────────────────────
info "Checking dependencies..."
MISSING=()
for cmd in alien rpmrebuild rpmbuild; do
    if ! command -v "$cmd" &>/dev/null; then
        MISSING+=("$cmd")
    fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    die "Missing required tools: ${MISSING[*]}\n       Install with: sudo apt install alien rpm rpm-build rpmrebuild"
fi
ok "All dependencies found."

# ── 3. alien conversion ──────────────────────
info "Converting '$DEB_FILE' to .rpm (this may take a moment)..."
cd "$OUTPUT_DIR"

ALIEN_OUTPUT="$(sudo alien -kr "$DEB_FILE" 2>&1)"
echo "$ALIEN_OUTPUT"

# Parse the generated .rpm filename from alien's output
GENERATED_RPM="$(echo "$ALIEN_OUTPUT" | grep -oP '[\w.+-]+\.rpm' | head -1)"

if [[ -z "$GENERATED_RPM" ]]; then
    # Fallback: find the newest .rpm in the directory
    GENERATED_RPM="$(ls -t "$OUTPUT_DIR"/*.rpm 2>/dev/null | head -1)"
    [[ -z "$GENERATED_RPM" ]] && die "alien did not produce an .rpm file."
else
    GENERATED_RPM="$OUTPUT_DIR/$GENERATED_RPM"
fi

[[ ! -f "$GENERATED_RPM" ]] && die "Expected RPM not found: $GENERATED_RPM"
ok "alien produced: $GENERATED_RPM"

# ── 4. rpmrebuild + spec patch ───────────────
info "Rebuilding RPM with rpmrebuild (editing spec)..."

# rpmrebuild -d sets the output directory; -e opens editor; -p uses a script instead.
# We patch the spec in-place by setting EDITOR to a sed one-liner.
PATCH_SCRIPT="$(mktemp /tmp/patch_spec.XXXXXX.sh)"
cat > "$PATCH_SCRIPT" <<'PATCH'
#!/usr/bin/env bash
# Called by rpmrebuild as $EDITOR <specfile>
sed -i '/%dir %attr(0755, root, root) "\/usr\/bin"/d' "$1"
PATCH
chmod +x "$PATCH_SCRIPT"

EDITOR="$PATCH_SCRIPT" rpmrebuild -d /tmp -ep "$GENERATED_RPM"

rm -f "$PATCH_SCRIPT"

# ── 5. Move rebuilt RPM next to original ─────
info "Locating rebuilt RPM in /tmp..."

# rpmrebuild -d /tmp places the file under /tmp/<arch>/ (e.g. /tmp/x86_64/)
RPM_BASENAME="$(basename "$GENERATED_RPM")"
REBUILT_RPM="$(find /tmp -maxdepth 3 -name "*.rpm" 2>/dev/null \
    | grep -F "$RPM_BASENAME" | head -1)"

if [[ -z "$REBUILT_RPM" ]]; then
    # Basename match failed — grab the newest .rpm anywhere under /tmp
    REBUILT_RPM="$(find /tmp -maxdepth 3 -name "*.rpm" -newer "$GENERATED_RPM" 2>/dev/null | head -1)"
fi

[[ -z "$REBUILT_RPM" ]] && die "Could not locate rebuilt RPM under /tmp.\nTry finding it manually with: find /tmp -name '*.rpm'"
ok "Rebuilt RPM: $REBUILT_RPM"

FINAL_RPM="$OUTPUT_DIR/$(basename "$REBUILT_RPM")"
cp "$REBUILT_RPM" "$FINAL_RPM"

ok "Final RPM placed at: ${BLD}$FINAL_RPM${RST}"
