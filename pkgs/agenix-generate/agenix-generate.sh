#!/usr/bin/env bash
set -Eeuo pipefail

PACKAGE="agenix-generate"

function show_help() {
  echo "$PACKAGE - rekey existing and generate new secrets with a single command"
  echo " "
  echo "$PACKAGE [-i IDENTITY] [-m META] FILE"
  echo "$PACKAGE [-i IDENTITY] [-m META] --all"
  echo ' '
  echo 'options:'
  echo '-h, --help                show help'
  echo '-i, --identity            identity to use when rekeying or decrypting a dependency'
  echo '-m, --meta                path to metadata file to determine if secrets should be regenerated'
  echo '-f, --force               force generate, even when secret already exists'
  echo '-a, --all                 generate all secrets defined in RULES'
  echo ' '
  echo 'PRIVATE_KEY a path to a private AGE or SSH key used to decrypt file'
  echo ' '
  echo 'RULES environment variable with path to Nix file specifying recipient public keys.'
  echo "Defaults to './secrets.nix'"
  echo ' '
  echo "agenix version: @version@"
  echo "age binary path: @ageBin@"
  echo "age version: $(@ageBin@ --version)"
}

FILE=""
ALL=false
FORCE=false
IDENTITY=${AGENIX_IDENTITY:-""}
RULES=${AGENIX_RULES:-$(realpath ./secrets.nix)}
GENERATORS=${AGENIX_GENERATORS:-$(realpath ./generators.nix)}
META=${AGENIX_META:-""}
while test $# -gt 0; do
  case "$1" in
  -h | --help)
    show_help
    exit 0
    ;;
  -i | --identity)
    shift
    if test $# -gt 0; then
      IDENTITY="$1"
    else
      echo >&2 "no IDENTITY specified"
      exit 1
    fi
    shift
    ;;
  -m | --meta)
    shift
    if test $# -gt 0; then
      META="$1"
    else
      echo >&2 "no META specified"
      exit 1
    fi
    shift
    ;;
  -f | --force)
    shift
    FORCE=true
    ;;
  -a | --all)
    shift
    ALL=true
    ;;
  -*)
    echo >&2 "unknown option $1"
    exit 1
    ;;
  *)
    if [[ "$FILE" != "" ]]; then
      echo >&2 "only one file can be specified"
      exit 1
    fi
    FILE="$1"
    shift
    ;;
  esac
done


if [[ $ALL == false ]] && [[ $FILE == "" ]]; then
  echo >&2 "Either a file must be specified or the --all flag must be set"
  exit 1
fi
if [[ $ALL == true ]] && [[ $FILE != "" ]]; then
  echo >&2 "Either a file must be specified or the --all flag must be set. Not both."
  exit 1
fi
if [[ $ALL == true ]] && [[ $FORCE == true ]]; then
  echo >&2 "The --all and --force options are mutually exclusive"
  exit 1
fi

# TODO: check if secrets.nix and generators.nix exist


echo "Running $PACKAGE from directory $(pwd) with;"
echo "  secrets file:    $RULES"
echo "  generators file: $GENERATORS"
if [[ $META != "" ]]; then
  echo "  meta file:       $META"
fi
echo

