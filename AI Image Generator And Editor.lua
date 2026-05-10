require "import"
import "android.provider.Settings"
import "android.content.Context"
import "android.accounts.AccountManager"

local PREFS_NAME = "AI Image Generator and Editor (Premium)"
local BASE_API = "https://ai-image.shrishyamdevs.com"
local CHAT_API = "https://ai-chat.shrishyamdevs.com/v1/chat/completions"
local IMGBB_KEY = "6c3c19148180756ca75df22b4d81f5ba"
local BRAND_DIR = "Shri Shyam Devs"
local SAVE_DIR = "AI Image Generator and Editor"
local IMAGE_EXTS = {jpg=true,jpeg=true,png=true,webp=true,bmp=true,gif=true}
local serverPrices = {}

local vpnDialogShowing = false
local pluginExited = false

function isVpnActive()
local ok, result = pcall(function()
local cm = this.getSystemService(Context.CONNECTIVITY_SERVICE)
if cm == nil then return false end
local network = cm.getActiveNetwork()
if network == nil then return false end
local caps = cm.getNetworkCapabilities(network)
if caps == nil then return false end
return caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
end)
return ok and result or false
end

function showVpnDialog()
if vpnDialogShowing or pluginExited then return end
vpnDialogShowing = true
local layout = {
LinearLayout, orientation="vertical", layout_width="fill", layout_height="wrap", padding="28dp", backgroundColor="#1A1A2E",
{TextView, text="VPN Detected", textSize="20sp", textColor="#E94560", gravity="center", layout_marginBottom="10dp"},
{TextView, text="A VPN connection was detected. This plugin requires a direct connection to function. Please disable your VPN and reopen the plugin.", textSize="14sp", textColor="#AAAAAA", gravity="center", layout_marginBottom="24dp"},
{Button, id="vpnCloseBtn", text="OK", layout_width="fill", layout_height="50dp", textSize="15sp", backgroundColor="#E94560", textColor="#FFFFFF"}
}
vpnDlg = LuaDialog(this).setView(loadlayout(layout)).setCancelable(false)
vpnCloseBtn.onClick = function()
pluginExited = true
vpnDialogShowing = false
vpnDlg.dismiss()
if loadingDlg then pcall(function() loadingDlg.dismiss() end) end
if mainDlg then pcall(function() mainDlg.dismiss() end) end
if accountDlg then pcall(function() accountDlg.dismiss() end) end
if dashDlg then pcall(function() dashDlg.dismiss() end) end
end
vpnDlg.show()
end

function checkVpnThenRun(callback)
if isVpnActive() then showVpnDialog()
else callback() end
end

function isImageFile(name)
local e = name:match("%.(%w+)$")
return e and IMAGE_EXTS[e:lower()]
end

function writeToFile(path, content)
return pcall(function()
local f = io.open(path, "wb")
if f then f:write(content) f:close() end
end)
end

function cleanFilename(text)
if not text or text == "" then return "image" end
local s = text:gsub("^%s*(.-)%s*$", "%1"):sub(1, 50)
s = s:gsub("[^%w%s%-_]", ""):gsub("%s+", "_")
return s ~= "" and s or "image"
end

function sanitizePrompt(text)
if not text then return "" end
text = tostring(text)
text = text:gsub("\n", " "):gsub("\r", " "):gsub("\t", " "):gsub("\0", "")
text = text:gsub(".", function(c)
local b = string.byte(c)
if b < 32 or b == 127 then return " " end
return c
end)
return text:gsub("%s+", " "):gsub("^%s*(.-)%s*$", "%1")
end

function createSaveDir()
local ok, dir = pcall(function()
local dl = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
local brand = File(dl, BRAND_DIR)
if not brand.exists() then brand.mkdirs() end
local d = File(brand, SAVE_DIR)
if not d.exists() then d.mkdirs() end
return d
end)
return ok and dir or nil
end

function readStream(stream)
local byteT = luajava.bindClass("java.lang.Byte").TYPE
local baos = ByteArrayOutputStream()
local buf = luajava.newArray(byteT, 4096)
while true do
local n = stream.read(buf, 0, 4096)
if n == -1 then break end
baos.write(buf, 0, n)
end
stream.close()
local bytes = baos.toByteArray()
baos.close()
return bytes, tostring(luajava.newInstance("java.lang.String", bytes))
end

function uploadBytesToImgbb(imgBytes)
local b64 = tostring(Base64.encodeToString(imgBytes, Base64.NO_WRAP))
local boundary = "Boundary" .. tostring(os.time())
local conn = URL("https://api.imgbb.com/1/upload").openConnection()
conn.setRequestMethod("POST")
conn.setDoOutput(true)
conn.setConnectTimeout(30000)
conn.setReadTimeout(60000)
conn.setRequestProperty("Content-Type", "multipart/form-data; boundary=" .. boundary)
local out = DataOutputStream(conn.getOutputStream())
out.writeBytes("--" .. boundary .. "\r\n")
out.writeBytes("Content-Disposition: form-data; name=\"key\"\r\n\r\n")
out.writeBytes(IMGBB_KEY .. "\r\n")
out.writeBytes("--" .. boundary .. "\r\n")
out.writeBytes("Content-Disposition: form-data; name=\"image\"\r\n\r\n")
out.writeBytes(b64 .. "\r\n")
out.writeBytes("--" .. boundary .. "--\r\n")
out.flush()
out.close()
local code = conn.getResponseCode()
if code ~= 200 then
local _, errText = readStream(conn.getErrorStream())
error("ImgBB HTTP " .. code .. ": " .. errText)
end
local _, respText = readStream(conn.getInputStream())
local parsed = require("cjson").decode(respText)
if not parsed or not parsed.data or not parsed.data.url then
error("Invalid ImgBB response")
end
return parsed.data.url
end

function uploadToImgbb(imagePath, callback)
checkVpnThenRun(function()
Thread(Runnable{run=function()
local ok, result = pcall(function()
local byteT = luajava.bindClass("java.lang.Byte").TYPE
local fis = FileInputStream(File(imagePath))
local baos = ByteArrayOutputStream()
local buf = luajava.newArray(byteT, 4096)
while true do
local n = fis.read(buf, 0, 4096)
if n == -1 then break end
baos.write(buf, 0, n)
end
fis.close()
local imgBytes = baos.toByteArray()
baos.close()
return uploadBytesToImgbb(imgBytes)
end)
Handler(Looper.getMainLooper()).post(Runnable{run=function()
if ok then callback(true, result) else callback(false, tostring(result)) end
end})
end}).start()
end)
end

function openUrl(url)
this.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
end

function getSharedPreferences()
return this.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
end

function saveCredentials(email, password, deviceId)
local editor = getSharedPreferences().edit()
editor.putString("email", email)
editor.putString("password", password)
editor.putString("device_id", deviceId)
editor.apply()
end

function getCredentials()
local prefs = getSharedPreferences()
return {
email = prefs.getString("email", ""),
password = prefs.getString("password", ""),
device_id = prefs.getString("device_id", "")
}
end

