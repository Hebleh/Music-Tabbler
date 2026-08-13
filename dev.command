#!/bin/zsh

set -u

repo_root="${0:A:h}"
device="macos"
clean=false
flutter_args=()

usage() {
  cat <<'EOF'
Usage: ./dev.command [--clean] [--device <flutter-device-id>] [flutter arguments]

Examples:
  ./dev.command
  ./dev.command --clean
  ./dev.command --device macos --dart-define=NAME=VALUE
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --clean|-Clean)
      clean=true
      shift
      ;;
    --device|-d|-Device)
      if (( $# < 2 )); then
        print -u2 "Missing device ID after $1."
        usage >&2
        exit 64
      fi
      device="$2"
      shift 2
      ;;
    --device=*)
      device="${1#*=}"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      flutter_args+=("$@")
      break
      ;;
    *)
      flutter_args+=("$1")
      shift
      ;;
  esac
done

if command -v flutter >/dev/null 2>&1; then
  flutter_command="$(command -v flutter)"
elif [[ -x "$repo_root/../flutter/bin/flutter" ]]; then
  flutter_command="$repo_root/../flutter/bin/flutter"
else
  print -u2 "Flutter was not found on PATH or beside the Music Tabbler folder."
  print -u2 "Install/configure Flutter before launching Music Tabbler."
  exit 127
fi

cd "$repo_root" || exit 1

if [[ "$clean" == true ]]; then
  "$flutter_command" clean || exit $?
fi

print "Launching Music Tabbler on '$device' in Flutter development mode..."
if command -v caffeinate >/dev/null 2>&1; then
  caffeinate -di "$flutter_command" run -d "$device" "${flutter_args[@]}"
else
  "$flutter_command" run -d "$device" "${flutter_args[@]}"
fi
exit $?
