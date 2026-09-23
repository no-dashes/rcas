// The worksheet. Everything mathematical happens in Ruby; this file takes
// a line of input to /api/eval and draws the cell that comes back.
"use strict";

const token = new URLSearchParams(location.search).get("token") || "";
const worksheet = document.getElementById("worksheet");
const greeting = document.getElementById("greeting");
const input = document.getElementById("input");
const promptLabel = document.getElementById("prompt");
const completions = document.getElementById("completions");
const modes = document.getElementById("modes");

const history = [];
let historyIndex = 0;
let draft = "";
let state = { mode: "typeset", theme: "auto", numbered: true, line: 1, version: "", modes: [] };

// ---- talking to Ruby -------------------------------------------------------

async function api(path, body) {
  const response = await fetch(path, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-RCAS-Token": token },
    body: JSON.stringify(body || {})
  });
  if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
  return response.json();
}

// ---- small DOM helpers -----------------------------------------------------

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined && text !== null) node.textContent = text;
  return node;
}

function line(tag, className) {
  const row = el("div", "line" + (className ? " " + className : ""));
  row.append(el("span", "tag", tag || ""));
  const body = el("div", "body");
  row.append(body);
  return { row, body };
}

// KaTeX renders into the node; without the package the source is shown
// instead, which is still the honest answer.
function typeset(latex) {
  const box = el("div", "tex");
  if (window.katex && !window.katexMissing) {
    try {
      window.katex.render(latex, box, { displayMode: true, throwOnError: false, strict: "ignore" });
      return box;
    } catch (e) {
      // fall through to the source
    }
  }
  return el("code", "source", latex);
}

function label(kind, n) {
  if (n === undefined || n === null) return "";
  return state.numbered ? `${kind}[${n}]` : kind;
}

// ---- drawing a cell --------------------------------------------------------

function draw(cell, source) {
  if (cell.kind === "clear") {
    worksheet.replaceChildren();
    if (cell.text) append(informational(cell));
    return;
  }
  if (cell.kind === "exit") {
    window.close();
    return;
  }
  const node = el("section", "cell");
  if (source !== undefined) {
    const { row, body } = line(label("In", cell.n), "in");
    body.textContent = source;
    body.title = "click to edit this line again";
    body.addEventListener("click", () => {
      input.value = source;
      autosize();
      input.focus();
    });
    node.append(row);
  }
  for (const part of output(cell)) node.append(part);
  append(node);
}

function append(node) {
  if (greeting && greeting.isConnected) greeting.remove();
  worksheet.append(node);
  worksheet.scrollTop = worksheet.scrollHeight;
}

// The Out row (or whatever the command produced) for one cell.
function output(cell) {
  switch (cell.kind) {
    case "result": return [result(cell)];
    case "error": return [failure(cell)];
    case "help": return [commandTable(cell.commands)];
    case "doc": return [documentation(cell)];
    case "vars": return [rowTable(cell)];
    default: return cell.text ? [informational(cell)] : [];
  }
}

function result(cell) {
  const { row, body } = line(label("Out", cell.n));
  if (cell.stdout) body.append(el("pre", "stdout", cell.stdout));

  // A plot is a picture here, the way it is braille art in a terminal;
  // only /output text asks for the characters.
  const drawn = cell.svg && state.mode !== "text";
  const showText = !drawn && (state.mode !== "typeset" || !cell.latex);
  if (showText && cell.text) body.append(el("pre", "text", cell.text));
  if (drawn) {
    const plot = el("div", "plot");
    plot.innerHTML = cell.svg; // Plot#to_svg builds this string itself
    body.append(plot);
  }
  if (cell.latex && (state.mode === "typeset" || state.mode === "both")) body.append(typeset(cell.latex));
  if (cell.latex && state.mode === "latex") body.append(el("code", "source", cell.latex));
  if (cell.note) body.append(el("div", "note", cell.note));
  if (cell.seconds > 0.25) body.append(el("div", "took", `${cell.seconds.toFixed(2)} s`));
  return row;
}

function failure(cell) {
  const { row, body } = line(label("Out", cell.n));
  body.append(el("pre", "text error", cell.text));
  if (cell.hint && cell.hint.length) {
    const hint = el("div", "hint");
    for (const text of cell.hint) hint.append(el("span", null, text));
    body.append(hint);
  }
  return row;
}

function informational(cell) {
  const { row, body } = line("");
  body.append(el("pre", cell.kind === "error" ? "text error" : "stdout", cell.text));
  return row;
}

function commandTable(commands) {
  const { row, body } = line("");
  const table = el("table", "rows");
  for (const [name, description] of Object.entries(commands || {})) {
    const tr = el("tr");
    tr.append(el("td", "name", name));
    tr.append(el("td", null, description));
    table.append(tr);
  }
  body.append(table);
  return row;
}

