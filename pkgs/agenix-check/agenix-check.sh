#!/usr/bin/env bash
set -Eeuo pipefail

PACKAGE="agenix-check"

function show_help() {
  echo "$PACKAGE - check if secrets defined in secrets.nix are generated and keyed correctly"
  echo " "
  echo "$PACKAGE [-m META] FILE"
  echo "$PACKAGE [-m META] --all"
  echo ' '
  echo 'options:'
  echo '-h, --help                show help'
  echo '-m, --meta                path to metadata file'
  echo '-a, --all                 check all secrets defined in RULES'
  echo '-s, --strict              also return non-zero exit code on warnings'
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

function error {
  echo >&2 -e "\033[1;91mERROR:\033[0m $1"
  return 1
}

function errorWithFile {
  echo >&2 -e "$FILE \033[1;91mERROR:\033[0m $1"
  return 1
}

function warn {
  if [[ $STRICT == true ]]; then
    echo >&2 -e "\033[1;91mERROR:\033[0m $1"
    return 1
  else
    echo -e "\033[1;93mWARNING:\033[0m $1"
    return 0
  fi
}

function warnWithFile {
  if [[ $STRICT == true ]]; then
    echo >&2 -e "$FILE \033[1;91mERROR:\033[0m $1"
    return 1
  else
    echo -e "$FILE \033[1;93mWARNING:\033[0m $1"
    return 0
  fi
}

FILE=""
ALL=false
STRICT=false
RULES=${AGENIX_RULES:-$(realpath ./secrets.nix)}
META=${AGENIX_META:-""}
while test $# -gt 0; do
  case "$1" in
  -h | --help)
    show_help
    exit 0
    ;;
  -m | --meta)
    shift
    if test $# -gt 0; then
      META="$1"
    else
      error "No META specified"
    fi
    shift
    ;;
  -a | --all)
    shift
    ALL=true
    ;;
  -s | --strict)
    shift
    STRICT=true
    ;;
  -*)
    error "Unknown option $1"
    ;;
  *)
    if [[ "$FILE" != "" ]]; then
      error "Only one file can be specified"
    fi
    FILE="$1"
    shift
    ;;
  esac
done

if [[ $ALL == false ]] && [[ $FILE == "" ]]; then
  error "Either a file must be specified or the --all flag must be set"
fi
if [[ $ALL == true ]] && [[ $FILE != "" ]]; then
  error "Either a file must be specified or the --all flag must be set. Not both."
fi

echo "Running $PACKAGE from directory $(pwd) with;"
echo "  secrets file:    $RULES"
echo "  meta file:       $META"
echo

function check-secret {
  if @nixEval@ --impure --raw --expr "(import $RULES).\"$FILE\".generator.name" 2>/dev/null; then
    HAS_GENERATOR=true
  else
    HAS_GENERATOR=false
  fi

  if [[ ! -f "$FILE" ]]; then
    if [[ $HAS_GENERATOR == true ]]; then
      errorWithFile "has a generator but has not been generated"
      return $?
    else
      warnWithFile "defined in $(basename "$RULES") but does not exist on disk"
      return $?
    fi
  fi

  if [[ $META != "" ]]; then
    CHECK_META=$(@nixEval@ --impure --json --expr "(import @checkMetaNix@) {secretName=\"$FILE\"; secretsPath=\"$RULES\"; metaPath=\"$META\";}")
    IN_META=$(echo -e "$CHECK_META" | @jqBin@ -r .inMeta)
    if [[ $IN_META != true ]] && [[ $HAS_GENERATOR == true ]]; then
      errorWithFile "is not in meta file"
      return $?
    fi
    if [[ $IN_META != true ]] && [[ $HAS_GENERATOR == false ]]; then
      warnWithFile "is not in meta file"
      return $?
    fi
    NEED_REKEY=$(echo -e "$CHECK_META" | @jqBin@ -r .needRekey)
    if [[ $NEED_REKEY == true ]]; then
      errorWithFile "must be rekeyed"
      return $?
    fi
    NEED_REGEN=$(echo -e "$CHECK_META" | @jqBin@ -r .needRegen)
    if [[ $NEED_REGEN == true ]]; then
      errorWithFile "must be regenerated"
      return $?
    fi
  fi

  echo -e "$FILE \033[1;92mokay\033[0m"
  return 0
}

function check-all {
  EXIT_CODE=0

  SECRET_FILES=$( (@nixEval@ --impure --json --expr "builtins.attrNames (import $RULES)" | @jqBin@ -r .[]) || exit 1)
  set +e
  for FILE in $SECRET_FILES; do
    if ! check-secret; then
      EXIT_CODE=1
    fi
  done
  set -e

  DISK_FILES=$(find . -type f -name "*.age" | sed 's|^\./||')
  set +e
  for FILE in $DISK_FILES; do
    if ! (echo "$SECRET_FILES" | grep -qw "$FILE"); then
      if ! warnWithFile "exists on disk but not in $(basename "$RULES")"; then
        EXIT_CODE=1
      fi
    fi
  done
  set -e

  return $EXIT_CODE
}

if [[ ! -f "$RULES" ]]; then
  error "RULES file $RULES does not exist"
fi
if [[ $META == "" ]]; then
  warn "No META specified. This limits the checking capabilities of $PACKAGE"
fi
if [[ $META != "" ]] && [[ ! -f "$META" ]]; then
  error "META file $META does not exist"
fi

if [[ $ALL == true ]]; then
  check-all
else
  check-secret
fi
exit $?
