const GH_OWNER = "bta2025";
const GH_REPO = "Preenia-plugins";
const GH_FILE = "AI%20Image%20Generator%20and%20Editor.json";
const GH_API = "https://api.github.com";
const FREE_DAILY_LIMIT = 3;
const IMGBB_KEY = "6c3c19148180756ca75df22b4d81f5ba";

const PRICE_1M = 0.99;
const PRICE_3M = 3.53;
const PRICE_6M = 6.39;
const PRICE_1Y = 8.93;

const SUPABASE_URL = "https://dydkrpmnafsnivjxmipj.supabase.co";
const SUPABASE_KEY = "sb_publishable_W_1Ofv9769iYEEn9dfyAHQ_OhuCER6g";
const SUPABASE_HEADERS = {
"User-Agent": "Dart/3.9 (dart:io)",
"Accept-Encoding": "gzip",
"x-supabase-client-platform": "android",
"x-client-info": "supabase-flutter/2.10.3",
"x-supabase-client-platform-version": "15 A15.0.2.0.VGWIDXM",
"Content-Type": "application/json; charset=utf-8",
"x-supabase-api-version": "2024-01-01"
};

function md5(string) {
function rotateLeft(x, n) { return (x << n) | (x >>> (32 - n)); }
function addUnsigned(x, y) {
const x8 = x & 0x80000000, y8 = y & 0x80000000;
const x4 = x & 0x40000000, y4 = y & 0x40000000;
const result = (x & 0x3FFFFFFF) + (y & 0x3FFFFFFF);
if (x4 & y4) return result ^ 0x80000000 ^ x8 ^ y8;
if (x4 | y4) return result & 0x40000000 ? result ^ 0xC0000000 ^ x8 ^ y8 : result ^ 0x40000000 ^ x8 ^ y8;
return result ^ x8 ^ y8;
}
function F(x, y, z) { return (x & y) | (~x & z); }
function G(x, y, z) { return (x & z) | (y & ~z); }
function H(x, y, z) { return x ^ y ^ z; }
function I(x, y, z) { return y ^ (x | ~z); }
function FF(a, b, c, d, x, s, ac) { return addUnsigned(rotateLeft(addUnsigned(addUnsigned(a, F(b, c, d)), addUnsigned(x, ac)), s), b); }
function GG(a, b, c, d, x, s, ac) { return addUnsigned(rotateLeft(addUnsigned(addUnsigned(a, G(b, c, d)), addUnsigned(x, ac)), s), b); }
function HH(a, b, c, d, x, s, ac) { return addUnsigned(rotateLeft(addUnsigned(addUnsigned(a, H(b, c, d)), addUnsigned(x, ac)), s), b); }
function II(a, b, c, d, x, s, ac) { return addUnsigned(rotateLeft(addUnsigned(addUnsigned(a, I(b, c, d)), addUnsigned(x, ac)), s), b); }
function convertToWordArray(str) {
const len = str.length, words = [];
for (let i = 0; i < len; i += 4) {
words.push((str.charCodeAt(i)) | (str.charCodeAt(i+1) << 8) | (str.charCodeAt(i+2) << 16) | (str.charCodeAt(i+3) << 24));
}
words[len >> 2] |= 0x80 << ((len % 4) * 8);
words[(((len + 8) >> 6) << 4) + 14] = len * 8;
return words;
}
function wordToHex(value) {
let hex = "";
for (let i = 0; i < 4; i++) hex += ((value >> (i * 8)) & 255).toString(16).padStart(2, "0");
return hex;
}
const x = convertToWordArray(string);
let a = 0x67452301, b = 0xEFCDAB89, c = 0x98BADCFE, d = 0x10325476;
const S = [[7,12,17,22],[5,9,14,20],[4,11,16,23],[6,10,15,21]];
const T = [
0xD76AA478,0xE8C7B756,0x242070DB,0xC1BDCEEE,0xF57C0FAF,0x4787C62A,0xA8304613,0xFD469501,
0x698098D8,0x8B44F7AF,0xFFFF5BB1,0x895CD7BE,0x6B901122,0xFD987193,0xA679438E,0x49B40821,
0xF61E2562,0xC040B340,0x265E5A51,0xE9B6C7AA,0xD62F105D,0x02441453,0xD8A1E681,0xE7D3FBC8,
0x21E1CDE6,0xC33707D6,0xF4D50D87,0x455A14ED,0xA9E3E905,0xFCEFA3F8,0x676F02D9,0x8D2A4C8A,
0xFFFA3942,0x8771F681,0x6D9D6122,0xFDE5380C,0xA4BEEA44,0x4BDECFA9,0xF6BB4B60,0xBEBFBC70,
0x289B7EC6,0xEAA127FA,0xD4EF3085,0x04881D05,0xD9D4D039,0xE6DB99E5,0x1FA27CF8,0xC4AC5665,
0xF4292244,0x432AFF97,0xAB9423A7,0xFC93A039,0x655B59C3,0x8F0CCC92,0xFFEFF47D,0x85845DD1,
0x6FA87E4F,0xFE2CE6E0,0xA3014314,0x4E0811A1,0xF7537E82,0xBD3AF235,0x2AD7D2BB,0xEB86D391
];
for (let k = 0; k < x.length; k += 16) {
const AA = a, BB = b, CC = c, DD = d;
for (let i = 0; i < 64; i++) {
let f, g;
if (i < 16) { f = FF; g = i; }
else if (i < 32) { f = GG; g = (5*i+1)%16; }
else if (i < 48) { f = HH; g = (3*i+5)%16; }
else { f = II; g = (7*i)%16; }
const temp = d; d = c; c = b;
b = f(a, b, c, temp, x[k+g]||0, S[Math.floor(i/16)][i%4], T[i]);
a = temp;
}
a = addUnsigned(a, AA); b = addUnsigned(b, BB); c = addUnsigned(c, CC); d = addUnsigned(d, DD);
}
return wordToHex(a) + wordToHex(b) + wordToHex(c) + wordToHex(d);
}