# TODO: print args and dependencies when (re)generating?
function rekey-or-generate {
  GENERATOR=$(@nixEval@ --raw -f "$RULES" \""$FILE\".generator.name" 2>/dev/null || echo "")

  # Secret does not yet exist. Either generate, or skip.
  if [[ ! (-f "$FILE") ]] && [[ $GENERATOR != "" ]]; then
    echo -e "\033[1;92mGenerating   \033[0;1m$FILE\033[0m with generator ${GENERATOR}"
    generate
    return
  fi
  if [[ ! (-f "$FILE") ]] && [[ $GENERATOR == "" ]]; then
    echo -e "\033[1;93mSkipping     \033[0;1m$FILE\033[1;93m because no generator defined!\033[0m"
    update-meta false
    return
  fi

  if [[ "$META" != "" ]]; then
    CHECK_META=$(@nixEval@ --impure --json --expr "(import @checkMetaNix@) {secretName=\"$FILE\"; secretsPath=\"$RULES\"; metaPath=\"$META\";}")

    DEPS_UPDATED=$(echo -e "$CHECK_META" | @jqBin@ -r .regenBecauseDeps)
    if [[ $DEPS_UPDATED == true ]]; then
      echo -e "\033[1;94mRegenerating \033[0;1m$FILE\033[0m because the dependencies changed"
      generate
      return
    fi

    ARGS_UPDATED=$(echo -e "$CHECK_META" | @jqBin@ -r .regenBecauseArgs)
    if [[ $ARGS_UPDATED == true ]]; then
      echo -e "\033[1;94mRegenerating \033[0;1m$FILE\033[0m because the generator args changed"
      generate
      return
    fi

    IN_META=$(echo -e "$CHECK_META" | @jqBin@ -r .inMeta)
    if [[ $IN_META != true ]]; then
      echo -e "\033[1;94mRekeying     \033[0;1m$FILE\033[0m because it is not in the meta file"
      rekey
      return
    fi

    PUBKEYS_UPDATED=$(echo -e "$CHECK_META" | @jqBin@ -r .pubkeysChanged)
    if [[ $PUBKEYS_UPDATED == true ]]; then
      echo -e "\033[1;94mRekeying     \033[0;1m$FILE\033[0m because the publicKeys changed"
      rekey
      return
    fi
  fi

  if [[ -f "$FILE" ]] && [[ $FORCE == true ]]; then
    echo -e "\033[1;95mRegenerating \033[0;1m$FILE\033[1;95m because --force flag is set\033[0m"
    generate
    return
  fi

  # If none of the above conditions matched, the secret can safely be skipped.
  echo -e "\033[2mSkipping     $FILE because it already exists\033[0m"
}

function rekey {
  KEYS=$( (@nixEval@ --json -f "$RULES" \""$FILE\".publicKeys" | @jqBin@ -r .[]) || exit 1)
  ENCRYPT_ARGS=(--encrypt)
  while IFS= read -r key; do
    ENCRYPT_ARGS+=(-r "$key")
  done <<<"$KEYS"
  ENCRYPT_ARGS+=(-o "$FILE")

  @ageBin@ --decrypt -i "$IDENTITY" "$FILE" | @ageBin@ "${ENCRYPT_ARGS[@]}"
  update-meta false
}

function generate {
  DECRYPT="@ageBin@ --decrypt -i $IDENTITY"
  SCRIPT=$(@nixEval@ --impure --raw --expr "(import @generateNix@) {secretName=\"$FILE\"; decrypt=\"$DECRYPT\"; generatorsPath=\"$GENERATORS\"; secretsPath=\"$RULES\";}" || exit 1)

  KEYS=$( (@nixEval@ --json -f "$RULES" \""$FILE\".publicKeys" | @jqBin@ -r .[]) || exit 1)
  ENCRYPT_ARGS=(--encrypt)
  while IFS= read -r key; do
    ENCRYPT_ARGS+=(-r "$key")
  done <<<"$KEYS"
  ENCRYPT_ARGS+=(-o "$FILE")

  eval "$SCRIPT" | @ageBin@ "${ENCRYPT_ARGS[@]}"
  update-meta true
}

function update-meta {
  if [[ $META == "" ]]; then
    return
  fi
  REGENERATED="$1"
  TIMESTAMP=$(date +%s)
  NEW_META=$(@nixEval@ --impure --json --expr "(import @updateMetaNix@) {secretName=\"$FILE\"; regenerated=$REGENERATED; timestamp=$TIMESTAMP; secretsPath=\"$RULES\"; metaPath=\"$META\";}")
  echo "$NEW_META" >"$META"
}

function generate-all {
  FILES=$( (@nixEval@ --impure --json --expr "(import @orderSecretsNix@) {secretsPath=\"$RULES\";}" | @jqBin@ -r .[]) || exit 1)
  for FILE in $FILES; do
    rekey-or-generate
  done

  # TODO: warn about secrets not defined in secrets.nix
  # TODO: remove old secrets from meta
}

if [[ $META != "" ]] && [[ ! -f "$META" ]]; then
  echo "{}" >"$META"
fi

if [[ $ALL == true ]]; then
  generate-all
else
  rekey-or-generate
fi
