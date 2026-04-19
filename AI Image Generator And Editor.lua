local BASE = "https://premium-image.shrishyamcoders.workers.dev"
local CHAT_API = "https://ai-chat.shrishyamdevs.com/v1/chat/completions"
local IMGBB_KEY = "6c3c19148180756ca75df22b4d81f5ba"
local BRAND_DIR = "Shri Shyam Devs"
local SAVE_DIR = "AI Image Generator and Editor"
local IMAGE_EXTS = {jpg=true,jpeg=true,png=true,webp=true,bmp=true,gif=true}

function urlEncode(str)
if not str then return "" end
return str:gsub("([^%w%-%.%_%~ ])", function(c)
return string.format("%%%02X", string.byte(c))
end):gsub(" ", "%%20")
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

function saveTempImage(content)
local dir = this.getExternalFilesDir(nil)
if not dir then return nil end
local path = tostring(dir.getAbsolutePath()) .. "/temp_image.png"
local ok = writeToFile(path, content)
return ok and path or nil
end

function isPNG(data)
return data and #data > 4 and data:sub(1, 4) == "\137PNG"
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
error("imgbb HTTP " .. code .. ": " .. errText)
end
local _, respText = readStream(conn.getInputStream())
local parsed = require("cjson").decode(respText)
if not parsed or not parsed.data or not parsed.data.url then
error("Invalid imgbb response: " .. respText)
end
return parsed.data.url
end

function uploadToImgbb(imagePath, callback)
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
end

function generateImage(prompt, callback)
Http.get(BASE .. "/api/generate?prompt=" .. urlEncode(prompt), nil, function(code, content)
if code == 200 and isPNG(content) then
local tempPath = saveTempImage(content)
if not tempPath then callback(false, "Failed to save temp image") return end
uploadToImgbb(tempPath, callback)
else
callback(false, "HTTP " .. tostring(code) .. ": " .. tostring(content))
end
end)
end

function editImage(prompt, imagePath, callback)
local function doEdit(imageUrl)
Thread(Runnable{run=function()
local ok, result = pcall(function()
local body = require("cjson").encode({prompt=prompt, url=imageUrl})
local editConn = URL(BASE .. "/api/edit").openConnection()
editConn.setRequestMethod("POST")
editConn.setDoOutput(true)
editConn.setConnectTimeout(30000)
editConn.setReadTimeout(120000)
editConn.setRequestProperty("Content-Type", "application/json")
local dos = DataOutputStream(editConn.getOutputStream())
dos.writeBytes(body)
dos.flush()
dos.close()
local editCode = editConn.getResponseCode()
if editCode ~= 200 then
local _, errText = readStream(editConn.getErrorStream())
error("HTTP " .. editCode .. ": " .. errText)
end
local respBytes, _ = readStream(editConn.getInputStream())
return uploadBytesToImgbb(respBytes)
end)
Handler(Looper.getMainLooper()).post(Runnable{run=function()
if ok then callback(true, result) else callback(false, tostring(result)) end
end})
end}).start()
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

function enhancePrompt(prompt, callback)
local body = require("cjson").encode({
model = "llama-3.3-70b-versatile",
temperature = 0.7,
max_tokens = 512,
messages = {
{role="system", content="You improve AI image generation prompts. Reply with only the improved prompt text, no explanations, no quotes, no extra text."},
{role="user", content="Improve this prompt for image generation: " .. prompt}
}
})
Http.post(CHAT_API, body, {["Content-Type"]="application/json"}, function(code, content)
if code == 200 then
local ok, data = pcall(function() return require("cjson").decode(content) end)
if ok and data then
local msg = data.message
if type(msg) == "table" then msg = msg.content end
if type(msg) == "string" and msg ~= "" then
callback(true, msg:gsub("^%s*(.-)%s*$", "%1"))
return
end
end
callback(false, "Invalid response: " .. tostring(content))
else
callback(false, "HTTP " .. tostring(code) .. ": " .. tostring(content))
end
end)
end

function openUrl(url)
this.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
end

