# Read VERSION, PATCHLEVEL, SUBLEVEL and EXTRAVERSION out of a kernel Makefile.
#
# Kept in its own file because embedding it in a shell string needs three
# levels of quoting, and every one of them breaks something.
#
# Usage:
#   read-version /path/to/Makefile
#
# Prints: VERSION PATCHLEVEL SUBLEVEL EXTRAVERSION
# EXTRAVERSION keeps its leading dash, so a Zen tree prints "-zen".

BEGIN { FS = "=" }

/^VERSION[ \t]*=/ {
    v = $2
    sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
    VERSION = v
}

/^PATCHLEVEL[ \t]*=/ {
    v = $2
    sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
    PATCHLEVEL = v
}

/^SUBLEVEL[ \t]*=/ {
    v = $2
    sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
    SUBLEVEL = v
}

/^EXTRAVERSION[ \t]*=/ {
    v = $2
    sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
    EXTRAVERSION = v
}

END {
    if (VERSION == "") {
        exit 1
    }
    printf "%s %s %s %s\n",
        VERSION,
        (PATCHLEVEL == "" ? "0" : PATCHLEVEL),
        (SUBLEVEL == "" ? "0" : SUBLEVEL),
        EXTRAVERSION
}