function clearCredentials()
getSharedPreferences().edit().clear().apply()
end

function getDeviceId()
return Settings.Secure.getString(this.getContentResolver(), Settings.Secure.ANDROID_ID)
end

function getGoogleAccounts()
local am = AccountManager.get(this)
local accounts = am.getAccountsByType("com.google")
local list = {}
for i = 0, #accounts - 1 do
table.insert(list, tostring(accounts[i].name))
end
return list
end

function apiCall(path, payload, readTimeout, callback)
checkVpnThenRun(function()
Thread(Runnable{run=function()
local success, codeOrErr, responseText = pcall(function()
local body = require("cjson").encode(payload)
local conn = URL(BASE_API .. path).openConnection()
conn.setRequestMethod("POST")
conn.setDoOutput(true)
conn.setConnectTimeout(15000)
conn.setReadTimeout(readTimeout or 30000)
conn.setRequestProperty("Content-Type", "application/json")
local dos = DataOutputStream(conn.getOutputStream())
dos.writeBytes(body)
dos.flush()
dos.close()
local c = conn.getResponseCode()
local stream = (c >= 200 and c < 300) and conn.getInputStream() or conn.getErrorStream()
local _, t = readStream(stream)
return c, t
end)
Handler(Looper.getMainLooper()).post(Runnable{run=function()
if not success then callback(false, tostring(codeOrErr)) return end
local pok, data = pcall(require("cjson").decode, responseText)
if not pok then callback(false, "JSON parse error") return end
if data.success then callback(true, data)
else callback(false, data.message or "Request failed") end
end})
end}).start()
end)
end

function verifyAccount(email, password, deviceId, callback)
apiCall("/account", {email=email, password=password, device_id=deviceId}, 30000, callback)
end

function generateImage(prompt, creds, callback)
apiCall("/api/generate", {email=creds.email, password=creds.password, device_id=creds.device_id, prompt=prompt}, 120000, callback)
end

function editImage(prompt, imagePath, creds, callback)
local function doEdit(imageUrl)
apiCall("/api/edit", {email=creds.email, password=creds.password, device_id=creds.device_id, prompt=prompt, url=imageUrl}, 120000, callback)
end
if imagePath:match("^https?://") then
doEdit(imagePath)
else
uploadToImgbb(imagePath, function(ok, urlOrErr)
if not ok then callback(false, "Upload error: " .. urlOrErr) return end
doEdit(urlOrErr)
end)
end
end

function enhancePrompt(prompt, isEdit, callback)
local sysPrompt = isEdit
and "You improve AI image editing prompts. Reply with only the improved editing instruction text, no explanations, no quotes, no extra text."
or "You improve AI image generation prompts. Reply with only the improved prompt text, no explanations, no quotes, no extra text."
local userMsg = isEdit
and "Improve this image editing instruction: " .. prompt
or "Improve this prompt for image generation: " .. prompt
local body = require("cjson").encode({
model = "llama-3.3-70b-versatile",
temperature = 0.7,
max_tokens = 512,
messages = {
{role="system", content=sysPrompt},
{role="user", content=userMsg}
}
})
Http.post(CHAT_API, body, {["Content-Type"]="application/json"}, function(code, content)
if code == 200 then
local ok, data = pcall(require("cjson").decode, content)
if ok and data then
local msg = nil
if data.choices and data.choices[1] and data.choices[1].message then
msg = data.choices[1].message.content
elseif type(data.message) == "string" and data.message ~= "" then
msg = data.message
end
if msg and msg ~= "" then
callback(true, msg:gsub("^%s*(.-)%s*$", "%1"))
return
end
end
callback(false, "Invalid response")
else
callback(false, "HTTP " .. tostring(code))
end
end)
end

function fetchBitmap(imageSource, callback)
if not imageSource or imageSource == "" then callback(nil) return end
if imageSource:match("^https?://") then
Thread(Runnable{run=function()
local ok, bmp = pcall(function()
local conn = URL(imageSource).openConnection()
conn.setConnectTimeout(15000)
conn.setReadTimeout(30000)
return BitmapFactory.decodeStream(conn.getInputStream())
end)
Handler(Looper.getMainLooper()).post(Runnable{run=function()
callback(ok and bmp or nil)
end})
end}).start()
else
callback(BitmapFactory.decodeFile(imageSource))
end
end

function showImageViewer(imageSource)
if not imageSource or imageSource == "" then
Toast.makeText(this, "No image to display", Toast.LENGTH_SHORT).show()
return
end
fetchBitmap(imageSource, function(bmp)
if not bmp then
Toast.makeText(this, "Failed to load image", Toast.LENGTH_SHORT).show()
return
end
local layout = {
LinearLayout, orientation="vertical", layout_width="fill", layout_height="fill", backgroundColor="#000000",
{ImageView, id="viewerImg", layout_width="fill", layout_height="0dp", layout_weight=1, scaleType="fitCenter"},
{Button, id="viewerClose", text="Close", layout_width="fill", layout_height="52dp", textColor="#FFFFFF", backgroundColor="#E94560", textSize="15sp"}
}
local v = loadlayout(layout)
local dlg = LuaDialog(this).setView(v).setCancelable(true)
viewerImg.setImageBitmap(bmp)
viewerClose.onClick = function() dlg.dismiss() end
dlg.show()
end)
end

