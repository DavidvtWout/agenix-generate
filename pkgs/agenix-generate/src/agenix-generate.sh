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

NAME=""
ALL=false
FORCE=false
DELETE=false
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
  -d | --delete)
    shift
    DELETE=true
    ;;
  -*)
    echo >&2 "unknown option $1"
    exit 1
    ;;
  *)
    if [[ "$NAME" != "" ]]; then
      echo >&2 "only one file can be specified"
      exit 1
    fi
    NAME="$1"
    shift
    ;;
  esac
done

if [[ $ALL == false ]] && [[ $NAME == "" ]]; then
  echo >&2 "Either a file must be specified or the --all flag must be set"
  exit 1
fi
if [[ $ALL == true ]] && [[ $NAME != "" ]]; then
  echo >&2 "Either a file must be specified or the --all flag must be set. Not both."
  exit 1
fi
if [[ $ALL == true ]] && [[ $FORCE == true ]]; then
  echo >&2 "The --all and --force options are mutually exclusive"
  exit 1
fi

DECRYPT="@ageBin@ --decrypt -i $IDENTITY"

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
  generator=$(echo "$SECRET" | jq -r '.value.generator.name')

  # Secret does not yet exist. Either generate, or skip.
  if [[ ! (-f "$NAME") ]] && [[ $generator != "null" ]]; then
    echo -e "\033[1;92mGenerating   \033[0;1m$NAME\033[0m with generator $generator"
    generate
    return
  fi
  if [[ ! (-f "$NAME") ]] && [[ $generator == "null" ]]; then
    echo -e "\033[1;93mSkipping     \033[0;1m$NAME\033[1;93m because no generator defined!\033[0m"
    update-meta false
    return
  fi

  if [[ "$META" != "" ]]; then
    deps_updated=$(echo "$SECRET" | jq -r '.value.generator.regenBecauseDeps')
    if [[ $deps_updated == true ]]; then
      echo -e "\033[1;94mRegenerating \033[0;1m$NAME\033[0m because the dependencies changed"
      generate
      return
    fi

    args_updated=$(echo "$SECRET" | jq -r '.value.generator.regenBecauseArgs')
    if [[ $args_updated == true ]]; then
      echo -e "\033[1;94mRegenerating \033[0;1m$NAME\033[0m because the generator args changed"
      generate
      return
    fi

    in_meta=$(echo "$SECRET" | jq -r '.value.generator.inMeta')
    if [[ $in_meta != true ]]; then
      echo -e "\033[1;94mRekeying     \033[0;1m$NAME\033[0m because it is not in the meta file"
      rekey
      return
    fi

    pubkeys_updated=$(echo "$SECRET" | jq -r '.value.generator.pubkeysChanged')
    if [[ $pubkeys_updated == true ]]; then
      echo -e "\033[1;94mRekeying     \033[0;1m$NAME\033[0m because the publicKeys changed"
      rekey
      return
    fi
  fi

  if [[ -f "$NAME" ]] && [[ $FORCE == true ]]; then
    echo -e "\033[1;95mRegenerating \033[0;1m$NAME\033[1;95m because --force flag is set\033[0m"
    generate
    return
  fi

  # If none of the above conditions matched, the secret can safely be skipped.
  echo -e "\033[2mSkipping     $NAME because it already exists\033[0m"
}

function rekey {
  KEYS=$( (@nixEval@ --json -f "$RULES" \""$NAME\".publicKeys" | @jqBin@ -r .[]) || exit 1)
  ENCRYPT_ARGS=(--encrypt)
  while IFS= read -r key; do
    ENCRYPT_ARGS+=(-r "$key")
  done <<<"$KEYS"
  ENCRYPT_ARGS+=(-o "$NAME")

  @ageBin@ --decrypt -i "$IDENTITY" "$NAME" | @ageBin@ "${ENCRYPT_ARGS[@]}"
  update-meta false
}

function generate {
  KEYS=$( (@nixEval@ --json -f "$RULES" \""$NAME\".publicKeys" | @jqBin@ -r .[]) || exit 1)
  ENCRYPT_ARGS=(--encrypt)
  while IFS= read -r key; do
    ENCRYPT_ARGS+=(-r "$key")
  done <<<"$KEYS"
  ENCRYPT_ARGS+=(-o "$NAME")

  script=$(echo "$SECRET" | jq -r '.value.generator.script')
  eval "$script" | @ageBin@ "${ENCRYPT_ARGS[@]}"
  update-meta true
}

function update-meta {
  if [[ $META == "" ]]; then
    return
  fi
  GENERATED="$1"
  TIMESTAMP=$(date +%s)
  NEW_META=$(@nixEval@ --impure --json --expr "(import @updateMetaNix@) {secretName=\"$NAME\"; generated=$GENERATED; timestamp=$TIMESTAMP; secretsPath=\"$RULES\"; metaPath=\"$META\";}")
  echo "$NEW_META" >"$META"
}

function generate-all {
  secrets=$(@nixEval@ --impure --json --expr "(import @loadSecretsNix@) {secretsPath=\"$RULES\"; generatorsPath=\"$GENERATORS\"; metaPath=\"$META\"; decrypt=\"$DECRYPT\";}")
  echo "$secrets" | @jqBin@ -c '.[]' | while read -r SECRET; do
    NAME=$(echo "$SECRET" | jq -r '.name')
    rekey-or-generate
  done

  # TODO: warn about secrets not defined in secrets.nix

  if [[ $DELETE == true ]]; then
    echo TODO: remove old secrets from meta
  fi

  # TODO: generate META all at once using $secrets
}

if [[ $META != "" ]] && [[ ! -f "$META" ]]; then
  echo "{}" >"$META"
fi

if [[ $ALL == true ]]; then
  generate-all
else
  # TODO: create SECRET variable from NAME
  rekey-or-generate
fi
