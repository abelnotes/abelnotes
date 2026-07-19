# Wrapper attorno a `flutter run -d windows` che silenzia lo spam ricorrente
# della a11y bridge di Flutter su Windows
# (https://github.com/flutter/flutter/issues/182444):
#
#   [ERROR:flutter/shell/platform/common/accessibility_bridge.cc(114)]
#   Failed to update ui::AXTree, error: NN will not be in the tree
#   and is not the new root
#
# Tutti gli altri log e i comandi interattivi (r=hot reload, R=hot restart,
# q=quit, h=help) passano inalterati. Argomenti aggiuntivi vengono passati
# pari pari a `flutter run`.
#
# Uso:   .\tools\flutter-quiet.ps1
#        .\tools\flutter-quiet.ps1 --release
#        .\tools\flutter-quiet.ps1 --dart-define=foo=bar
#
# Per abbandonare il filtro: lancia `flutter run -d windows` direttamente.

param(
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$ExtraArgs
)

# `cmd /c` e' qui apposta: in PS 5.1 il `2>&1` su native exe wrappa stderr in
# ErrorRecord e sporca lo stream. Delegare a cmd.exe evita l'idiosincrasia
# e mantiene findstr come filtro nativo (piu' veloce di Where-Object e
# senza buffering aggressivo che ritarderebbe i comandi hot-reload).
$argList = (@('run', '-d', 'windows') + $ExtraArgs) -join ' '
$cmdLine = "flutter $argList 2>&1 | findstr /V /C:`"accessibility_bridge.cc`" /C:`"will not be in the tree`""
& cmd /c $cmdLine