function showResultsDialog(urls, prompt)
local layout = {
LinearLayout, orientation="vertical", layout_width="fill", layout_height="wrap", padding="16dp", backgroundColor="#1A1A2E",
{TextView, text="Generated Images", textSize="18sp", textColor="#E94560", gravity="center", layout_marginBottom="14dp"},
{LinearLayout, id="imagesContainer", orientation="vertical", layout_width="fill", layout_height="wrap", padding="4dp"},
{Button, id="resultCloseBtn", text="Close", layout_width="fill", layout_height="48dp", textSize="14sp", backgroundColor="#E94560", textColor="#FFFFFF", layout_marginTop="8dp"}
}
local v = loadlayout(layout)
resultsDlg = LuaDialog(this).setView(v).setCancelable(true)
for i = 1, #urls do
local u = urls[i]
local idx = i
local row = {
LinearLayout, orientation="horizontal", layout_width="fill", layout_height="wrap", gravity="center_vertical",
{TextView, text="Image " .. idx, layout_width="0dp", layout_weight=1, layout_height="wrap", textSize="14sp", textColor="#FFFFFF"},
{Button, id="rvBtn"..idx, text="View", layout_width="wrap", layout_height="44dp", textSize="13sp", backgroundColor="#0F3460", textColor="#FFFFFF", layout_marginEnd="6dp"},
{Button, id="rsBtn"..idx, text="Save", layout_width="wrap", layout_height="44dp", textSize="13sp", backgroundColor="#533483", textColor="#FFFFFF"}
}
imagesContainer.addView(loadlayout(row))
local vb = _G["rvBtn"..idx]
local sb = _G["rsBtn"..idx]
vb.onClick = function() showImageViewer(u) end
sb.onClick = function()
local defName = cleanFilename(prompt) .. (idx > 1 and ("_" .. idx) or "")
local dir = createSaveDir()
if not dir then Toast.makeText(this, "Failed to create directory", Toast.LENGTH_SHORT).show() return end
local saveLayout = {
LinearLayout, orientation="vertical", layout_width="fill", layout_height="wrap", padding="20dp", backgroundColor="#1A1A2E",
{TextView, text="Save Image " .. idx, textSize="16sp", textColor="#E94560", gravity="center", layout_marginBottom="10dp"},
{EditText, id="rsSaveInput", text=defName, layout_width="fill", layout_height="wrap", textSize="14sp", padding="10dp", backgroundColor="#16213E", textColor="#FFFFFF", layout_marginBottom="12dp"},
{LinearLayout, orientation="horizontal", layout_width="fill", layout_height="wrap",
{Button, id="rsDoSave", text="Save", layout_width="0dp", layout_weight=1, layout_height="48dp", textSize="14sp", backgroundColor="#E94560", textColor="#FFFFFF", layout_marginEnd="6dp"},
{Button, id="rsCancel", text="Cancel", layout_width="0dp", layout_weight=1, layout_height="48dp", textSize="14sp", backgroundColor="#533483", textColor="#FFFFFF"}
}
}
rsSaveDlg = LuaDialog(this).setView(loadlayout(saveLayout)).setCancelable(true)
rsDoSave.onClick = function()
local fname = rsSaveInput.getText().toString():gsub("[^%w%s%-_]",""):gsub("%s+","_")
if fname == "" then fname = "image" end
rsSaveDlg.dismiss()
local f = File(dir, fname .. ".png")
Toast.makeText(this, "Saving...", Toast.LENGTH_SHORT).show()
Http.get(u, nil, function(code, data)
if code ~= 200 then Toast.makeText(this, "Download failed", Toast.LENGTH_SHORT).show() return end
local ok = writeToFile(tostring(f.getPath()), data)
if ok then
local intent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
intent.setData(Uri.fromFile(f))
this.sendBroadcast(intent)
Toast.makeText(this, "Saved: " .. fname, Toast.LENGTH_SHORT).show()
service.speak("Image " .. idx .. " saved")
else
Toast.makeText(this, "Save failed", Toast.LENGTH_SHORT).show()
end
end)
end
rsCancel.onClick = function() rsSaveDlg.dismiss() end
rsSaveDlg.show()
end
end
resultCloseBtn.onClick = function() resultsDlg.dismiss() end
resultsDlg.show()
end

function getSavedImages()
local files = {}
local dir = createSaveDir()
if not dir then return files end
local fl = dir.listFiles()
if not fl then return files end
local i = 0
while true do
local ok, f = pcall(function() return fl[i] end)
if not ok or not f then break end
if f.isFile() then
local e = tostring(f.getName()):match("%.(%w+)$")
if e and e:lower() == "png" then
table.insert(files, {name=tostring(f.getName()):gsub("%.%w+$",""), path=tostring(f.getPath()), size=f.length()})
end
end
i = i + 1
end
return files
end

function deleteFile(path)
local f = File(path)
return f.exists() and f.delete()
end

function deleteAllFiles()
local n = 0
for _, f in ipairs(getSavedImages()) do
if deleteFile(f.path) then n = n + 1 end
end
return n
end

function scanFolders()
local folders, seen = {}, {}
local root = Environment.getExternalStorageDirectory()
local roots = {}
if root then table.insert(roots, root) end
local subs = {"DCIM","Pictures","Downloads","WhatsApp/Media/WhatsApp Images","Telegram/Telegram Images","Screenshots"}
for _, s in ipairs(subs) do
local f = File(root, s)
if f.exists() and f.isDirectory() then table.insert(roots, f) end
end
local function scan(dir, depth)
if depth > 3 then return end
local fl = dir.listFiles()
if not fl then return end
local hasImg, i = false, 0
while true do
local ok, f = pcall(function() return fl[i] end)
if not ok or not f then break end
if f.isFile() and isImageFile(tostring(f.getName())) then hasImg = true end
i = i + 1
end
local dp = tostring(dir.getPath())
if hasImg and not seen[dp] then
seen[dp] = true
table.insert(folders, {name=tostring(dir.getName()), path=dp})
end
i = 0
while true do
local ok, f = pcall(function() return fl[i] end)
if not ok or not f then break end
if f.isDirectory() then scan(f, depth+1) end
i = i + 1
end
end
for _, r in ipairs(roots) do scan(r, 0) end
return folders
end

function getFolderImages(path)
local imgs = {}
local fl = File(path).listFiles()
if not fl then return imgs end
local i = 0
while true do
local ok, f = pcall(function() return fl[i] end)
if not ok or not f then break end
if f.isFile() and isImageFile(tostring(f.getName())) then
table.insert(imgs, {name=tostring(f.getName()), path=tostring(f.getPath())})
end
i = i + 1
end
return imgs
end

function showFolderImages(folderPath, folderName, onSelect)
local allImgs = getFolderImages(folderPath)
local filtered = {}
for _, v in ipairs(allImgs) do table.insert(filtered, v) end
local layout = {
LinearLayout, orientation="vertical", layout_width="fill", layout_height="fill", padding="14dp", backgroundColor="#1A1A2E",
{TextView, text=folderName, textSize="20sp", textColor="#E94560", gravity="center", layout_marginBottom="10dp"},
{EditText, id="imgSearch", hint="Search images...", layout_width="fill", layout_height="wrap", textSize="14sp", padding="10dp", backgroundColor="#16213E", textColor="#FFFFFF", layout_marginBottom="10dp"},
{ListView, id="imgList", layout_width="fill", layout_height="0dp", layout_weight=1, layout_marginBottom="10dp"},
{Button, id="imgBack", text="Back", layout_width="fill", layout_height="50dp", textColor="#FFFFFF", backgroundColor="#533483", textSize="15sp"}
}
local v = loadlayout(layout)
local dlg = LuaDialog(this).setView(v).setCancelable(true)
local function refresh(list)
local names = {}
for _, img in ipairs(list) do table.insert(names, img.name) end
if #names == 0 then table.insert(names, "No images found") end
imgList.setAdapter(ArrayAdapter(this, android.R.layout.simple_list_item_1, String(names)))
end
refresh(filtered)
imgSearch.addTextChangedListener(luajava.createProxy("android.text.TextWatcher", {
beforeTextChanged=function(s,st,c,a) end,
onTextChanged=function(s,st,b,c)
local q = s.toString():lower()
filtered = {}
for _, img in ipairs(allImgs) do
if img.name:lower():find(q, 1, true) then table.insert(filtered, img) end
end
refresh(filtered)
end,
afterTextChanged=function(s) end
}))
imgList.onItemClick = function(parent, vw, pos, id)
local sel = filtered[pos+1]
if sel then
dlg.dismiss()
Toast.makeText(this, "Selected: " .. sel.name, Toast.LENGTH_SHORT).show()
onSelect(sel.path)
end
end
imgBack.onClick = function() dlg.dismiss() end
dlg.show()
end

