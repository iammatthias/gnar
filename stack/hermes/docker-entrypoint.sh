#!/bin/sh
# GNAR hermes image entrypoint.
#
# Best-effort: when the agent's git identity is unset or still the
# install-time placeholder (e.g. `iam@` from setup.sh when $(hostname) was
# empty), derive it from the authenticated gh account so commits the agent
# makes are attributable and don't trip "author identity unknown". Never
# fatal — always hands off to the hermes process.

configure_git_identity() {
    command -v gh >/dev/null 2>&1 || return 0
    gh auth status >/dev/null 2>&1 || return 0

    cur_email="$(git config --global user.email 2>/dev/null)"
    case "$cur_email" in
        ""|*@) ;;          # unset or broken placeholder → (re)configure
        *)     return 0 ;; # already a real identity → leave it alone
    esac

    login="$(gh api user --jq .login 2>/dev/null)" || return 0
    [ -n "$login" ] || return 0
    uid="$(gh api user --jq .id 2>/dev/null)"

    git config --global user.name "$login" 2>/dev/null || true
    if [ -n "$uid" ]; then
        git config --global user.email "${uid}+${login}@users.noreply.github.com" 2>/dev/null || true
    else
        git config --global user.email "${login}@users.noreply.github.com" 2>/dev/null || true
    fi
}

configure_git_identity || true

exec "$@"