function hashEmail(email) { return md5(email.toLowerCase().trim()); }

function getCurrentDate() {
const now = new Date();
return `${now.getFullYear()}${String(now.getMonth()+1).padStart(2,"0")}${String(now.getDate()).padStart(2,"0")}`;
}

function isSubscriptionActive(expiryDate) {
if (expiryDate === "permanent") return true;
return expiryDate > getCurrentDate();
}

function ghHeaders(token) {
return {
"Authorization": `Bearer ${token}`,
"Accept": "application/vnd.github+json",
"Content-Type": "application/json",
"X-GitHub-Api-Version": "2022-11-28",
"User-Agent": "Preenia-Worker"
};
}

function b64Encode(str) {
const bytes = new TextEncoder().encode(str);
let binary = "";
const chunk = 8192;
for (let i = 0; i < bytes.length; i += chunk) binary += String.fromCharCode(...bytes.subarray(i, i+chunk));
return btoa(binary);
}

function toBase64(buffer) {
const bytes = new Uint8Array(buffer);
let binary = "";
const chunk = 8192;
for (let i = 0; i < bytes.length; i += chunk) binary += String.fromCharCode(...bytes.subarray(i, i+chunk));
return btoa(binary);
}

async function readDB(token) {
const res = await fetch(`${GH_API}/repos/${GH_OWNER}/${GH_REPO}/contents/${GH_FILE}`, { headers: ghHeaders(token) });
if (!res.ok) {
const errBody = await res.text();
throw new Error(`GitHub read failed: ${res.status} - ${errBody}`);
}
const meta = await res.json();
const content = JSON.parse(atob(meta.content.replace(/\n/g, "")));
return { data: content, sha: meta.sha };
}

async function writeDB(content, sha, token, attempt = 0) {
const res = await fetch(`${GH_API}/repos/${GH_OWNER}/${GH_REPO}/contents/${GH_FILE}`, {
method: "PUT",
headers: ghHeaders(token),
body: JSON.stringify({ message: "Update user database", content: b64Encode(JSON.stringify(content)), sha })
});
if (res.ok) return;
const errText = await res.text();
if (attempt < 2) {
await new Promise(r => setTimeout(r, 1500 * (attempt + 1)));
return writeDB(content, sha, token, attempt + 1);
}
throw new Error(`GitHub write failed: ${res.status} ${errText}`);
}