function showFolderBrowser(onSelect)
statusText.setVisibility(View.VISIBLE)
statusText.setText("Scanning folders...")
Thread(Runnable{run=function()
local folders = scanFolders()
local allFiles = {}
for _, folder in ipairs(folders) do
local imgs = getFolderImages(folder.path)
for _, img in ipairs(imgs) do
table.insert(allFiles, {name=img.name, path=img.path, folder=folder.name})
end
end
Handler(Looper.getMainLooper()).post(Runnable{run=function()
statusText.setVisibility(View.GONE)
local layout = {
LinearLayout, orientation="vertical", layout_width="fill", layout_height="fill", padding="14dp", backgroundColor="#1A1A2E",
{TextView, text="Select Folder or File", textSize="20sp", textColor="#E94560", gravity="center", layout_marginBottom="10dp"},
{EditText, id="folderSearch", hint="Search folders or files...", layout_width="fill", layout_height="wrap", textSize="14sp", padding="10dp", backgroundColor="#16213E", textColor="#FFFFFF", layout_marginBottom="10dp"},
{ListView, id="folderList", layout_width="fill", layout_height="0dp", layout_weight=1, layout_marginBottom="10dp"},
{Button, id="folderCancel", text="Cancel", layout_width="fill", layout_height="50dp", textColor="#FFFFFF", backgroundColor="#E94560", textSize="15sp"}
}
local v = loadlayout(layout)
local dlg = LuaDialog(this).setView(v).setCancelable(true)
local results = {}
local function refresh(query)
results = {}
if query == "" then
for _, f in ipairs(folders) do
table.insert(results, {type="folder", display=f.name, data=f})
end
else
for _, f in ipairs(folders) do
if f.name:lower():find(query, 1, true) then
table.insert(results, {type="folder", display="[Folder] " .. f.name, data=f})
end
end
for _, img in ipairs(allFiles) do
if img.name:lower():find(query, 1, true) then
table.insert(results, {type="file", display=img.name .. "\n" .. img.folder, data=img})
end
end
end
local names = {}
for _, r in ipairs(results) do table.insert(names, r.display) end
if #names == 0 then table.insert(names, "No results found") end
folderList.setAdapter(ArrayAdapter(this, android.R.layout.simple_list_item_1, String(names)))
end
refresh("")
folderSearch.addTextChangedListener(luajava.createProxy("android.text.TextWatcher", {
beforeTextChanged=function(s,st,c,a) end,
onTextChanged=function(s,st,b,c) refresh(s.toString():lower()) end,
afterTextChanged=function(s) end
}))
folderList.onItemClick = function(parent, vw, pos, id)
local sel = results[pos+1]
if not sel then return end
if sel.type == "folder" then
dlg.dismiss()
showFolderImages(sel.data.path, sel.data.name, onSelect)
else
dlg.dismiss()
Toast.makeText(this, "Selected: " .. sel.data.name, Toast.LENGTH_SHORT).show()
onSelect(sel.data.path)
end
end
folderCancel.onClick = function() dlg.dismiss() end
dlg.show()
end})
end}).start()
end

function showManageImages()
local images = getSavedImages()
local layout = {
LinearLayout, orientation="vertical", layout_width="fill", layout_height="fill", padding="16dp", backgroundColor="#1A1A2E",
{TextView, id="manageTitle", text="Saved Images", textSize="22sp", textColor="#E94560", gravity="center", layout_marginBottom="12dp"},
{ListView, id="manageList", layout_width="fill", layout_height="0dp", layout_weight=1, layout_marginBottom="10dp"},
{Button, id="manageClose", text="Close", layout_width="fill", layout_height="50dp", textColor="#FFFFFF", backgroundColor="#E94560", textSize="15sp"}
}
local v = loadlayout(layout)
manageTitle.setTypeface(Typeface.DEFAULT_BOLD)
local manageDlg = LuaDialog(this).setView(v).setCancelable(true)
local function refresh()
images = getSavedImages()
local names = {}
if #images > 0 then
for _, img in ipairs(images) do
table.insert(names, img.name .. "\n" .. math.floor(img.size/1024) .. " KB")
end
else
table.insert(names, "No saved images found")
end
manageList.setAdapter(ArrayAdapter(this, android.R.layout.simple_list_item_1, String(names)))
end
refresh()
manageList.onItemClick = function(parent, vw, pos, id)
if images[pos+1] then showImageViewer(images[pos+1].path) end
end
manageList.setOnItemLongClickListener(function(parent, vw, pos, id)
if not images[pos+1] then return false end
local img = images[pos+1]
local menuLayout = {
LinearLayout, orientation="vertical", layout_width="fill", layout_height="wrap", padding="16dp", backgroundColor="#1A1A2E",
{Button, id="ctxView", text="View", layout_width="fill", layout_height="50dp", textColor="#FFFFFF", backgroundColor="#0F3460", textSize="15sp", layout_marginBottom="6dp"},
{Button, id="ctxShare", text="Share", layout_width="fill", layout_height="50dp", textColor="#FFFFFF", backgroundColor="#0F3460", textSize="15sp", layout_marginBottom="6dp"},
{Button, id="ctxDelete", text="Delete", layout_width="fill", layout_height="50dp", textColor="#FFFFFF", backgroundColor="#E94560", textSize="15sp", layout_marginBottom="6dp"},
{Button, id="ctxDeleteAll", text="Delete All", layout_width="fill", layout_height="50dp", textColor="#FFFFFF", backgroundColor="#E94560", textSize="15sp", layout_marginBottom="6dp"},
{Button, id="ctxCancel", text="Cancel", layout_width="fill", layout_height="50dp", textColor="#FFFFFF", backgroundColor="#533483", textSize="15sp"}
}
ctxDlg = LuaDialog(this).setView(loadlayout(menuLayout)).setCancelable(true)
ctxView.onClick = function() showImageViewer(img.path) ctxDlg.dismiss() end
ctxShare.onClick = function() service.shareFile(img.path) ctxDlg.dismiss() end
ctxDelete.onClick = function()
LuaDialog(this).setTitle("Delete this image?").setPositiveButton("Yes", function()
if deleteFile(img.path) then Toast.makeText(this,"Deleted",Toast.LENGTH_SHORT).show() refresh() end
end).setNegativeButton("No", function() end).show()
ctxDlg.dismiss()
end
ctxDeleteAll.onClick = function()
LuaDialog(this).setTitle("Delete all images?").setPositiveButton("Yes", function()
local n = deleteAllFiles()
Toast.makeText(this, n .. " files deleted", Toast.LENGTH_SHORT).show()
refresh()
end).setNegativeButton("No", function() end).show()
ctxDlg.dismiss()
end
ctxCancel.onClick = function() ctxDlg.dismiss() end
ctxDlg.show()
return true
end)
manageClose.onClick = function() manageDlg.dismiss() end
manageDlg.show()
end

