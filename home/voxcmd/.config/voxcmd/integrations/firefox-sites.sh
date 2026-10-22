# shellcheck shell=bash
# Hook library of firefox-sites.toml: sourced before every hook of the integration.

# id<TAB>label<TAB>match_text per site. Only sites whose title or name is the target's words, or a domain said alone:
# unlike "open X in firefox", nothing here said a site was meant, so a near miss is no match rather than a picker of
# pages (hence --strong). A site that appears twice is listed once, the first; that dedupe runs after the word match so
# a weak copy cannot hide a strong one.
site_candidates() {
  "$VOXCMD_SHARE_DIR/firefox-tab" candidates sites "$VOXCMD_ARG_TARGET" --raw "$VOXCMD_RAW_TRANSCRIPT" 2>/dev/null |
    jq -r '.[]
      | (.match_text // .label) as $match
      | select($match != "")
      | [.id, .label, $match] | map(gsub("[\t\n\r]"; " ")) | join("\t")' |
    "$VOXCMD_SELF" util word-match --strong "$VOXCMD_ARG_TARGET" 2>/dev/null |
    awk -F'\t' '!seen[$1]++'
}
