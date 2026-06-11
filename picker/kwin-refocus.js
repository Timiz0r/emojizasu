var active = workspace.activeWindow;
var stack = workspace.stackingOrder;
for (var i = stack.length - 1; i >= 0; i--) {
    var w = stack[i];
    if (w && !w.deleted && w.normalWindow && w !== active) { workspace.activeWindow = w; break; }
}
