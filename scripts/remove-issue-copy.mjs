import fs from "node:fs";
import path from "node:path";

const root = path.resolve(".");
const removedText = [
  "Live repository powered by Supabase public.projects",
  "Projects inserted into your Supabase projects table with is_active = true will immediately appear here.",
  "Submitters appear strictly as \"Anonymous\" for privacy protection",
  "(Submitter Masked)",
  "Submitter is masked as Anonymous on the public board."
];

const ignoredDirs = new Set([".git", ".netlify", "node_modules"]);
const textExts = new Set([".html", ".htm", ".js", ".mjs", ".cjs", ".txt", ".md", ".json", ".css"]);

function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (ignoredDirs.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (textExts.has(path.extname(entry.name).toLowerCase())) sanitize(full);
  }
}

function sanitize(file) {
  let text;
  try { text = fs.readFileSync(file, "utf8"); } catch { return; }
  let updated = text;
  for (const phrase of removedText) updated = updated.split(phrase).join("");
  if (updated !== text) {
    fs.writeFileSync(file, updated, "utf8");
    console.log(`Sanitized issue copy: ${path.relative(root, file)}`);
  }
}

walk(root);
console.log("Issue-board copy sanitization complete.");