async function uploadToImgbb(b64Image) {
const form = new FormData();
form.append("key", IMGBB_KEY);
form.append("image", b64Image);
const res = await fetch("https://api.imgbb.com/1/upload", { method: "POST", body: form });
if (!res.ok) throw new Error(`ImgBB upload failed: ${res.status}`);
const data = await res.json();
if (!data.data?.url) throw new Error("ImgBB returned no URL");
return data.data.url;
}

async function getSupabaseToken() {
const res = await fetch(`${SUPABASE_URL}/auth/v1/signup`, {
method: "POST",
headers: { ...SUPABASE_HEADERS, apikey: SUPABASE_KEY, Authorization: `Bearer ${SUPABASE_KEY}` },
body: JSON.stringify({ data: {}, gotrue_meta_security: { captcha_token: null } })
});
const data = await res.json();
return data.access_token || null;
}

function supabaseAuthHeaders(token) {
return { ...SUPABASE_HEADERS, apikey: SUPABASE_KEY, Authorization: `Bearer ${token}` };
}

function jsonResponse(data, status = 200) {
return new Response(JSON.stringify(data), {
status,
headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" }
});
}

async function verifyUser(db, email, password, device_id) {
const emailHash = hashEmail(email);
const user = db.users[emailHash];
if (!user) return { error: jsonResponse({ success: false, message: "Account not found." }, 404) };
if (user.password !== md5(password)) return { error: jsonResponse({ success: false, message: "Invalid password." }, 401) };
if (user.device_id !== device_id) return { error: jsonResponse({ success: false, message: "Device ID mismatch. Contact admin to update your device." }, 403) };
return { user, emailHash };
}

async function checkAndDeductLimit(db, sha, user, emailHash, isPremium, token) {
const currentDate = getCurrentDate();
if (!isPremium) {
if (user.last_reset_date !== currentDate) {
user.generations_left = FREE_DAILY_LIMIT;
user.last_reset_date = currentDate;
}
if (user.generations_left <= 0) {
return { error: jsonResponse({ success: false, message: "Daily limit reached. Upgrade to premium for unlimited access!", expiry_date: "not subscribed", generations_left: 0 }, 403) };
}
user.generations_left -= 1;
}
user.total_generations = (user.total_generations || 0) + 1;
db.users[emailHash] = user;
await writeDB(db, sha, token);
return { ok: true };
}

async function handleAccount(request, token) {
try {
const body = await request.json();
const { email, password, device_id } = body;
if (!email || !password || !device_id) return jsonResponse({ success: false, message: "Missing fields: email, password, device_id" }, 400);
const { data: db, sha } = await readDB(token);
const emailHash = hashEmail(email);
let user = db.users[emailHash];
if (!user) {
user = {
email, password: md5(password), device_id,
expiry_date: "20250101", generations_left: FREE_DAILY_LIMIT,
total_generations: 0, last_reset_date: getCurrentDate(),
created_at: new Date().toISOString()
};
db.users[emailHash] = user;
await writeDB(db, sha, token);
return jsonResponse({ success: true, message: "Account created successfully", expiry_date: "not subscribed", generations_left: FREE_DAILY_LIMIT, total_generations: 0, prices: { "1_month": PRICE_1M, "3_months": PRICE_3M, "6_months": PRICE_6M, "1_year": PRICE_1Y } });
}
if (user.password !== md5(password)) return jsonResponse({ success: false, message: "Invalid password." }, 401);
if (user.device_id !== device_id) return jsonResponse({ success: false, message: "Device ID mismatch. Contact admin to update your device." }, 403);
const isPremium = isSubscriptionActive(user.expiry_date);
const currentDate = getCurrentDate();
if (!isPremium && user.last_reset_date !== currentDate) {
user.generations_left = FREE_DAILY_LIMIT;
user.last_reset_date = currentDate;
db.users[emailHash] = user;
await writeDB(db, sha, token);
}
if (isPremium) return jsonResponse({ success: true, message: "Account verified successfully", expiry_date: user.expiry_date, total_generations: user.total_generations });
return jsonResponse({ success: true, message: "Account verified successfully", expiry_date: "not subscribed", generations_left: user.generations_left, total_generations: user.total_generations });
} catch (e) {
return jsonResponse({ success: false, message: `Error: ${e.message}` }, 500);
}
}

