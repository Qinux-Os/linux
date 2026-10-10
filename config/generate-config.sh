#!/usr/bin/env bash
#
# generate-config.sh - turn the Zen fragment into the complete kernel config.
#
# Produces linux/config, the file the PKGBUILD installs and verify-config
# checks. Run it on the build host, not on the machine that pushes: it needs a
# toolchain and about 3 GB of free space for a kernel source tree.
#
# Usage:
#   generate-config.sh /path/to/zen-source-tree [FRAGMENT]
#
#   TREE      an unpacked Zen kernel source tree. The Zen tarball from
#             zenkernel.org unpacks to linux-zen-X.Y.Z-zenN/, which is this.
#   FRAGMENT  config fragment to apply. Default: ../config/zen.config
#
# Output: config, next to this script's repository root, i.e. ../config
#
# Why generated rather than checked in
#
# A complete config is roughly 18000 symbols and changes on every kernel
# update. Hand-maintained, the two symbols anyone actually decided on are
# invisible in a diff of a hundred unrelated churn. Generated, the base comes
# from the kernel and the fragment holds only the decisions, so reviewing the
# fragment reviews the decisions.
#
# Order matters and is not obvious
#
# The fragment is merged first and x86_64_defconfig second. defconfig resolves
# every symbol, so it overrides the fragment wherever the two disagree -- and
# for a symbol Zen added and defconfig has never heard of, defconfig's answer
# is to leave it unset. Applying the fragment last would survive that, but then
# a symbol the fragment does not mention keeps defconfig's value rather than
# the base's, and the result is neither.
#
# The way out is olddefconfig: it takes whatever is set as given, completes the
# rest from the base, and leaves the fragment's choices alone. It cannot
# introduce a conflict, because there is nothing to reconcile.

set -o errexit
set -o nounset
set -o pipefail

# Resolved before the default for FRAGMENT, so the default can be a plain
# reference rather than another nested command substitution.
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)

TREE=${1:-}
FRAGMENT=${2:-$REPO_DIR/config/zen.config}

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
log() { printf '==> %s\n' "$*" >&2; }

[[ -n "$TREE" ]] || die "usage: $0 /path/to/zen-source-tree [fragment]"
[[ -d "$TREE" ]] || die "not a directory: $TREE"
[[ -r "$FRAGMENT" ]] || die "cannot read fragment: $FRAGMENT"
[[ -r "$TREE/Makefile" ]] || die "no kernel Makefile in $TREE; is this a kernel source tree?"

for t in make gcc flex bison bc; do
    command -v "$t" >/dev/null 2>&1 || die "required tool not found: $t"
done

cd "$TREE"

# --- What version is this? -------------------------------------------------
#
# Read from the Makefile rather than taken from the tree's name, because the
# tree name is how the tarball was called and the Makefile is what actually
# gets compiled. They disagree often enough to matter.

# The awk program is in a double-quoted heredoc so that $3 and $0 reach awk
# rather than being expanded by this shell.
read -r VERSION PATCHLEVEL SUBLEVEL EXTRAVERSION <<EOF
$(awk -f "$SCRIPT_DIR/read-version.awk" "$TREE/Makefile")
EOF

[[ -n "${VERSION:-}" ]] || die "could not read the version from $TREE/Makefile"

# EXTRAVERSION is -zen for every Zen build, which is the marker that this tree
# really is Zen and not a vanilla kernel someone pointed the script at.
case "${EXTRAVERSION:-}" in
    *zen*) log "Zen tree: ${VERSION}.${PATCHLEVEL}.${SUBLEVEL}${EXTRAVERSION}" ;;
    *)     log "WARNING: EXTRAVERSION is '${EXTRAVERSION:-}', not -zen." \
                log "         This does not look like a Zen kernel." ;;
esac

OUT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/config

# --- Base -----------------------------------------------------------------

log "starting from x86_64_defconfig"
make -s x86_64_defconfig

# --- Fragment -------------------------------------------------------------

log "applying $(basename "$FRAGMENT")"
if ! ./scripts/kconfig/merge_config.sh -m -O "$TREE" "$FRAGMENT" 2>/dev/null; then
    # merge_config.sh moved or is not executable in this tree. Fall back to a
    # plain append, which is equivalent here: the fragment is applied before
    # olddefconfig, and olddefconfig is what resolves the rest.
    log "merge_config.sh unavailable, appending the fragment directly"
    cat "$FRAGMENT" >>"$TREE/.config"
fi

# --- Resolve --------------------------------------------------------------

log "resolving with olddefconfig"
# This is the step that matters. It keeps every symbol the fragment set,
# including ones defconfig has never heard of, and fills in the rest from the
# base. It does not resolve conflicts, because there is nothing to resolve.
make -s olddefconfig

# --- Record what the fragment actually achieved ----------------------------
#
# Counted before and after, because a fragment naming a symbol this kernel does
# not have is silently dropped by olddefconfig and the resulting config looks
# complete. A count that does not move is the signal that the fragment did
# nothing.

frag_symbols=$(grep -cE '^CONFIG_[A-Z0-9_]+=' "$FRAGMENT" || true)
kept=$(comm -12 \
        <(grep -oE '^CONFIG_[A-Z0-9_]+' "$FRAGMENT" | sort -u) \
        <(grep -oE '^CONFIG_[A-Z0-9_]+' "$TREE/.config" | sort -u) \
    | wc -l)
dropped=$(( frag_symbols - kept ))

log "fragment named $frag_symbols set symbols; $kept are set in the result"

if (( dropped > frag_symbols / 4 )); then
    log "WARNING: $dropped symbols did not survive. The likely cause is that"
    log "         this kernel version renamed or removed them. Compare:"
    log ""
    log "           comm -23 <(grep -oE '^CONFIG_[A-Z0-9_]+' '$FRAGMENT' | sort -u) \\"
    log "                    <(grep -oE '^CONFIG_[A-Z0-9_]+' '$TREE/.config' | sort -u)"
fi

# --- Stamp ----------------------------------------------------------------
#
# Written into the config as a comment so that a kernel built from this file
# says what produced it. Without it, six months later there is no way to tell
# a deliberate change from an accidental one.

{
    printf '\n#\n# Generated by generate-config.sh from %s\n' "$FRAGMENT"
    printf '# Kernel: %s.%s.%s%s\n' "$VERSION" "$PATCHLEVEL" "$SUBLEVEL" "${EXTRAVERSION:-}"
    printf '# Base:    x86_64_defconfig, fragment applied first\n'
    printf '# Regenerate rather than editing: see linux/README.md\n'
    printf '#\n'
} >>"$TREE/.config"

cp "$TREE/.config" "$OUT/config"
log "wrote $OUT/config ($(grep -c '^CONFIG_' "$OUT/config") symbols)"

# --- Verify ---------------------------------------------------------------

VERIFY="$OUT/scripts/verify-config"
if [[ -x "$VERIFY" ]]; then
    log "verifying"
    "$VERIFY" "$OUT/config" || die "generated config does not pass verification"
fi

log ""
log "done. Review the fragment, not the generated config."
