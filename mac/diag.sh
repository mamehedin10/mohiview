#!/bin/bash
# MohiView for Mac - collect the logs needed when MohiView closes by itself.
#
#   curl -fsSL https://remote.brandivolabs.com/mac-diag.sh | bash
#
# Read-only: changes nothing on this Mac and uploads nothing. The report is
# saved to the Desktop and copied to the clipboard. During a MohiView session
# the clipboard is shared, so the office PC receives it too.
set -u

APP="MohiView"
LOGDIR="$HOME/Library/Logs/$APP"
OUT="$HOME/Desktop/$APP-diagnostics.txt"
AGENT="com.carriez.${APP}_server"
DAEMON="com.carriez.${APP}_service"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Summarises a macOS crash report (.ips = one JSON header line + JSON body).
cat > "$TMP/ips.js" <<'JS'
ObjC.import('Foundation');
function run(argv) {
  var data = $.NSData.dataWithContentsOfFile(argv[0]);
  if (!data) return 'cannot read ' + argv[0];
  var text = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js;
  var nl = text.indexOf('\n');
  var head, body;
  try {
    head = JSON.parse(text.slice(0, nl));
    body = JSON.parse(text.slice(nl + 1));
  } catch (e) {
    return text.split('\n').slice(0, 80).join('\n');
  }
  var out = [];
  out.push('process: ' + (body.procName || head.app_name || '?') + '  time: ' + (body.captureTime || head.timestamp || '?'));
  if (body.exception) out.push('exception: ' + JSON.stringify(body.exception));
  if (body.termination) out.push('termination: ' + JSON.stringify(body.termination));
  if (body.asi) out.push('asi: ' + JSON.stringify(body.asi));
  var imgs = body.usedImages || [];
  var n = body.faultingThread || 0;
  var t = (body.threads || [])[n] || {};
  out.push('faulting thread ' + n + (t.name ? ' name=' + t.name : '') + (t.queue ? ' queue=' + t.queue : ''));
  (t.frames || []).slice(0, 40).forEach(function (f, i) {
    var img = imgs[f.imageIndex] || {};
    var where = f.symbol ? f.symbol + ' + ' + (f.symbolLocation || 0) : '+' + f.imageOffset;
    out.push('  ' + i + ' ' + (img.name || '?') + ' ' + where);
  });
  return out.join('\n');
}
JS

section() { printf '\n===== %s =====\n' "$*"; }

echo "Collecting $APP logs (this can take up to a minute)..."
{
  section "$APP diagnostics, $(date '+%Y-%m-%d %H:%M:%S %z')"
  sw_vers 2>/dev/null
  echo "arch: $(uname -m)"

  section "Running $APP processes"
  ps -axo pid,user,lstart,command | grep -i "[m]ohiview" || echo "(none running)"

  section "Service"
  ls -l "/Library/LaunchAgents/$AGENT.plist" "/Library/LaunchDaemons/$DAEMON.plist" 2>&1
  launchctl print "gui/$(id -u)/$AGENT" 2>&1 | grep -E "^[[:space:]]*(state|pid|runs|last exit code|last terminating signal) =" || echo "agent not loaded"
  launchctl print "system/$DAEMON" 2>&1 | grep -E "^[[:space:]]*(state|pid|runs|last exit code|last terminating signal) =" || echo "daemon not loaded (or not readable without admin)"

  section "Crash lines in $APP logs"
  grep -rh -B 2 -A 40 -E "Got signal|panicked" "$LOGDIR" 2>/dev/null | tail -n 150
  grep -rqs -E "Got signal|panicked" "$LOGDIR" || echo "(none)"

  section "Restarts and hand-overs in $APP logs"
  grep -rh -E "Receive close message|Failed to start ipc|ipc is occupied|start --server|start --service|Started ipc server|Exit" "$LOGDIR" 2>/dev/null | tail -n 40

  section "Crash reports"
  found=0
  for d in "$HOME/Library/Logs/DiagnosticReports" /Library/Logs/DiagnosticReports; do
    for f in $(ls -t "$d" 2>/dev/null | grep -E "^($APP|service)[-_.]" | head -n 3); do
      found=1
      echo "--- $d/$f"
      osascript -l JavaScript "$TMP/ips.js" "$d/$f" 2>&1 | head -n 60
    done
  done
  [ "$found" = 1 ] || echo "(no crash reports)"

  section "Latest log lines"
  ls -t "$LOGDIR"/*.log "$LOGDIR"/*/*.log 2>/dev/null | head -n 4 | while IFS= read -r f; do
    echo "--- $f (changed $(stat -f '%Sm' "$f"))"
    tail -n 50 "$f"
  done

  section "System log: $APP exits in the last 90 minutes"
  ( log show --last 90m --style compact --predicate 'eventMessage CONTAINS[c] "mohiview" AND (eventMessage CONTAINS[c] "exit" OR eventMessage CONTAINS[c] "terminat" OR eventMessage CONTAINS[c] "kill" OR eventMessage CONTAINS[c] "crash" OR eventMessage CONTAINS[c] "quit")' > "$TMP/syslog.txt" 2>/dev/null ) &
  lp=$!
  ( sleep 60; kill "$lp" 2>/dev/null ) &
  kp=$!
  wait "$lp" 2>/dev/null
  kill "$kp" 2>/dev/null
  tail -n 40 "$TMP/syslog.txt"
} > "$OUT" 2>&1

echo
echo "Saved: $OUT"
if pbcopy < "$OUT" 2>/dev/null; then
  echo "Also copied to the clipboard: paste it (Cmd+V) to the office."
fi
echo
echo "----- short summary -----"
sed -n '/===== Service =====/,/===== Crash reports =====/p' "$OUT" | head -n 30