function showAccountDialog()
local accountLayout = {
LinearLayout, orientation="vertical", layout_width="fill", layout_height="wrap", padding="24dp", backgroundColor="#1A1A2E",
{TextView, text="AI Image Generator & Editor", layout_width="fill", layout_height="wrap", textSize="22sp", textColor="#E94560", gravity="center", layout_marginBottom="6dp"},
{TextView, text="Sign in to continue", layout_width="fill", layout_height="wrap", textSize="14sp", textColor="#AAAAAA", gravity="center", layout_marginBottom="20dp"},
{Button, id="selectGoogleBtn", text="Select Google Account", layout_width="fill", layout_height="55dp", textSize="15sp", backgroundColor="#0F3460", textColor="#FFFFFF", layout_marginBottom="12dp"},
{EditText, id="emailInput", hint="Email", layout_width="fill", layout_height="wrap", textSize="15sp", padding="12dp", layout_marginBottom="10dp", backgroundColor="#16213E", textColor="#FFFFFF", enabled=false},
{EditText, id="passwordInput", hint="Set Password (min 6 chars)", layout_width="fill", layout_height="wrap", textSize="15sp", padding="12dp", layout_marginBottom="10dp", backgroundColor="#16213E", textColor="#FFFFFF", inputType="textPassword"},
{EditText, id="confirmPasswordInput", hint="Confirm Password", layout_width="fill", layout_height="wrap", textSize="15sp", padding="12dp", layout_marginBottom="16dp", backgroundColor="#16213E", textColor="#FFFFFF", inputType="textPassword"},
{Button, id="continueBtn", text="Continue", layout_width="fill", layout_height="55dp", textSize="15sp", backgroundColor="#E94560", textColor="#FFFFFF", layout_marginBottom="8dp"},
{Button, id="accountCloseBtn", text="Close", layout_width="fill", layout_height="50dp", textSize="14sp", backgroundColor="#533483", textColor="#FFFFFF"}
}
accountDlg = LuaDialog(this).setView(loadlayout(accountLayout)).setCancelable(false)
accountCloseBtn.onClick = function() accountDlg.dismiss() end
selectGoogleBtn.onClick = function()
local accounts = getGoogleAccounts()
if #accounts == 0 then service.speak("No Google accounts found") return end
local listLayout = {
LinearLayout, orientation="vertical", layout_width="fill", layout_height="wrap", padding="20dp", backgroundColor="#1A1A2E",
{TextView, text="Select Account", textSize="18sp", textColor="#E94560", gravity="center", layout_marginBottom="12dp"},
{ListView, id="accList", layout_width="fill", layout_height="wrap", layout_marginBottom="10dp"},
{Button, id="accCancel", text="Cancel", layout_width="fill", layout_height="50dp", textSize="14sp", backgroundColor="#E94560", textColor="#FFFFFF"}
}
accSelectDlg = LuaDialog(this).setView(loadlayout(listLayout)).setCancelable(true)
accList.setAdapter(ArrayAdapter(this, android.R.layout.simple_list_item_1, String(accounts)))
accList.onItemClick = function(parent, vw, pos, id)
emailInput.setText(accounts[pos+1])
service.speak("Account selected")
accSelectDlg.dismiss()
end
accCancel.onClick = function() accSelectDlg.dismiss() end
accSelectDlg.show()
end
continueBtn.onClick = function()
local email = emailInput.getText().toString()
local password = passwordInput.getText().toString()
local confirmPassword = confirmPasswordInput.getText().toString()
if email == "" then service.speak("Please select a Google account") return end
if #password < 6 then service.speak("Password must be at least 6 characters") return end
if password ~= confirmPassword then service.speak("Passwords do not match") return end
continueBtn.setEnabled(false)
service.speak("Verifying account, please wait")
local deviceId = getDeviceId()
verifyAccount(email, password, deviceId, function(ok, data)
continueBtn.setEnabled(true)
if ok then
if data.prices then serverPrices = data.prices end
saveCredentials(email, password, deviceId)
service.speak("Account verified successfully")
accountDlg.dismiss()
showMainDialog()
else
service.speak("Verification failed")
Toast.makeText(this, "Failed: " .. tostring(data), Toast.LENGTH_LONG).show()
end
end)
end
accountDlg.show()
end

