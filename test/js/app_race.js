// The worksheet's Enter, run against the real app.js with a stub DOM and a
// fetch whose /api/incomplete answer waits until the test releases it.
// Pressing Enter on "1 + 1" and typing "2" before the answer came submitted
// "1 + 12" (a review, 23 Sept 2026). Run by test/app_test.rb when node is
// installed; exits non-zero on a failure. Plain Node, no packages.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");

function fakeElement() {
  const listeners = {};
  const target = {
    value: "", style: {}, children: [], dataset: {}, hidden: true, textContent: "",
    selectionStart: 0, selectionEnd: 0, scrollHeight: 10, listeners,
    addEventListener(type, f) { (listeners[type] = listeners[type] || []).push(f); },
    setRangeText(s, a, b) { this.value = this.value.slice(0, a) + s + this.value.slice(b); },
    classList: { add() {}, remove() {}, toggle() {} }
  };
  // anything else the page asks of an element is a harmless no-op
  return new Proxy(target, { get: (t, k) => (k in t ? t[k] : () => fakeElement()) });
}

const elements = {};
const document = {
  getElementById: (id) => (elements[id] = elements[id] || fakeElement()),
  createElement: fakeElement, createTextNode: () => ({}), documentElement: fakeElement(),
  querySelectorAll: () => [], addEventListener() {}
};
const evaluated = [];
const pending = [];
async function fetch(route, options) {
  const body = JSON.parse(options.body);
  if (route === "/api/incomplete") await new Promise((release) => pending.push(release));
  if (route === "/api/eval") evaluated.push(body.source);
  const json = route === "/api/incomplete" ? { incomplete: false } : route === "/api/cells" ? { cells: [] } : { kind: "result", text: "", state: {} };
  return { ok: true, json: async () => json };
}
const media = () => ({ matches: false, addEventListener() {} });
const context = vm.createContext({ document, fetch, location: { search: "" }, URLSearchParams, console, setTimeout, window: { matchMedia: media }, matchMedia: media });
vm.runInContext(fs.readFileSync(path.join(__dirname, "../../lib/rcas/app/public/app.js"), "utf8"), context);

const input = elements.input;
const enter = () => input.listeners.keydown.forEach((f) => f({ key: "Enter", shiftKey: false, preventDefault() {} }));
const settle = () => new Promise((done) => setTimeout(done, 10));
const failures = [];
const expect = (what, actual, wanted) => {
  if (JSON.stringify(actual) !== JSON.stringify(wanted)) failures.push(`${what}: ${JSON.stringify(actual)}, wanted ${JSON.stringify(wanted)}`);
};

(async () => {
  await settle();
  input.value = "1 + 1";
  enter();
  input.value = "1 + 12"; // typed while the check is on its way
  pending.shift()();
  await settle();
  expect("the line submitted", evaluated, ["1 + 1"]);
  expect("what was typed after it", input.value, "2");

  input.value = "2 + 2";
  enter();
  input.value = "3 + 3";
  enter(); // the first Enter's answer is stale now
  pending.shift()();
  pending.shift()();
  await settle();
  expect("two Enters submit once", evaluated, ["1 + 1", "3 + 3"]);

  if (failures.length) {
    console.log(failures.join("\n"));
    process.exit(1);
  }
  console.log("ok");
})();
