// Pure row/command builders: display labels are never passed as device IDs.
var colors = ["warm", "cool", "white", "red", "orange", "yellow", "green", "blue", "purple", "pink"];

function targets(data) {
    if (!data) return [];
    var rows = [{ id: "scenes", label: "Scenes", view: "scenes", detail: "Run a saved scene" }];
    if (!data.devices.length) return rows;
    rows.push({ id: "all", label: "All devices", target: "all", kind: "all", detail: data.devices.length + " lights" });
    Object.keys(data.rooms).sort().forEach(function (name) {
        rows.push({ id: "room:" + name, label: name, target: "room:" + name, kind: "room", detail: "Room · " + data.rooms[name].length + " lights" });
    });
    var assigned = [].concat.apply([], Object.keys(data.rooms).map(function (name) { return data.rooms[name]; }));
    if (data.devices.some(function (d) { return assigned.indexOf(d.mac) < 0 && assigned.indexOf(d.name) < 0; }))
        rows.push({ id: "room:other", label: "Unassigned devices", target: "room:other", kind: "other", detail: "Lights without a room" });
    data.devices.forEach(function (d) {
        var state = d.online === false ? "offline" : d.online !== true ? "unknown" : d.power === 1 ? "on" : d.power === 0 ? "off" : "unknown";
        rows.push({ id: d.mac, label: d.label || d.name, target: d.mac, kind: "device", device: d,
                    detail: state + (typeof d.brightness === "number" ? " · " + d.brightness + "%" : "") + " · " + d.mac });
    });
    return rows;
}

function actions(target) {
    if (!target) return [];
    var rows = [
        { id: "on", label: "Turn on", args: ["--json", "on", target.target] },
        { id: "off", label: "Turn off", args: ["--json", "off", target.target] },
        { id: "brightness", label: "Brightness…", form: "brightness", detail: "0–100 percent" },
        { id: "color", label: "Colour…", view: "colors", detail: "Named colour or custom RGB" }
    ];
    if (target.kind === "device") {
        rows.push({ id: "label", label: "Friendly name…", form: "label", detail: "Leave empty to clear" });
        rows.push({ id: "rooms", label: "Move to room…", view: "rooms" });
    }
    if (target.kind === "room") rows.push({ id: "rename", label: "Rename room…", form: "rename" });
    return rows;
}

function rows(view, data, target) {
    if (view === "targets") return targets(data);
    if (view === "actions") return actions(target);
    if (view === "scenes") return (data ? data.scenes : []).map(function (name) {
        return { id: name, label: name, args: ["--json", "scene", name], detail: "Apply saved scene" };
    });
    if (view === "colors") return [{ id: "custom", label: "Custom RGB…", form: "color", detail: "RRGGBB or #RRGGBB" }].concat(colors.map(function (name) {
        return { id: name, label: name, args: ["--json", "color", name, target.target] };
    }));
    if (view === "rooms") return [{ id: "new", label: "New room…", form: "newroom" },
        { id: "none", label: "No room", args: ["rooms", "assign", "none", target.target] }].concat(Object.keys(data.rooms).sort().map(function (name) {
            return { id: name, label: name, args: ["rooms", "assign", name, target.target] };
        }));
    return [];
}

function filter(rows, query) {
    var q = query.trim().toLowerCase();
    return rows.filter(function (row) { return (row.label + " " + (row.detail || "")).toLowerCase().indexOf(q) >= 0; });
}

function formCommand(form, value, target) {
    var text = value.trim();
    if (form === "brightness") {
        if (!/^\d{1,3}$/.test(text) || Number(text) > 100) throw new Error("Brightness must be an integer from 0 to 100");
        return ["--json", "brightness", String(Number(text)), target.target];
    }
    if (form === "color") {
        if (!/^#?[0-9a-f]{6}$/i.test(text)) throw new Error("Use six hexadecimal digits, for example ff8800");
        return ["--json", "color", text, target.target];
    }
    if (form === "label") return ["label", target.target, text];
    if (!text || /^(none|other|all)$/i.test(text)) throw new Error("Enter a room name other than none, other or all");
    if (form === "newroom") return ["rooms", "assign", text, target.target];
    if (form === "rename") return ["rooms", "rename", target.label, text];
    throw new Error("Unknown action");
}

function resultMessage(success, message) {
    try {
        var result = JSON.parse(message);
        if (result.error) return result.error;
        var failed = (result.results || []).filter(function (r) { return r.status === "failed"; });
        if (failed.length) return failed.map(function (r) { return r.device + ": " + r.error; }).join("; ");
        if ((result.results || []).some(function (r) { return r.status === "unverified"; }))
            return "Cloud accepted the command; device change is not yet verified";
    } catch (e) {
        if (message) return message;
    }
    return success ? "Done" : "Command failed";
}
