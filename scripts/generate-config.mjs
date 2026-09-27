import fs from "node:fs";
import path from "node:path";

const publishDir = path.resolve(".");
const url = process.env.NEXT_PUBLIC_SUPABASE_URL || "";
const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || "";
const appUrl = process.env.APP_URL || "";

if (!url || !anonKey) {
  throw new Error("Missing NEXT_PUBLIC_SUPABASE_URL or NEXT_PUBLIC_SUPABASE_ANON_KEY in Netlify environment variables.");
}

const config = `window.__ROOTDECK_CONFIG__ = ${JSON.stringify({
  SUPABASE_URL: url,
  SUPABASE_ANON_KEY: anonKey,
  APP_URL: appUrl
})};`;

fs.writeFileSync(path.join(publishDir, "config.js"), config + "\n", "utf8");
console.log("RootDeck runtime config generated.");