function showDashboard(creds)
service.speak("Loading dashboard")
verifyAccount(creds.email, creds.password, creds.device_id, function(ok, data)
if not ok then
service.speak("Failed to load dashboard")
Toast.makeText(this, "Failed: " .. tostring(data), Toast.LENGTH_SHORT).show()
return
end
local isPremium = data.expiry_date and data.expiry_date ~= "not subscribed"
if data.prices then serverPrices = data.prices end
local subText = isPremium and ("Active until: " .. data.expiry_date) or "Not subscribed"
local genLeftText = (not isPremium and data.generations_left ~= nil) and ("Generations left today: " .. tostring(math.floor(data.generations_left))) or ""
local totalText = data.total_generations and ("Total generations: " .. tostring(math.floor(data.total_generations))) or ""
local dashLayout = {
LinearLayout, orientation="vertical", layout_width="fill", layout_height="wrap", padding="24dp", backgroundColor="#1A1A2E",
{TextView, text="Dashboard", textSize="24sp", textColor="#E94560", gravity="center", layout_marginBottom="16dp"},
{TextView, text="Email: " .. creds.email, textSize="14sp", textColor="#FFFFFF", layout_marginBottom="8dp"},
{TextView, text="Subscription: " .. subText, textSize="14sp", textColor=isPremium and "#00C853" or "#AAAAAA", layout_marginBottom="8dp"},
{TextView, text=genLeftText, textSize="14sp", textColor="#FFD700", layout_marginBottom="8dp", visibility=genLeftText ~= "" and "visible" or "gone"},
{TextView, text=totalText, textSize="14sp", textColor="#AAAAAA", layout_marginBottom="16dp", visibility=totalText ~= "" and "visible" or "gone"},
{TextView, text="Upgrade to Premium — Get unlimited generations, unlimited edits, and 4 images per request!", textSize="13sp", textColor="#E94560", padding="12dp", backgroundColor="#16213E", layout_marginBottom="8dp", visibility=isPremium and "gone" or "visible"},
{Button, id="upgradeBtn", text="Upgrade to Premium", layout_width="fill", layout_height="55dp", textSize="15sp", backgroundColor="#E94560", textColor="#FFFFFF", layout_marginBottom="8dp", visibility=isPremium and "gone" or "visible"},
{TextView, text="© Shri Shyam Devs", layout_width="fill", layout_height="wrap", textSize="12sp", textColor="#555555", gravity="center", layout_marginBottom="6dp"},
{LinearLayout, orientation="horizontal", layout_width="fill", layout_height="wrap", gravity="center", layout_marginBottom="8dp",
{Button, id="dashEmailBtn", text="Email Us", layout_width="0dp", layout_weight=1, layout_height="44dp", textSize="12sp", backgroundColor="#E94560", textColor="#FFFFFF", layout_marginEnd="6dp"},
{Button, id="dashTelegramBtn", text="Join Shri Shyam Devs", layout_width="0dp", layout_weight=1, layout_height="44dp", textSize="12sp", backgroundColor="#0F3460", textColor="#FFFFFF", layout_marginEnd="6dp"},
{Button, id="dashVisionBtn", text="Join Vision Hacks", layout_width="0dp", layout_weight=1, layout_height="44dp", textSize="12sp", backgroundColor="#0F3460", textColor="#FFFFFF"}
},
{Button, id="logoutBtn", text="Logout", layout_width="fill", layout_height="50dp", textSize="14sp", backgroundColor="#533483", textColor="#FFFFFF", layout_marginBottom="8dp"},
{Button, id="dashCloseBtn", text="Close", layout_width="fill", layout_height="50dp", textSize="14sp", backgroundColor="#E94560", textColor="#FFFFFF"}
}
dashDlg = LuaDialog(this).setView(loadlayout(dashLayout)).setCancelable(true)
upgradeBtn.onClick = function()
local selectedPlan = "1 Month"
local selectedMethod = "Credit Card"
local p1m = tonumber(serverPrices["1_month"]) or 1.99
local p3m = tonumber(serverPrices["3_months"]) or 4.99
local p6m = tonumber(serverPrices["6_months"]) or 7.99
local p1y = tonumber(serverPrices["1_year"]) or 9.33
local function fmt(n) return string.format("USD %.2f", n) end
local function fpm(n) return string.format("USD %.2f/mo", n) end
local s3m = fpm(math.floor((p1m - p3m/3)*100+0.5)/100)
local s6m = fpm(math.floor((p1m - p6m/6)*100+0.5)/100)
local s1y = fpm(math.floor((p1m - p1y/12)*100+0.5)/100)
local prices = {["1 Month"]=fmt(p1m),["3 Months"]=fmt(p3m),["6 Months"]=fmt(p6m),["1 Year"]=fmt(p1y)}
local planLayout = {
LinearLayout, orientation="vertical", layout_width="fill", layout_height="wrap", padding="20dp", backgroundColor="#1A1A2E",
{TextView, text="Upgrade to Premium", textSize="20sp", textColor="#E94560", gravity="center", layout_marginBottom="6dp"},
{TextView, text="Note: Subscription is paid and can be purchased with real money.", textSize="12sp", textColor="#AAAAAA", gravity="center", layout_marginBottom="16dp"},
{TextView, text="Select Plan", textSize="15sp", textColor="#FFFFFF", layout_marginBottom="8dp"},
{RadioGroup, id="planGroup", orientation="vertical", layout_width="fill", layout_height="wrap", layout_marginBottom="14dp",
{RadioButton, id="rb1m", text="1 Month — "..fmt(p1m), textColor="#FFFFFF", textSize="14sp"},
{RadioButton, id="rb3m", text="3 Months — "..fmt(p3m).."  (Save "..s3m..")", textColor="#FFFFFF", textSize="14sp"},
{RadioButton, id="rb6m", text="6 Months — "..fmt(p6m).."  (Save "..s6m..")", textColor="#FFFFFF", textSize="14sp"},
{RadioButton, id="rb1y", text="1 Year — "..fmt(p1y).."  (Save "..s1y..")", textColor="#FFFFFF", textSize="14sp"}
},
{TextView, text="Payment Method", textSize="15sp", textColor="#FFFFFF", layout_marginBottom="8dp"},
{RadioGroup, id="methodGroup", orientation="vertical", layout_width="fill", layout_height="wrap", layout_marginBottom="16dp",
{RadioButton, id="rbCard", text="Credit Card", textColor="#FFFFFF", textSize="14sp"},
{RadioButton, id="rbPaypal", text="PayPal", textColor="#FFFFFF", textSize="14sp"},
{RadioButton, id="rbBinance", text="Binance", textColor="#FFFFFF", textSize="14sp"}
},
{Button, id="proceedBtn", text="Proceed", layout_width="fill", layout_height="52dp", textSize="15sp", backgroundColor="#E94560", textColor="#FFFFFF", layout_marginBottom="6dp"},
{Button, id="upgradeCancelBtn", text="Cancel", layout_width="fill", layout_height="46dp", textSize="14sp", backgroundColor="#533483", textColor="#FFFFFF"}
}
upgradeDlg = LuaDialog(this).setView(loadlayout(planLayout)).setCancelable(true)
rb1m.setChecked(true)
rbCard.setChecked(true)
planGroup.setOnCheckedChangeListener(luajava.createProxy("android.widget.RadioGroup$OnCheckedChangeListener", {
onCheckedChanged = function(group, checkedId)
if checkedId == rb1m.getId() then selectedPlan = "1 Month"
elseif checkedId == rb3m.getId() then selectedPlan = "3 Months"
elseif checkedId == rb6m.getId() then selectedPlan = "6 Months"
elseif checkedId == rb1y.getId() then selectedPlan = "1 Year"
end
end
}))
methodGroup.setOnCheckedChangeListener(luajava.createProxy("android.widget.RadioGroup$OnCheckedChangeListener", {
onCheckedChanged = function(group, checkedId)
if checkedId == rbCard.getId() then selectedMethod = "Credit Card"
elseif checkedId == rbPaypal.getId() then selectedMethod = "PayPal"
elseif checkedId == rbBinance.getId() then selectedMethod = "Binance"
end
end
}))
proceedBtn.onClick = function()
local msg = string.format("please activate AI Image Generator and Editor (Premium) subscription.\nEmail: %s\nPassword: %s\nDevice ID: %s\nPlan: %s\nPayment Method: %s", creds.email, creds.password, creds.device_id, selectedPlan.." ("..prices[selectedPlan]..")", selectedMethod)
local encoded = msg:gsub("\n","%%0A"):gsub(" ","%%20"):gsub(":","%%3A")
upgradeDlg.dismiss()
dashDlg.dismiss()
if mainDlg then mainDlg.dismiss() end
openUrl("https://t.me/jieshuo_help_bot?text="..encoded)
end
upgradeCancelBtn.onClick = function() upgradeDlg.dismiss() end
upgradeDlg.show()
end
dashEmailBtn.onClick = function()
dashDlg.dismiss()
if mainDlg then mainDlg.dismiss() end
openUrl("mailto:support@shrishyamdevs.com")
end
dashTelegramBtn.onClick = function()
dashDlg.dismiss()
if mainDlg then mainDlg.dismiss() end
openUrl("https://t.me/shrishyamdevs")
end
dashVisionBtn.onClick = function()
dashDlg.dismiss()
if mainDlg then mainDlg.dismiss() end
openUrl("https://t.me/VisionHacks_Official")
end
logoutBtn.onClick = function()
LuaDialog(this).setTitle("Logout").setMessage("Are you sure you want to logout?").setPositiveButton("Yes", function()
clearCredentials()
dashDlg.dismiss()
if mainDlg then mainDlg.dismiss() end
service.speak("Logged out successfully")
showAccountDialog()
end).setNegativeButton("No", function() end).show()
end
dashCloseBtn.onClick = function() dashDlg.dismiss() end
dashDlg.show()
end)
end

