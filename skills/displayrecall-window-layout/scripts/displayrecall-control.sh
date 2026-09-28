#!/bin/zsh
set -u

APP_PATH="${DISPLAYRECALL_APP_PATH:-/Applications/DisplayRecall.app}"
USER_HOME="${HOME:?HOME is required}"
STATUS_PATH="${DISPLAYRECALL_STATUS_PATH:-${USER_HOME}/Library/Application Support/com.zomeelee.DisplayRecall/command-status-v1.json}"
LAYOUT_PATH="${USER_HOME}/Library/Application Support/com.zomeelee.DisplayRecall/layout-v1.json"
PLIST_PATH="${APP_PATH}/Contents/Info.plist"

usage() {
  echo "Usage: displayrecall-control.sh inspect|status|save|restore|permissions" >&2
}

json_bool() {
  if [[ "$1" == "true" ]]; then
    echo "true"
  else
    echo "false"
  fi
}

inspect() {
  local installed="false"
  local running="false"
  local command_interface="false"
  local layout_exists="false"
  local version=""

  if [[ -d "$APP_PATH" ]]; then
    installed="true"
  fi
  if /usr/bin/pgrep -x DisplayRecall >/dev/null 2>&1; then
    running="true"
  fi
  if [[ -f "$LAYOUT_PATH" ]]; then
    layout_exists="true"
  fi
  if [[ -f "$PLIST_PATH" ]]; then
    version=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST_PATH" 2>/dev/null || true)
    local scheme
    scheme=$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes:0" "$PLIST_PATH" 2>/dev/null || true)
    if [[ "$scheme" == "displayrecall" ]]; then
      command_interface="true"
    fi
  fi

  /usr/bin/printf '{"installed":%s,"running":%s,"commandInterface":%s,"layoutExists":%s,"version":"%s","appPath":"%s","statusPath":"%s"}\n' \
    "$(json_bool "$installed")" \
    "$(json_bool "$running")" \
    "$(json_bool "$command_interface")" \
    "$(json_bool "$layout_exists")" \
    "$version" \
    "$APP_PATH" \
    "$STATUS_PATH"
}

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

ACTION="$1"
case "$ACTION" in
  inspect)
    inspect
    exit 0
    ;;
  permissions)
    /usr/bin/open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    exit $?
    ;;
  status|save|restore)
    ;;
  *)
    usage
    exit 2
    ;;
esac

if [[ ! -d "$APP_PATH" || ! -f "$PLIST_PATH" ]]; then
  echo "DisplayRecall is not installed at $APP_PATH" >&2
  exit 3
fi

SCHEME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleURLTypes:0:CFBundleURLSchemes:0" "$PLIST_PATH" 2>/dev/null || true)
if [[ "$SCHEME" != "displayrecall" ]]; then
  echo "Installed DisplayRecall does not provide the local command interface; install version 0.1.8 or later." >&2
  exit 4
fi

REQUEST_ID=$(/usr/bin/uuidgen | /usr/bin/tr '[:upper:]' '[:lower:]')
URL="displayrecall://${ACTION}?request=${REQUEST_ID}"

if ! /usr/bin/open -g "$URL"; then
  echo "Unable to dispatch $ACTION to DisplayRecall." >&2
  exit 5
fi

TIMEOUT=30
if [[ "$ACTION" == "restore" ]]; then
  TIMEOUT=120
fi

SECONDS=0
while (( SECONDS < TIMEOUT )); do
  if [[ -f "$STATUS_PATH" ]]; then
    RESULT_ID=$(/usr/bin/plutil -extract requestID raw -o - "$STATUS_PATH" 2>/dev/null || true)
    if [[ "$RESULT_ID" == "$REQUEST_ID" ]]; then
      STATE=$(/usr/bin/plutil -extract state raw -o - "$STATUS_PATH" 2>/dev/null || true)
      if [[ "$STATE" == "completed" ]]; then
        /bin/cat "$STATUS_PATH"
        exit 0
      fi
      if [[ "$STATE" == "failed" ]]; then
        /bin/cat "$STATUS_PATH"
        exit 6
      fi
    fi
  fi
  /bin/sleep 0.25
done

echo "Timed out waiting for DisplayRecall $ACTION result after ${TIMEOUT}s." >&2
inspect >&2
exit 7
