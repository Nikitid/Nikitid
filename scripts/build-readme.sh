#!/usr/bin/env bash
#
# Rebuild the profile README from the public repositories.
#
# The list is generated rather than maintained by hand because the hand-written
# one went stale: it named two repositories by names they no longer carry and
# omitted six that exist.
#
# Repositories are grouped by their first GitHub topic, in the order given by
# GROUP_ORDER, and sorted by last push inside each group. A repository with no
# matching topic falls into "Other", so nothing disappears just because its
# metadata is incomplete.

set -euo pipefail

user="${1:-Nikitid}"
readme="${2:-README.md}"

# "topic:Heading" pairs, in the order the groups appear. Plain strings rather
# than an associative array: this has to run on the bash that ships with macOS,
# which is 3.2 and has none.
GROUPS="openwrt:OpenWrt vpn:VPN media:Media"

repos="$(gh api --paginate "users/$user/repos?per_page=100&sort=pushed" \
  --jq '.[] | select(.fork==false and .archived==false and .private==false)
        | select(.name != "'"$user"'")
        | {name, description, language, pushed_at, topics}')"

emit_group() {
  local topic="$1" title="$2" body
  body="$(printf '%s\n' "$repos" | jq -r --arg t "$topic" '
    select((.topics // []) | index($t))
    | "- **[\(.name)](https://github.com/'"$user"'/\(.name))**"
      + (if (.description // "") == "" then "" else " — \(.description)" end)
      + (if (.language // "") == "" then "" else "  `\(.language)`" end)')"
  [[ -n "$body" ]] || return 0
  printf '\n### %s\n\n%s\n' "$title" "$body"
}

{
  printf '## Projects\n'

  for pair in $GROUPS; do
    emit_group "${pair%%:*}" "${pair#*:}"
  done

  # Anything the groups did not claim, so incomplete topics never hide a repo.
  matched="$(for pair in $GROUPS; do printf '%s\n' "${pair%%:*}"; done |
    jq -R . | jq -s .)"
  rest="$(printf '%s\n' "$repos" | jq -r --argjson known "$matched" '
    select([(.topics // [])[] | select(. as $t | $known | index($t))] | length == 0)
    | "- **[\(.name)](https://github.com/'"$user"'/\(.name))**"
      + (if (.description // "") == "" then "" else " — \(.description)" end)
      + (if (.language // "") == "" then "" else "  `\(.language)`" end)')"
  if [[ -n "$rest" ]]; then
    printf '\n### Other\n\n%s\n' "$rest"
  fi
} >"$readme.new"

mv "$readme.new" "$readme"
printf 'wrote %s (%s lines)\n' "$readme" "$(wc -l <"$readme" | tr -d ' ')"
