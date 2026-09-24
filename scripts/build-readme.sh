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
# Not named GROUPS: bash keeps that name for the caller's group ids, so an
# assignment to it is ignored and it reads back as a number.
GROUP_LIST="openwrt:OpenWrt vpn:VPN media:Media"

repos="$(gh api --paginate "users/$user/repos?per_page=100&sort=pushed" \
  --jq '.[] | select(.fork==false and .archived==false and .private==false)
        | select(.name != "'"$user"'")
        | {name, description, language, pushed_at, topics}')"

# The product name is the first-line title of each README, so the profile shows
# what a user sees in the application next to the repository it lives in. A
# repository whose README cannot be read is listed by its name alone.
titled=""
while IFS= read -r repo; do
  name="$(printf '%s\n' "$repo" | jq -r .name)"
  title="$(gh api "repos/$user/$name/readme" --jq .content 2>/dev/null |
    base64 -d 2>/dev/null | sed -n '1s/^# //p' || true)"
  titled="$titled$(printf '%s\n' "$repo" | jq -c --arg t "$title" '. + {title: (if $t == "" then null else $t end)}')
"
done <<EOF_REPOS
$(printf '%s\n' "$repos" | jq -c .)
EOF_REPOS
repos="$titled"

# Render one line per repository. A repository is placed in the first group
# whose topic it carries, so carrying two of them lists it once rather than
# twice.
# jq expressions: the $ and \( belong to jq, not the shell.
# shellcheck disable=SC2016
line_filter='"- **[\(.title // .name)](https://github.com/'"$user"'/\(.name))**"
  + (if (.title // "") == "" then "" else " (`\(.name)`)" end)
  + (if (.description // "") == "" then "" else " - \(.description)" end)
  + (if (.language // "") == "" then "" else "  `\(.language)`" end)'

ordered_topics="$(for pair in $GROUP_LIST; do printf '%s\n' "${pair%%:*}"; done |
  jq -R . | jq -sc .)"

# group_of: the index of the first group topic the repository carries, or the
# count of groups when it carries none, which is the Other bucket.
# jq expressions: the $ and \( belong to jq, not the shell.
# shellcheck disable=SC2016
assign='. as $r
  | ($known | map(. as $t | ($r.topics // []) | index($t) | if . then 1 else 0 end))
  | (index(1) // ($known | length)) as $g
  | $r + {group: $g}'

placed="$(printf '%s\n' "$repos" | jq -c --argjson known "$ordered_topics" "$assign")"

{
  printf '## Projects\n'

  index=0
  for pair in $GROUP_LIST; do
    body="$(printf '%s\n' "$placed" |
      jq -r --argjson g "$index" "select(.group == \$g) | $line_filter")"
    if [ -n "$body" ]; then
      printf '\n### %s\n\n%s\n' "${pair#*:}" "$body"
    fi
    index=$((index + 1))
  done

  # Anything no group claimed, so incomplete topics never hide a repository.
  rest="$(printf '%s\n' "$placed" |
    jq -r --argjson g "$index" "select(.group == \$g) | $line_filter")"
  if [ -n "$rest" ]; then
    printf '\n### Other\n\n%s\n' "$rest"
  fi
} >"$readme.new"

mv "$readme.new" "$readme"
printf 'wrote %s (%s lines)\n' "$readme" "$(wc -l <"$readme" | tr -d ' ')"
