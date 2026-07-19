# shellcheck shell=bash
#
# probe_artifacts.sh -- the OPTIONAL "resolved state" layer.
#
# Everything above (repo, python, packages, toolchain) is static: it is true of a
# fresh clone. This section reports what a BUILD has actually produced on this
# machine, if anything -- the persistent package cache, the synced DBs, the
# offline local repo index, built ISOs in output/, and the logs. On a clean clone
# these directories don't exist and the whole section degrades to a single
# "no build artifacts present" line rather than erroring.
#
# This is what lets one script answer both "what is this project" and "what has
# my last build left on disk".
#
# Depends on: common.sh. Reads: cache/, output/, logs/.

probe_artifacts() {
    local root="$SPEC_REPO_ROOT"
    local cache="$root/cache" out="$root/output" logs="$root/logs"

    h2 "5. Build artifacts (resolved state)"

    if [ ! -d "$cache" ] && [ ! -d "$out" ] && [ ! -d "$logs" ]; then
        bullet "No build artifacts present -- this is a clean tree (nothing built yet)."
        note "Sections 1-4 fully describe the project without a build. Run the Docker build to populate \`cache/\`, \`output/\`, \`logs/\`."
        return
    fi

    kv "Combined artifact size" "$(hsize_total "$cache" "$out" "$logs")"

    # --- package cache ------------------------------------------------------
    blank
    h3 "5.1 Package cache -- \`cache/\`"
    if [ -d "$cache" ]; then
        local pacstrap="$cache/pacman-pkg" repo="$cache/pkgs/repo" syncdb="$cache/pkgs/db/sync"
        local ncache; ncache=$(count_glob "$pacstrap" "*.pkg.tar.zst")
        kv "pacstrap CacheDir (\`cache/pacman-pkg/\`)" "$ncache cached packages, $(hsize "$pacstrap")"
        if [ -d "$repo" ]; then
            local nrepo; nrepo=$(count_glob "$repo" "*.pkg.tar.zst")
            kv "Offline local repo (\`cache/pkgs/repo/\`)" "$nrepo packages, $(hsize "$repo")"
        fi
        if [ -f "$repo/pacstrap-azarch-repo.db" ]; then
            kv "Local repo index" "\`pacstrap-azarch-repo.db\` present -> offline rebuilds enabled"
        else
            kv "Local repo index" "absent -> next build needs the network to populate it"
        fi
        if [ -d "$syncdb" ]; then
            local ndb; ndb=$(count_glob "$syncdb" "*.db")
            kv "Synced pacman DBs (\`cache/pkgs/db/sync/\`)" "$ndb database(s)"
        fi
        # The disposable profile/scratch tree, if a build was mid-flight or kept.
        [ -d "$cache/build" ] && kv "Scratch build tree (\`cache/build/\`)" "present, $(hsize "$cache/build") (disposable mkarchiso workdir)"

        # Offline-readiness verdict mirrors build.py::cache_is_complete().
        blank
        if [ -f "$repo/pacstrap-azarch-repo.db" ] && [ "$(count_glob "$repo" '*.pkg.tar.zst')" -gt 0 ] \
           && [ -d "$syncdb" ] && [ "$(count_glob "$syncdb" '*.db')" -gt 0 ]; then
            bullet "**Offline-ready:** cache is complete; a rebuild will contact no server (matches \`cache_is_complete()\`)."
        else
            bullet "**Not offline-ready:** cache is incomplete; the next build will reach the mirrors."
        fi
    else
        bullet "\`cache/\` absent."
    fi

    # --- output ISOs --------------------------------------------------------
    blank
    h3 "5.2 Output -- \`output/\`"
    if [ -d "$out" ]; then
        local found=0 iso
        for iso in "$out"/*.iso; do
            [ -e "$iso" ] || continue
            found=1
            kv "ISO" "\`$(basename "$iso")\` -- $(hsize "$iso")"
        done
        [ "$found" = 0 ] && bullet "No \`.iso\` built yet."
    else
        bullet "\`output/\` absent."
    fi

    # --- logs ---------------------------------------------------------------
    blank
    h3 "5.3 Logs -- \`logs/\`"
    if [ -d "$logs" ]; then
        [ -f "$logs/full.log" ]  && kv "full.log"  "$(hsize "$logs/full.log") ($(loc "$logs/full.log") lines)"
        [ -f "$logs/steps.log" ] && kv "steps.log" "$(hsize "$logs/steps.log") ($(loc "$logs/steps.log") lines)"
        # Surface the last milestone line, if present -- a quick "where did it get to".
        if [ -f "$logs/steps.log" ] && [ -s "$logs/steps.log" ]; then
            local last; last=$(tail -1 "$logs/steps.log" 2>/dev/null)
            [ -n "$last" ] && bullet "Last milestone: \`$last\`"
        fi
    else
        bullet "\`logs/\` absent."
    fi
}