function rowTable(cell) {
  const { row, body } = line("");
  const table = el("table", "rows");
  for (const entry of cell.rows || []) {
    const tr = el("tr");
    tr.append(el("td", "name", entry.name));
    const value = el("td", "value");
    if (entry.latex && (state.mode === "typeset" || state.mode === "both")) value.append(typeset(entry.latex));
    else value.textContent = entry.text;
    tr.append(value);
    table.append(tr);
  }
  body.append(table);
  return row;
}

// /help NAME: the signature, the comment block, and the background and
// reading that rcas keeps for the name.
function documentation(cell) {
  const { row, body } = line("");
  const doc = el("div", "doc");
  doc.append(el("h2", null, cell.signature));
  for (const text of cell.lines || []) doc.append(el("p", null, text));
  if (cell.also) doc.append(field("also", cell.also));
  for (const entry of cell.background || []) doc.append(field(entry.label, entry.text));
  for (const source of cell.sources || []) doc.append(field("source", source));
  if (cell.reading && cell.reading.length) {
    const links = el("div", "field");
    links.append(el("b", null, "read: "));
    cell.reading.forEach((href, i) => {
      if (i) links.append(document.createTextNode(", "));
      const a = el("a", null, href.replace(/^https?:\/\/(en\.)?wikipedia\.org\/wiki\//, ""));
      a.href = href;
      a.target = "_blank";
      a.rel = "noopener noreferrer";
      links.append(a);
    });
    doc.append(links);
  }
  if (cell.sections && cell.sections.length) doc.append(field("manual", cell.sections.join("; ")));
  body.append(doc);
  return row;
}

function field(name, text) {
  const node = el("div", "field");
  node.append(el("b", null, `${name}: `));
  node.append(document.createTextNode(text));
  return node;
}

// ---- the session -----------------------------------------------------------

// What "auto" actually came to in this window: plots are drawn in Ruby,
// which cannot see a media query.
function resolvedTheme() {
  if (state.theme !== "auto") return state.theme;
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}

function applyState(next) {
  state = Object.assign(state, next || {});
  document.getElementById("version").textContent = state.version || "";
  if (state.theme === "auto") document.documentElement.removeAttribute("data-theme");
  else document.documentElement.setAttribute("data-theme", state.theme);
  promptLabel.textContent = state.numbered ? `In[${state.line}]` : "In";
  if (state.modes && modes.children.length !== state.modes.length) drawModes(state.modes);
  for (const button of modes.children) button.setAttribute("aria-pressed", String(button.dataset.mode === state.mode));
}

// `typed` is the text as it was when Enter was pressed. Enter first asks
// the server whether the line is finished, and what is typed while that
// answer is on its way belongs to the next line, not to this one: reading
// input.value here submitted "1 + 12" for "1 + 1" followed by a quick "2"
// (a review, 23 Sept 2026). Text added after the submitted line stays in
// the field; an edit anywhere else leaves the field as the reader made it.
async function submit(typed = input.value) {
  const source = typed.replace(/\s+$/, "");
  if (!source.trim()) return;
  const now = input.value;
  input.value = now === typed ? "" : now.startsWith(typed) ? now.slice(typed.length).replace(/^\n/, "") : now;
  autosize();
  hideCompletions();
  history.push(source);
  historyIndex = history.length;
  draft = "";
  try {
    const cell = await api("/api/eval", { source, theme: resolvedTheme() });
    draw(cell, cell.kind === "result" || cell.kind === "error" ? source : undefined);
    if (cell.state) applyState(cell.state);
    else applyState(await api("/api/state", {}));
  } catch (e) {
    draw({ kind: "error", text: `the session is gone: ${e.message}` }, source);
  }
}

// ---- input behaviour -------------------------------------------------------

function autosize() {
  input.style.height = "auto";
  input.style.height = `${input.scrollHeight}px`;
}

function caretLine() {
  const before = input.value.slice(0, input.selectionStart);
  return { first: !before.includes("\n"), last: !input.value.slice(input.selectionEnd).includes("\n") };
}

function recall(step) {
  if (historyIndex === history.length) draft = input.value;
  historyIndex = Math.min(Math.max(historyIndex + step, 0), history.length);
  input.value = historyIndex === history.length ? draft : history[historyIndex];
  autosize();
  const end = input.value.length;
  input.setSelectionRange(end, end);
}

async function complete() {
  const before = input.value.slice(0, input.selectionStart);
  const match = before.match(/[\p{L}_][\p{L}\p{N}_]*$/u);
  if (!match) return;
  const { candidates } = await api("/api/complete", { prefix: match[0] });
  if (!candidates || !candidates.length) return hideCompletions();
  const shared = candidates.reduce((a, b) => {
    let i = 0;
    while (i < a.length && i < b.length && a[i] === b[i]) i += 1;
    return a.slice(0, i);
  });
  if (shared.length > match[0].length) insertCompletion(match[0], shared);
  if (candidates.length === 1) return hideCompletions();
  showCompletions(candidates, match[0]);
}

function insertCompletion(prefix, word) {
  const start = input.selectionStart - prefix.length;
  input.setRangeText(word, start, input.selectionStart, "end");
  autosize();
}

function showCompletions(candidates, prefix) {
  completions.replaceChildren();
  for (const word of candidates.slice(0, 40)) {
    const button = el("button", null, word);
    button.type = "button";
    button.addEventListener("click", () => {
      const current = input.value.slice(0, input.selectionStart).match(/[\p{L}_][\p{L}\p{N}_]*$/u);
      insertCompletion(current ? current[0] : prefix, word);
      hideCompletions();
      input.focus();
    });
    completions.append(button);
  }
  completions.hidden = false;
}

function hideCompletions() {
  completions.hidden = true;
  completions.replaceChildren();
}

input.addEventListener("input", () => {
  autosize();
  if (!completions.hidden) hideCompletions();
});

// Enter never types anything: whether the line is finished has to be asked
// of Ruby, and preventDefault after an await comes too late to stop the
// browser inserting the newline first. So the default is cancelled at once
// and the newline, if the line turns out to be unfinished, is put in here.
//
// Only the latest Enter counts: a second one while the first is still
// being checked makes the first answer stale, and it is dropped.
let enterCount = 0;

async function enter() {
  const source = input.value;
  const mine = ++enterCount;
  if (source.trim() && !source.trim().startsWith("/")) {
    try {
      const { incomplete } = await api("/api/incomplete", { source });
      if (mine !== enterCount) return;
      // unfinished: the newline Enter stood for, unless the reader has
      // typed on in the meantime, which says the line was not done anyway
      if (incomplete) return input.value === source ? newline() : undefined;
    } catch (e) {
      if (mine !== enterCount) return;
      // the server is gone; submit and let that be reported
    }
  }
  submit(source);
}

// A line break at the caret, as typing one would have done. setRangeText
// fires no input event, so the two things that listener does are done here.
function newline() {
  input.setRangeText("\n", input.selectionStart, input.selectionEnd, "end");
  autosize();
  hideCompletions();
}

input.addEventListener("keydown", (event) => {
  // Mid-composition (an IME entering α, or Japanese, or Chinese) Enter and
  // the arrows belong to the IME, not to us.
  if (event.isComposing || event.keyCode === 229) return;
  if (event.key === "Enter" && !event.shiftKey) {
    event.preventDefault();
    enter();
    return;
  }
  if (event.key === "Tab") {
    event.preventDefault();
    complete();
    return;
  }
  if (event.key === "Enter" && event.shiftKey) {
    event.preventDefault();
    newline();
    return;
  }
  if (event.key === "Escape") return hideCompletions();
  if (event.key === "ArrowUp" && caretLine().first && history.length) {
    event.preventDefault();
    recall(-1);
    return;
  }
  if (event.key === "ArrowDown" && caretLine().last && historyIndex < history.length) {
    event.preventDefault();
    recall(1);
  }
});

// Typing anywhere goes to the input; the worksheet itself is only scrolled.
document.addEventListener("keydown", (event) => {
  if (event.target === input || event.metaKey || event.ctrlKey || event.altKey) return;
  if (event.key.length === 1 || event.key === "Backspace") input.focus();
});

// ---- chrome ----------------------------------------------------------------

// The buttons are named by Ruby, so the window and /output agree on what
// each mode is called.
function drawModes(list) {
  modes.replaceChildren();
  for (const mode of list) {
    const button = el("button", null, mode);
    button.type = "button";
    button.dataset.mode = mode;
    button.addEventListener("click", async () => {
      const cell = await api("/api/eval", { source: `/output ${mode}`, theme: resolvedTheme() });
      if (cell.state) applyState(cell.state);
    });
    modes.append(button);
  }
}

document.getElementById("help-button").addEventListener("click", () => {
  input.value = "/help";
  submit();
});

for (const button of document.querySelectorAll(".examples button")) {
  button.addEventListener("click", () => {
    input.value = button.textContent;
    autosize();
    input.focus();
  });
}

// A reloaded window comes back with the session it had: the values never
// left Ruby, only the page was thrown away.
async function restore() {
  applyState(await api("/api/state", {}));
  const { cells } = await api("/api/cells", {});
  for (const cell of cells || []) draw(cell, cell.input);
}

restore().catch(() => {});
autosize();
input.focus();
