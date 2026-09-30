import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const file = join(process.cwd(), "_next/static/chunks/app/page-d146f388bacf79b3.js");
const source = await readFile(file, "utf8");

const pattern = /if\(r\)\{let e=await _\.auth\.verifyOtp\(\{email:H\.trim\(\),token:Q\.trim\(\),type:\"signup\"\}\);if\(e\.error\)throw e\.error;e\.data\.user&&await eC\(e\.data\.user\.id,e\.data\.user\.email\|\|H,\(null==\(t=e\.data\.user\.user_metadata\)\?void 0:t\.name\)\|\|W\)\}else e\.user&&await eC\(e\.user\.id,e\.user\.email\|\|H,\(null==\(s=e\.user\.user_metadata\)\?void 0:s\.name\)\|\|W\);/;
const replacement = 'if(r)throw r;else e.user&&await eC(e.user.id,e.user.email||H,(null==(s=e.user.user_metadata)?void 0:s.name)||W);';

if (!pattern.test(source)) {
  throw new Error("RootDeck OTP auth fallback pattern was not found; refusing to modify the compiled bundle.");
}

const patched = source.replace(pattern, replacement);
await writeFile(file, patched, "utf8");
console.log("RootDeck OTP auth fixed: verifyOtp now uses only type=\"email\".");