async function handleGenerate(request, token) {
try {
const body = await request.json();
const { email, password, device_id, prompt } = body;
if (!email || !password || !device_id || !prompt) return jsonResponse({ success: false, message: "Missing fields: email, password, device_id, prompt" }, 400);
const { data: db, sha } = await readDB(token);
const { user, emailHash, error } = await verifyUser(db, email, password, device_id);
if (error) return error;
const isPremium = isSubscriptionActive(user.expiry_date);
const limitResult = await checkAndDeductLimit(db, sha, user, emailHash, isPremium, token);
if (limitResult.error) return limitResult.error;
const sbToken = await getSupabaseToken();
if (!sbToken) return jsonResponse({ success: false, message: "Backend auth failed." }, 500);
const count = isPremium ? 4 : 1;
const results = await Promise.all(Array.from({ length: count }, () =>
fetch(`${SUPABASE_URL}/functions/v1/generate-image`, {
method: "POST",
headers: supabaseAuthHeaders(sbToken),
body: JSON.stringify({ prompt, model: "fal-ai/flux-2" })
}).then(r => r.json())
));
const imageUrls = await Promise.all(results.map(async (imgData, i) => {
if (!imgData.image) throw new Error(`Image ${i + 1} generation failed.`);
return await uploadToImgbb(imgData.image);
}));return jsonResponse({ success: true, image_urls: imageUrls, is_premium: isPremium, generations_left: isPremium ? null : user.generations_left, total_generations: user.total_generations });
} catch (e) {
return jsonResponse({ success: false, message: `Error: ${e.message}` }, 500);
}
}

async function handleEdit(request, token) {
try {
const body = await request.json();
const { email, password, device_id, prompt, url } = body;
if (!email || !password || !device_id || !prompt || !url) return jsonResponse({ success: false, message: "Missing fields: email, password, device_id, prompt, url" }, 400);
const { data: db, sha } = await readDB(token);
const { user, emailHash, error } = await verifyUser(db, email, password, device_id);
if (error) return error;
const isPremium = isSubscriptionActive(user.expiry_date);
const limitResult = await checkAndDeductLimit(db, sha, user, emailHash, isPremium, token);
if (limitResult.error) return limitResult.error;
const sbToken = await getSupabaseToken();
if (!sbToken) return jsonResponse({ success: false, message: "Backend auth failed." }, 500);
const imgRes = await fetch(url);
if (!imgRes.ok) return jsonResponse({ success: false, message: "Failed to fetch image from URL." }, 400);
const b64 = toBase64(await imgRes.arrayBuffer());
const count = isPremium ? 4 : 1;
const results = await Promise.all(Array.from({ length: count }, () =>
fetch(`${SUPABASE_URL}/functions/v1/edit-image`, {
method: "POST",
headers: supabaseAuthHeaders(sbToken),
body: JSON.stringify({ image: b64, mimeType: "image/jpeg", prompt, model: "fal-ai/flux-2", isFirstAttempt: true })
}).then(r => r.json())
));
const imageUrls = await Promise.all(results.map(async (editData, i) => {
if (!editData.image) throw new Error(`Image ${i + 1} edit failed.`);
return await uploadToImgbb(editData.image);
}));
return jsonResponse({ success: true, image_urls: imageUrls, is_premium: isPremium, generations_left: isPremium ? null : user.generations_left, total_generations: user.total_generations });
} catch (e) {
return jsonResponse({ success: false, message: `Error: ${e.message}` }, 500);
}
}

export default {
async fetch(request, env) {
const token = env.GH_TOKEN;
const url = new URL(request.url);
if (request.method === "OPTIONS") {
return new Response(null, { headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "POST, OPTIONS", "Access-Control-Allow-Headers": "Content-Type" } });
}
if (url.pathname === "/account" && request.method === "POST") return handleAccount(request, token);
if (url.pathname === "/api/generate" && request.method === "POST") return handleGenerate(request, token);
if (url.pathname === "/api/edit" && request.method === "POST") return handleEdit(request, token);
return jsonResponse({ status: "Running", endpoints: ["POST /account", "POST /api/generate", "POST /api/edit"] });
}
};