function showImageViewer(imageSource)
local function displayBitmap(bmp)
if not bmp then Toast.makeText(this, "Failed to load image", Toast.LENGTH_SHORT).show() return end
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
end
if imageSource:match("^https?://") then
Thread(Runnable{run=function()
local ok, bmp = pcall(function()
local conn = URL(imageSource).openConnection()
conn.setConnectTimeout(15000)
conn.setReadTimeout(30000)
return BitmapFactory.decodeStream(conn.getInputStream())
end)
Handler(Looper.getMainLooper()).post(Runnable{run=function()
displayBitmap(ok and bmp or nil)
end})
end}).start()
else
displayBitmap(BitmapFactory.decodeFile(imageSource))
end
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
onTextChanged=function(s,st,b,c)
refresh(s.toString():lower())
end,
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
{Button, text="View", layout_width="fill", layout_height="50dp", textColor="#FFFFFF", backgroundColor="#0F3460", textSize="15sp", layout_marginBottom="6dp", onClick=function() showImageViewer(img.path) ctxDlg.dismiss() end},
{Button, text="Share", layout_width="fill", layout_height="50dp", textColor="#FFFFFF", backgroundColor="#0F3460", textSize="15sp", layout_marginBottom="6dp", onClick=function() service.shareFile(img.path) ctxDlg.dismiss() end},
{Button, text="Delete", layout_width="fill", layout_height="50dp", textColor="#FFFFFF", backgroundColor="#E94560", textSize="15sp", layout_marginBottom="6dp", onClick=function()
LuaDialog(this).setTitle("Delete this image?").setPositiveButton("Yes", function()
if deleteFile(img.path) then Toast.makeText(this,"Deleted",Toast.LENGTH_SHORT).show() refresh() end
end).setNegativeButton("No", function() end).show()
ctxDlg.dismiss()
end},
{Button, text="Delete All", layout_width="fill", layout_height="50dp", textColor="#FFFFFF", backgroundColor="#E94560", textSize="15sp", layout_marginBottom="6dp", onClick=function()
LuaDialog(this).setTitle("Delete all images?").setPositiveButton("Yes", function()
local n = deleteAllFiles()
Toast.makeText(this, n .. " files deleted", Toast.LENGTH_SHORT).show()
refresh()
end).setNegativeButton("No", function() end).show()
ctxDlg.dismiss()
end},
{Button, text="Cancel", layout_width="fill", layout_height="50dp", textColor="#FFFFFF", backgroundColor="#533483", textSize="15sp", onClick=function() ctxDlg.dismiss() end}
}
ctxDlg = LuaDialog(this).setView(loadlayout(menuLayout)).setCancelable(true)
ctxDlg.show()
return true
end)
manageClose.onClick = function() manageDlg.dismiss() end
manageDlg.show()
end

function showMainDialog()
local currentImageUrl = ""
local currentPrompt = ""
local savedFilePath = ""
local isEditMode = false
local uploadedImagePath = ""

