# shellcheck shell=bash
# Copyright 2026 AgentDorm contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# A deliberately small reader for resident.yaml, so the CLI needs nothing but
# bash and awk. It understands exactly the shapes resident.yaml uses:
#
#   key: value            scalars (optionally quoted; ` # comment` stripped)
#   key: |                literal block, indented lines below it
#   key:                  list, `  - item` lines below it
#
# Anything fancier belongs in a real YAML parser, not in resident.yaml.

# ad_yaml_get <file> <key>  ->  value, block text, or one list item per line
ad_yaml_get() {
  awk -v want="$2" '
    function unquote(v) {
      if (v ~ /^".*"$/ || v ~ /^\x27.*\x27$/) return substr(v, 2, length(v) - 2)
      sub(/[ \t]+#.*$/, "", v)
      return v
    }
    BEGIN { mode = "" }
    mode == "block" {
      if ($0 ~ /^[^ \t]/ && $0 !~ /^$/) exit
      line = $0
      if (indent == 0 && line ~ /^[ \t]+[^ \t]/) { match(line, /^[ \t]+/); indent = RLENGTH }
      print substr(line, indent + 1)
      next
    }
    mode == "list" {
      if ($0 ~ /^[ \t]*-[ \t]+/) { v = $0; sub(/^[ \t]*-[ \t]+/, "", v); print unquote(v); next }
      if ($0 ~ /^[ \t]*$/ || $0 ~ /^[ \t]*#/) next
      exit
    }
    $0 ~ ("^" want ":") {
      v = $0; sub("^" want ":[ \t]*", "", v)
      if (v ~ /^[|>][-+]?[ \t]*$/) { mode = "block"; indent = 0; next }
      if (v == "" || v ~ /^#/) { mode = "list"; next }
      print unquote(v); exit
    }
  ' "$1" | awk 'NF { last = NR } { lines[NR] = $0 } END { for (i = 1; i <= last; i++) print lines[i] }'
}