function showMainDialog()
local creds = getCredentials()
local currentImageUrl = ""
local currentPrompt = ""
local savedFilePath = ""
local isEditMode = false
local uploadedImagePath = ""
local isPremium = false
local generationsLeft = 0

local loadingLayout = {
LinearLayout, orientation="vertical", layout_width="fill", layout_height="wrap", padding="32dp", backgroundColor="#1A1A2E", gravity="center",
{TextView, text="Verifying your identity", textSize="18sp", textColor="#E94560", gravity="center", layout_marginBottom="10dp"},
{TextView, text="Please wait...", textSize="14sp", textColor="#AAAAAA", gravity="center"}
}
loadingDlg = LuaDialog(this).setView(loadlayout(loadingLayout)).setCancelable(false)
loadingDlg.show()

verifyAccount(creds.email, creds.password, creds.device_id, function(ok, data)
if pluginExited then return end
loadingDlg.dismiss()
if ok then
isPremium = data.expiry_date ~= nil and data.expiry_date ~= "not subscribed"
generationsLeft = isPremium and 999 or math.floor(tonumber(data.generations_left) or 0)
if data.prices then serverPrices = data.prices end
if not isPremium and generationsLeft <= 0 then
local limitLayout = {
LinearLayout, orientation="vertical", layout_width="fill", layout_height="wrap", padding="28dp", backgroundColor="#1A1A2E",
{TextView, text="Daily Limit Reached", textSize="20sp", textColor="#E94560", gravity="center", layout_marginBottom="10dp"},
{TextView, text="You have used all your free generations for today. Upgrade to premium for unlimited access.", textSize="14sp", textColor="#AAAAAA", gravity="center", layout_marginBottom="24dp"},
{Button, id="limitUpgradeBtn", text="Upgrade to Premium", layout_width="fill", layout_height="52dp", textSize="15sp", backgroundColor="#E94560", textColor="#FFFFFF", layout_marginBottom="8dp"},
{Button, id="limitCloseBtn", text="Close", layout_width="fill", layout_height="48dp", textSize="14sp", backgroundColor="#533483", textColor="#FFFFFF"}
}
limitDlg = LuaDialog(this).setView(loadlayout(limitLayout)).setCancelable(false)
limitUpgradeBtn.onClick = function()
limitDlg.dismiss()
showDashboard(creds)
end
limitCloseBtn.onClick = function() limitDlg.dismiss() end
limitDlg.show()
return
end
end

local mainLayout = {
LinearLayout, orientation="vertical", layout_width="fill", layout_height="fill", padding="20dp", backgroundColor="#1A1A2E",
{TextView, text="AI Image Generator & Editor", layout_width="fill", layout_height="wrap", textSize="24sp", textColor="#E94560", gravity="center", layout_marginBottom="16dp"},
{Button, id="uploadBtn", text="Upload Image for Editing", layout_width="fill", layout_height="50dp", textSize="14sp", backgroundColor="#0F3460", textColor="#FFFFFF", layout_marginBottom="6dp"},
{TextView, id="selectedLabel", text="", layout_width="fill", layout_height="wrap", textSize="12sp", textColor="#00C853", gravity="center", layout_marginBottom="4dp", visibility="gone"},
{Button, id="viewUploadedBtn", text="View Uploaded Image", layout_width="fill", layout_height="46dp", textSize="13sp", backgroundColor="#16213E", textColor="#00C853", layout_marginBottom="8dp", visibility="gone"},
{EditText, id="promptInput", hint="Describe your image...", layout_width="fill", layout_height="100dp", textSize="15sp", padding="12dp", layout_marginBottom="8dp", backgroundColor="#16213E", textColor="#FFFFFF"},
{LinearLayout, orientation="horizontal", layout_width="fill", layout_height="wrap", layout_marginBottom="6dp",
{Button, id="actionBtn", text="Generate", layout_width="0dp", layout_weight=1, layout_height="55dp", textSize="15sp", backgroundColor="#E94560", textColor="#FFFFFF", layout_marginEnd="6dp"},
{TextView, id="statusText", text="", layout_width="0dp", layout_weight=2, layout_height="55dp", textSize="12sp", padding="8dp", backgroundColor="#16213E", textColor="#FFFFFF", gravity="center", visibility="gone"}
},
{Button, id="improveBtn", text="Enhance Prompt with AI", layout_width="fill", layout_height="50dp", textSize="14sp", backgroundColor="#0F3460", textColor="#FFFFFF", layout_marginBottom="8dp"},
{TextView, id="premiumNudge", text="Upgrade to premium for unlimited generations!", layout_width="fill", layout_height="wrap", textSize="12sp", textColor="#E94560", gravity="center", padding="8dp", backgroundColor="#16213E", layout_marginBottom="8dp", visibility=isPremium and "gone" or "visible"},
{LinearLayout, orientation="horizontal", layout_width="fill", layout_height="wrap", layout_marginBottom="8dp",
{Button, id="viewBtn", text="View Image", layout_width="0dp", layout_weight=1, layout_height="55dp", textSize="15sp", backgroundColor="#0F3460", textColor="#FFFFFF", layout_marginEnd="6dp", visibility="gone"},
{Button, id="editResultBtn", text="Edit this Image", layout_width="0dp", layout_weight=1, layout_height="55dp", textSize="15sp", backgroundColor="#533483", textColor="#FFFFFF", visibility="gone"}
},
{LinearLayout, orientation="horizontal", layout_width="fill", layout_height="wrap", layout_marginBottom="8dp",
{Button, id="saveBtn", text="Save", layout_width="0dp", layout_weight=1, layout_height="55dp", textSize="15sp", backgroundColor="#533483", textColor="#FFFFFF", layout_marginEnd="6dp", visibility="gone"},
{Button, id="shareBtn", text="Share", layout_width="0dp", layout_weight=1, layout_height="55dp", textSize="15sp", backgroundColor="#0F3460", textColor="#FFFFFF", visibility="gone"}
},
{LinearLayout, orientation="horizontal", layout_width="fill", layout_height="wrap", layout_marginBottom="6dp",
{Button, id="dashboardBtn", text="Dashboard", layout_width="0dp", layout_weight=1, layout_height="50dp", textSize="13sp", backgroundColor="#533483", textColor="#FFFFFF", layout_marginEnd="6dp"},
{Button, id="manageBtn", text="Manage Images", layout_width="0dp", layout_weight=1, layout_height="50dp", textSize="13sp", backgroundColor="#0F3460", textColor="#FFFFFF"}
},
{Button, id="closeBtn", text="Close", layout_width="fill", layout_height="50dp", textSize="13sp", backgroundColor="#E94560", textColor="#FFFFFF"}
}
mainDlg = LuaDialog(this).setView(loadlayout(mainLayout)).setCancelable(true)

local function hideResultButtons()
viewBtn.setVisibility(View.GONE)
editResultBtn.setVisibility(View.GONE)
saveBtn.setVisibility(View.GONE)
shareBtn.setVisibility(View.GONE)
end

local function showFreeResultButtons()
viewBtn.setVisibility(View.VISIBLE)
editResultBtn.setVisibility(View.VISIBLE)
saveBtn.setVisibility(View.VISIBLE)
end

local function setBusy(busy)
actionBtn.setEnabled(not busy)
improveBtn.setEnabled(not busy)
uploadBtn.setEnabled(not busy)
if busy then
statusText.setVisibility(View.VISIBLE)
hideResultButtons()
end
end

local function setEditMode(path, name)
isEditMode = true
uploadedImagePath = path
uploadBtn.setText("Change Image")
selectedLabel.setText("Editing: " .. name)
selectedLabel.setVisibility(View.VISIBLE)
viewUploadedBtn.setVisibility(View.VISIBLE)
promptInput.setHint("Describe edits to apply...")
promptInput.setText("")
actionBtn.setText("Edit Image")
actionBtn.setBackgroundColor(0xFF533483)
hideResultButtons()
statusText.setVisibility(View.GONE)
end

local function onResult(ok, result, elapsed)
setBusy(false)
local timeStr = " • " .. elapsed .. "s"
if ok then
local urls = result.image_urls
local imageUrls = (type(urls) == "table" and #urls > 0) and urls or {}
isPremium = result.is_premium == true
generationsLeft = isPremium and 999 or math.floor(tonumber(result.generations_left) or 0)
premiumNudge.setVisibility(isPremium and View.GONE or View.VISIBLE)
if isPremium then
statusText.setText("Done • Premium • " .. #imageUrls .. " images" .. timeStr)
service.speak("Images ready")
showResultsDialog(imageUrls, currentPrompt)
else
currentImageUrl = (type(imageUrls[1]) == "string") and imageUrls[1] or ""
savedFilePath = ""
statusText.setText("Done • " .. generationsLeft .. " left today" .. timeStr)
service.speak("Image ready")
showFreeResultButtons()
end
else
statusText.setText("Error: " .. tostring(result))
premiumNudge.setVisibility(View.VISIBLE)
service.speak("Failed")
end
end

uploadBtn.onClick = function()
showFolderBrowser(function(path)
setEditMode(path, tostring(File(path).getName()))
end)
end

viewUploadedBtn.onClick = function()
if uploadedImagePath ~= "" then showImageViewer(uploadedImagePath) end
end

actionBtn.onClick = function()
local prompt = tostring(promptInput.getText().toString())
if not prompt or #prompt == 0 then
Toast.makeText(this, "Please enter a prompt", Toast.LENGTH_SHORT).show()
return
end
if not isPremium and generationsLeft <= 0 then
Toast.makeText(this, "Daily limit reached. Upgrade to premium!", Toast.LENGTH_LONG).show()
return
end
currentPrompt = sanitizePrompt(prompt)
currentImageUrl = ""
savedFilePath = ""
setBusy(true)
premiumNudge.setVisibility(View.GONE)
local startTime = os.time()
if isEditMode then
statusText.setText("Uploading and editing, please wait...")
service.speak("Editing image, please wait")
editImage(currentPrompt, uploadedImagePath, creds, function(ok, result)
onResult(ok, result, os.time() - startTime)
end)
else
statusText.setText("Generating image, please wait...")
service.speak("Generating image, please wait")
generateImage(currentPrompt, creds, function(ok, result)
onResult(ok, result, os.time() - startTime)
end)
end
end

improveBtn.onClick = function()
local prompt = tostring(promptInput.getText().toString())
if not prompt or #prompt == 0 then
Toast.makeText(this, "Enter a prompt first", Toast.LENGTH_SHORT).show()
return
end
setBusy(true)
statusText.setVisibility(View.VISIBLE)
statusText.setText("Enhancing prompt...")
service.speak("Enhancing prompt with AI")
enhancePrompt(prompt, isEditMode, function(ok, result)
setBusy(false)
if ok then
promptInput.setText(result)
promptInput.setSelection(result:len())
statusText.setText("Prompt enhanced!")
service.speak("Prompt enhanced")
else
statusText.setText("Error: " .. result)
end
end)
end

viewBtn.onClick = function()
if currentImageUrl ~= "" then showImageViewer(currentImageUrl) end
end

editResultBtn.onClick = function()
if currentImageUrl ~= "" then setEditMode(currentImageUrl, "generated image") end
end

saveBtn.onClick = function()
if currentImageUrl == "" then return end
local defName = cleanFilename(currentPrompt)
local saveLayout = {
LinearLayout, orientation="vertical", layout_width="fill", layout_height="wrap", padding="20dp", backgroundColor="#1A1A2E",
{TextView, text="Save Image As", textSize="18sp", textColor="#E94560", gravity="center", layout_marginBottom="12dp"},
{EditText, id="freeSaveInput", text=defName, layout_width="fill", layout_height="wrap", textSize="14sp", padding="10dp", backgroundColor="#16213E", textColor="#FFFFFF", layout_marginBottom="12dp"},
{LinearLayout, orientation="horizontal", layout_width="fill", layout_height="wrap",
{Button, id="freeDoSave", text="Save", layout_width="0dp", layout_weight=1, layout_height="48dp", textSize="14sp", backgroundColor="#E94560", textColor="#FFFFFF", layout_marginEnd="6dp"},
{Button, id="freeCancelSave", text="Cancel", layout_width="0dp", layout_weight=1, layout_height="48dp", textSize="14sp", backgroundColor="#533483", textColor="#FFFFFF"}
}
}
freeSaveDlg = LuaDialog(this).setView(loadlayout(saveLayout)).setCancelable(true)
freeDoSave.onClick = function()
local fname = freeSaveInput.getText().toString():gsub("[^%w%s%-_]",""):gsub("%s+","_")
if fname == "" then fname = "image" end
freeSaveDlg.dismiss()
local dir = createSaveDir()
if not dir then statusText.setText("Failed to create directory") return end
local f = File(dir, fname .. ".png")
statusText.setVisibility(View.VISIBLE)
statusText.setText("Saving...")
Http.get(currentImageUrl, nil, function(code, data)
if code ~= 200 then statusText.setText("Failed to download image") return end
local ok = writeToFile(tostring(f.getPath()), data)
if ok then
savedFilePath = tostring(f.getPath())
local intent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
intent.setData(Uri.fromFile(f))
this.sendBroadcast(intent)
statusText.setText("Saved!")
shareBtn.setVisibility(View.VISIBLE)
service.speak("Image saved")
else
statusText.setText("Failed to save")
end
end)
end
freeCancelSave.onClick = function() freeSaveDlg.dismiss() end
freeSaveDlg.show()
end

shareBtn.onClick = function()
if savedFilePath ~= "" then
service.shareFile(savedFilePath)
mainDlg.dismiss()
else
Toast.makeText(this, "Save the image first", Toast.LENGTH_SHORT).show()
end
end

dashboardBtn.onClick = function() showDashboard(creds) end
manageBtn.onClick = function() showManageImages() end
closeBtn.onClick = function() mainDlg.dismiss() end
mainDlg.show()
end)
end

local creds = getCredentials()
if creds.email == "" or creds.password == "" or creds.device_id == "" then
showAccountDialog()
else
showMainDialog()
end