local mainLayout = {
LinearLayout, orientation="vertical", layout_width="fill", layout_height="fill", padding="20dp", backgroundColor="#1A1A2E",
{TextView, text="AI Image Generator", layout_width="fill", layout_height="wrap", textSize="26sp", textColor="#E94560", gravity="center", layout_marginBottom="16dp"},
{Button, id="uploadBtn", text="Upload Image for Editing", layout_width="fill", layout_height="50dp", textSize="14sp", backgroundColor="#0F3460", textColor="#FFFFFF", layout_marginBottom="6dp"},
{TextView, id="selectedLabel", text="", layout_width="fill", layout_height="wrap", textSize="12sp", textColor="#00C853", gravity="center", layout_marginBottom="4dp", visibility="gone"},
{Button, id="viewUploadedBtn", text="View Uploaded Image", layout_width="fill", layout_height="46dp", textSize="13sp", backgroundColor="#16213E", textColor="#00C853", layout_marginBottom="8dp", visibility="gone"},
{EditText, id="promptInput", hint="Describe your image...", layout_width="fill", layout_height="100dp", textSize="15sp", padding="12dp", layout_marginBottom="8dp", backgroundColor="#16213E", textColor="#FFFFFF"},
{
LinearLayout, orientation="horizontal", layout_width="fill", layout_height="wrap", layout_marginBottom="6dp",
{Button, id="actionBtn", text="Generate", layout_width="0dp", layout_weight=1, layout_height="55dp", textSize="15sp", backgroundColor="#E94560", textColor="#FFFFFF", layout_marginEnd="6dp"},
{TextView, id="statusText", text="", layout_width="0dp", layout_weight=2, layout_height="55dp", textSize="12sp", padding="8dp", backgroundColor="#16213E", textColor="#FFFFFF", gravity="center", visibility="gone"}
},
{Button, id="improveBtn", text="Enhance Prompt with AI", layout_width="fill", layout_height="50dp", textSize="14sp", backgroundColor="#0F3460", textColor="#FFFFFF", layout_marginBottom="8dp"},
{
LinearLayout, orientation="horizontal", layout_width="fill", layout_height="wrap", layout_marginBottom="8dp",
{Button, id="viewBtn", text="View", layout_width="0dp", layout_weight=1, layout_height="55dp", textSize="15sp", backgroundColor="#0F3460", textColor="#FFFFFF", layout_marginEnd="6dp", visibility="gone"},
{Button, id="editResultBtn", text="Edit this Image", layout_width="0dp", layout_weight=1, layout_height="55dp", textSize="15sp", backgroundColor="#533483", textColor="#FFFFFF", visibility="gone"}
},
{
LinearLayout, orientation="horizontal", layout_width="fill", layout_height="wrap", layout_marginBottom="8dp",
{Button, id="saveBtn", text="Save", layout_width="0dp", layout_weight=1, layout_height="55dp", textSize="15sp", backgroundColor="#533483", textColor="#FFFFFF", layout_marginEnd="6dp", visibility="gone"},
{Button, id="shareBtn", text="Share", layout_width="0dp", layout_weight=1, layout_height="55dp", textSize="15sp", backgroundColor="#0F3460", textColor="#FFFFFF", visibility="gone"}
},
{Button, id="manageBtn", text="Manage Images", layout_width="fill", layout_height="50dp", textSize="13sp", backgroundColor="#533483", textColor="#FFFFFF", layout_marginBottom="6dp"},
{Button, id="closeBtn", text="Close", layout_width="fill", layout_height="50dp", textSize="13sp", backgroundColor="#E94560", textColor="#FFFFFF", layout_marginBottom="10dp"},
{TextView, text="© Shri Shyam Devs", layout_width="fill", layout_height="wrap", textSize="12sp", textColor="#555555", gravity="center", layout_marginBottom="6dp"},
{
LinearLayout, orientation="horizontal", layout_width="fill", layout_height="wrap", gravity="center", layout_marginBottom="6dp",
{Button, id="emailBtn", text="Email Us", layout_width="0dp", layout_weight=1, layout_height="44dp", textSize="12sp", backgroundColor="#E94560", textColor="#FFFFFF", layout_marginEnd="6dp"},
{Button, id="telegramBtn", text="Join Shri Shyam Devs", layout_width="0dp", layout_weight=1, layout_height="44dp", textSize="12sp", backgroundColor="#0F3460", textColor="#FFFFFF"}
},
{Button, id="friendBtn", text="Join Plugins impacientes", layout_width="fill", layout_height="44dp", textSize="12sp", backgroundColor="#533483", textColor="#FFFFFF"}
}

local mainView = loadlayout(mainLayout)
local mainDlg = LuaDialog(this).setView(mainView).setCancelable(true)

local function setBusy(busy)
actionBtn.setEnabled(not busy)
improveBtn.setEnabled(not busy)
uploadBtn.setEnabled(not busy)
if busy then statusText.setVisibility(View.VISIBLE) end
end

local function hideResultButtons()
viewBtn.setVisibility(View.GONE)
editResultBtn.setVisibility(View.GONE)
saveBtn.setVisibility(View.GONE)
shareBtn.setVisibility(View.GONE)
end

local function showResultButtons()
viewBtn.setVisibility(View.VISIBLE)
editResultBtn.setVisibility(View.VISIBLE)
saveBtn.setVisibility(View.VISIBLE)
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

local function setGenerateMode()
isEditMode = false
uploadedImagePath = ""
uploadBtn.setText("Upload Image for Editing")
selectedLabel.setVisibility(View.GONE)
viewUploadedBtn.setVisibility(View.GONE)
promptInput.setHint("Describe your image...")
promptInput.setText("")
actionBtn.setText("Generate")
actionBtn.setBackgroundColor(0xFFE94560)
hideResultButtons()
statusText.setVisibility(View.GONE)
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
local prompt = promptInput.getText().toString()
if not prompt or #prompt == 0 then
Toast.makeText(this, "Please enter a prompt", Toast.LENGTH_SHORT).show()
return
end
currentPrompt = prompt
currentImageUrl = ""
savedFilePath = ""
hideResultButtons()
setBusy(true)
if isEditMode then
statusText.setText("Uploading and editing, please wait...")
service.speak("Editing image, please wait")
editImage(prompt, uploadedImagePath, function(ok, result)
setBusy(false)
if ok then
currentImageUrl = result
statusText.setText("Image edited!")
showResultButtons()
service.speak("Image edited successfully")
else
statusText.setText("Error: " .. result)
service.speak("Edit failed")
end
end)
else
statusText.setText("Generating image, please wait...")
service.speak("Generating image, please wait")
generateImage(prompt, function(ok, result)
setBusy(false)
if ok then
currentImageUrl = result
statusText.setText("Image ready!")
showResultButtons()
service.speak("Image generated successfully")
else
statusText.setText("Error: " .. result)
service.speak("Generation failed")
end
end)
end
end

improveBtn.onClick = function()
local prompt = promptInput.getText().toString()
if not prompt or #prompt == 0 then
Toast.makeText(this, "Enter a prompt first", Toast.LENGTH_SHORT).show()
return
end
setBusy(true)
statusText.setVisibility(View.VISIBLE)
statusText.setText("Enhancing prompt...")
service.speak("Enhancing prompt with AI")
enhancePrompt(prompt, function(ok, result)
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
if currentImageUrl ~= "" then
setEditMode(currentImageUrl, "generated image")
end
end

saveBtn.onClick = function()
if currentImageUrl == "" then return end
local defName = cleanFilename(currentPrompt)
local saveDlgLayout = {
LinearLayout, orientation="vertical", layout_width="fill", layout_height="wrap", padding="20dp", backgroundColor="#1A1A2E",
{TextView, text="Save Image As", textSize="18sp", textColor="#E94560", gravity="center", layout_marginBottom="12dp"},
{EditText, id="fileNameInput", text=defName, hint="File name", layout_width="fill", layout_height="wrap", textSize="15sp", padding="10dp", backgroundColor="#16213E", textColor="#FFFFFF", layout_marginBottom="12dp"},
{
LinearLayout, orientation="horizontal", layout_width="fill", layout_height="wrap",
{Button, text="Save", layout_width="0dp", layout_weight=1, layout_height="50dp", textSize="15sp", backgroundColor="#E94560", textColor="#FFFFFF", layout_marginEnd="6dp", onClick=function()
local fname = fileNameInput.getText().toString():gsub("[^%w%s%-_]",""):gsub("%s+","_")
if fname == "" then fname = "image" end
saveDlg.dismiss()
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
end},
{Button, text="Cancel", layout_width="0dp", layout_weight=1, layout_height="50dp", textSize="15sp", backgroundColor="#533483", textColor="#FFFFFF", onClick=function() saveDlg.dismiss() end}
}
}
saveDlg = LuaDialog(this).setView(loadlayout(saveDlgLayout)).setCancelable(true)
saveDlg.show()
end

shareBtn.onClick = function()
if savedFilePath ~= "" then
service.shareFile(savedFilePath)
mainDlg.dismiss()
else
Toast.makeText(this, "Save the image first", Toast.LENGTH_SHORT).show()
end
end

manageBtn.onClick = function() showManageImages() end
closeBtn.onClick = function() mainDlg.dismiss() end
emailBtn.onClick = function() openUrl("mailto:support@shrishyamdevs.com") end
telegramBtn.onClick = function() openUrl("https://t.me/shrishyamdevs") end
friendBtn.onClick = function() openUrl("https://t.me/Pluginimpaciente") end
mainDlg.show()
end

showMainDialog()