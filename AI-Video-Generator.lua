local API_URL = "https://ai-video.shrishyamdevs.com/generate?prompt="
local CHAT_API_URL = "https://ai-chat.shrishyamdevs.com/v1/chat/completions"
local MAX_PROMPT_LENGTH = 300
local BRAND_DIR = "Shri Shyam Devs"
local SAVE_DIR = "AI Video Generator"

function createVideoDirectory()
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

function writeToFile(path, content)
return pcall(function()
local f = io.open(path, "wb")
if f then f:write(content) f:close() end
end)
end

function cleanFilename(text)
if not text or text == "" then return "video" end
local s = text:gsub("^%s*(.-)%s*$", "%1"):sub(1, 50)
s = s:gsub("[^%w%s%-_]", ""):gsub("%s+", "_")
return s ~= "" and s or "video"
end

function urlEncode(str)
if not str then return "" end
return str:gsub("([^%w%-%.%_%~ ])", function(c)
return string.format("%%%02X", string.byte(c))
end):gsub(" ", "%%20")
end

function getSavedVideoFiles()
local dir = createVideoDirectory()
local files = {}
if dir and dir.exists() and dir.isDirectory() then
local fl = dir.listFiles()
if fl then
local i = 0
while true do
local ok, f = pcall(function() return fl[i] end)
if not ok or not f then break end
if f.isFile() then
local ext = f.getName():match("%.(%w+)$")
if ext then
ext = ext:lower()
if ext == "mp4" or ext == "mkv" or ext == "webm" or ext == "avi" or ext == "mov" then
table.insert(files, {name = f.getName():gsub("%.%w+$", ""), path = f.getPath(), size = f.length()})
end
end
end
i = i + 1
end
end
end
return files
end

function deleteVideoFile(path)
local f = File(path)
return f.exists() and f.delete()
end

function deleteAllVideoFiles()
local n = 0
for _, vf in ipairs(getSavedVideoFiles()) do
if deleteVideoFile(vf.path) then n = n + 1 end
end
return n
end

function downloadVideo(url, filename, callback)
if isVpnActive() then callback(false, "VPN detected. Please disconnect VPN.") return end
if not url or url == "" then callback(false, "Invalid URL") return end
Thread(Runnable{run = function()
local dir = createVideoDirectory()
if not dir then callback(false, "Failed to create directory") return end
Http.get(tostring(url), nil, function(code, content)
if code == 200 then
local file = File(dir, tostring(filename or "video.mp4"))
local path = file.getPath()
local ok = writeToFile(path, content)
if ok then
local intent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE)
intent.setData(Uri.fromFile(file))
service.sendBroadcast(intent)
callback(true, path)
else
callback(false, "Failed to write file")
end
else
callback(false, "Download failed: " .. code)
end
end)
end}).start()
end

function generateVideo(prompt, callback)
if isVpnActive() then callback(false, "VPN detected. Please disconnect VPN.") return end
local enc = urlEncode(prompt)
Http.get(API_URL .. enc, nil, function(code, content)
if code == 200 then
local ok, data = pcall(function() return require("cjson").decode(content) end)
if ok and data.url then
callback(true, data.url)
else
callback(false, "Invalid response from server")
end
else
callback(false, "API Error: " .. code)
end
end)
end

function improvePrompt(prompt, callback)
if isVpnActive() then callback(false, "VPN detected. Please disconnect VPN.") return end
local cjson = require("cjson")
local body = cjson.encode({
model = "llama-3.3-70b-versatile",
temperature = 0.7,
max_tokens = 512,
messages = {
{role = "system", content = "You improve AI video generation prompts. Reply with only the improved prompt text, no explanations, no quotes, no extra text."},
{role = "user", content = "Improve this prompt for video generation: " .. prompt}
}
})
local headers = {["Content-Type"] = "application/json"}
Http.post(CHAT_API_URL, headers, body, function(code, content)
if code == 200 then
local ok, data = pcall(function() return cjson.decode(content) end)
if ok and data.success and data.message and #data.message > 0 then
local improved = data.message:gsub("^%s*(.-)%s*$", "%1")
if #improved > MAX_PROMPT_LENGTH then improved = improved:sub(1, MAX_PROMPT_LENGTH) end
callback(true, improved)
else
callback(false, "Invalid response from API")
end
else
callback(false, "Chat API Error: " .. code)
end
end)
end

function openUrl(dlg, url)
dlg.dismiss()
local intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
this.startActivity(intent)
end

function showVideoPlayerDialog(videoUrl)
local playerLayout = {
LinearLayout,
orientation = "vertical",
layout_width = "fill",
layout_height = "fill",
backgroundColor = "#000000",
{VideoView, id = "playerVideoView", layout_width = "fill", layout_height = "0dp", layout_weight = 1},
{
LinearLayout,
orientation = "horizontal",
layout_width = "fill",
layout_height = "wrap",
backgroundColor = "#1A1A2E",
padding = "10dp",
gravity = "center",
{Button, id = "rewindBtn", text = "Rewind 1s", layout_width = "0dp", layout_weight = 1, layout_height = "52dp", textColor = "#FFFFFF", backgroundColor = "#0F3460", textSize = "13sp", layout_marginEnd = "4dp"},
{Button, id = "playPauseBtn", text = "Pause", layout_width = "0dp", layout_weight = 1, layout_height = "52dp", textColor = "#FFFFFF", backgroundColor = "#533483", textSize = "14sp", layout_marginEnd = "4dp"},
{Button, id = "forwardBtn", text = "Forward 1s", layout_width = "0dp", layout_weight = 1, layout_height = "52dp", textColor = "#FFFFFF", backgroundColor = "#0F3460", textSize = "13sp", layout_marginEnd = "4dp"},
{Button, id = "exitPlayerBtn", text = "Exit", layout_width = "0dp", layout_weight = 1, layout_height = "52dp", textColor = "#FFFFFF", backgroundColor = "#E94560", textSize = "13sp"}
}
}
local playerView = loadlayout(playerLayout)
local playerDlg = LuaDialog(this).setView(playerView).setCancelable(false)
local function closePlayer()
pcall(function() playerVideoView.stopPlayback() end)
playerDlg.dismiss()
end
playerVideoView.setVideoURI(Uri.parse(tostring(videoUrl)))
playerVideoView.setOnPreparedListener(function(mp)
mp.setLooping(false)
playerVideoView.start()
playPauseBtn.setText("Pause")
end)
playerVideoView.setOnErrorListener(function(mp, what, extra)
Toast.makeText(this, "Error playing video", Toast.LENGTH_SHORT).show()
closePlayer()
return true
end)
playerVideoView.setOnCompletionListener(function(mp)
playPauseBtn.setText("Play")
end)
playPauseBtn.onClick = function()
if playerVideoView.isPlaying() then
playerVideoView.pause()
playPauseBtn.setText("Play")
else
playerVideoView.start()
playPauseBtn.setText("Pause")
end
end
rewindBtn.onClick = function()
playerVideoView.seekTo(math.max(0, playerVideoView.getCurrentPosition() - 1000))
end
forwardBtn.onClick = function()
local dur = playerVideoView.getDuration()
if dur > 0 then playerVideoView.seekTo(math.min(dur, playerVideoView.getCurrentPosition() + 1000)) end
end
exitPlayerBtn.onClick = function() closePlayer() end
playerDlg.setOnKeyListener(function(dialog, keyCode, event)
if keyCode == 4 then closePlayer() return true end
return false
end)
playerDlg.setOnDismissListener(function()
pcall(function() playerVideoView.stopPlayback() end)
end)
playerDlg.show()
end

function showManageVideosDialog()
local videoFiles = getSavedVideoFiles()
local manageLayout = {
LinearLayout,
orientation = "vertical",
layout_width = "fill",
layout_height = "fill",
padding = "16dp",
backgroundColor = "#1A1A2E",
{TextView, id = "manageTitle", text = "Saved Videos", textSize = "22sp", textColor = "#E94560", gravity = "center", layout_marginBottom = "12dp"},
{ListView, id = "videoList", layout_width = "fill", layout_height = "0dp", layout_weight = 1, layout_marginBottom = "10dp"},
{Button, id = "closeManageBtn", text = "Close", layout_width = "fill", layout_height = "50dp", textColor = "#FFFFFF", backgroundColor = "#E94560", textSize = "15sp"}
}
local manageView = loadlayout(manageLayout)
manageTitle.setTypeface(Typeface.DEFAULT_BOLD)
local manageDlg = LuaDialog(this).setView(manageView).setCancelable(true)
local function refresh()
videoFiles = getSavedVideoFiles()
local names = {}
if #videoFiles > 0 then
for _, vf in ipairs(videoFiles) do
table.insert(names, vf.name .. "\n" .. math.floor(vf.size / 1024) .. " KB")
end
else
table.insert(names, "No saved videos found")
end
videoList.setAdapter(ArrayAdapter(this, android.R.layout.simple_list_item_1, String(names)))
end
refresh()
videoList.onItemClick = function(parent, v, pos, id)
if videoFiles[pos + 1] then showVideoPlayerDialog(videoFiles[pos + 1].path) end
end
videoList.setOnItemLongClickListener(function(parent, v, pos, id)
if not videoFiles[pos + 1] then return false end
local vf = videoFiles[pos + 1]
local menuLayout = {
LinearLayout,
orientation = "vertical",
layout_width = "fill",
layout_height = "wrap",
padding = "16dp",
backgroundColor = "#1A1A2E",
{Button, text = "Play", layout_width = "fill", layout_height = "50dp", textColor = "#FFFFFF", backgroundColor = "#0F3460", textSize = "15sp", layout_marginBottom = "6dp", onClick = function() showVideoPlayerDialog(vf.path) ctxDlg.dismiss() end},
{Button, text = "Share", layout_width = "fill", layout_height = "50dp", textColor = "#FFFFFF", backgroundColor = "#0F3460", textSize = "15sp", layout_marginBottom = "6dp", onClick = function() service.shareFile(vf.path) ctxDlg.dismiss() end},
{Button, text = "Delete", layout_width = "fill", layout_height = "50dp", textColor = "#FFFFFF", backgroundColor = "#E94560", textSize = "15sp", layout_marginBottom = "6dp", onClick = function()
LuaDialog(this).setTitle("Delete this video?").setPositiveButton("Yes", function()
if deleteVideoFile(vf.path) then Toast.makeText(this, "Deleted", Toast.LENGTH_SHORT).show() refresh() else Toast.makeText(this, "Failed to delete", Toast.LENGTH_SHORT).show() end
end).setNegativeButton("No", function() end).show()
ctxDlg.dismiss()
end},
{Button, text = "Delete All", layout_width = "fill", layout_height = "50dp", textColor = "#FFFFFF", backgroundColor = "#E94560", textSize = "15sp", layout_marginBottom = "6dp", onClick = function()
LuaDialog(this).setTitle("Delete all videos?").setPositiveButton("Yes", function()
local n = deleteAllVideoFiles()
Toast.makeText(this, n .. " files deleted", Toast.LENGTH_SHORT).show()
refresh()
end).setNegativeButton("No", function() end).show()
ctxDlg.dismiss()
end},
{Button, text = "Cancel", layout_width = "fill", layout_height = "50dp", textColor = "#FFFFFF", backgroundColor = "#533483", textSize = "15sp", onClick = function() ctxDlg.dismiss() end}
}
ctxDlg = LuaDialog(this).setView(loadlayout(menuLayout)).setCancelable(true)
ctxDlg.show()
return true
end)
closeManageBtn.onClick = function() manageDlg.dismiss() end
manageDlg.show()
end

function showMainDialog()
local currentVideoUrl = ""
local currentPrompt = ""
local downloadedFilePath = ""
local mainLayout = {
LinearLayout,
orientation = "vertical",
layout_width = "fill",
layout_height = "fill",
padding = "20dp",
backgroundColor = "#1A1A2E",
{TextView, text = "AI Video Generator", layout_width = "fill", layout_height = "wrap", textSize = "26sp", textColor = "#E94560", gravity = "center", layout_marginBottom = "16dp"},
{EditText, id = "videoPrompt", hint = "Describe your video (max 300 characters)", layout_width = "fill", layout_height = "100dp", textSize = "15sp", padding = "12dp", layout_marginBottom = "6dp", backgroundColor = "#16213E", textColor = "#FFFFFF"},
{TextView, id = "charCount", text = "0/300", layout_width = "fill", layout_height = "wrap", textSize = "12sp", textColor = "#888888", gravity = "right", layout_marginBottom = "10dp"},
{
LinearLayout,
orientation = "horizontal",
layout_width = "fill",
layout_height = "wrap",
layout_marginBottom = "6dp",
{Button, id = "generateBtn", text = "Generate", layout_width = "0dp", layout_weight = 1, layout_height = "55dp", textSize = "15sp", backgroundColor = "#E94560", textColor = "#FFFFFF", layout_marginEnd = "6dp"},
{TextView, id = "statusText", text = "", layout_width = "0dp", layout_weight = 2, layout_height = "55dp", textSize = "12sp", padding = "8dp", backgroundColor = "#16213E", textColor = "#FFFFFF", gravity = "center", visibility = "gone"}
},
{Button, id = "improveBtn", text = "Improve Prompt with AI", layout_width = "fill", layout_height = "50dp", textSize = "14sp", backgroundColor = "#0F3460", textColor = "#FFFFFF", layout_marginBottom = "8dp"},
{
LinearLayout,
orientation = "horizontal",
layout_width = "fill",
layout_height = "wrap",
layout_marginBottom = "8dp",
{Button, id = "watchBtn", text = "Watch", layout_width = "0dp", layout_weight = 1, layout_height = "55dp", textSize = "15sp", backgroundColor = "#0F3460", textColor = "#FFFFFF", layout_marginEnd = "6dp", visibility = "gone"},
{Button, id = "downloadBtn", text = "Download", layout_width = "0dp", layout_weight = 1, layout_height = "55dp", textSize = "15sp", backgroundColor = "#533483", textColor = "#FFFFFF", visibility = "gone"}
},
{
LinearLayout,
orientation = "horizontal",
layout_width = "fill",
layout_height = "wrap",
layout_marginBottom = "8dp",
{Button, id = "shareBtn", text = "Share", layout_width = "0dp", layout_weight = 1, layout_height = "55dp", textSize = "15sp", backgroundColor = "#0F3460", textColor = "#FFFFFF", layout_marginEnd = "6dp", visibility = "gone"},
{Button, id = "deleteBtn", text = "Delete File", layout_width = "0dp", layout_weight = 1, layout_height = "55dp", textSize = "15sp", backgroundColor = "#E94560", textColor = "#FFFFFF", visibility = "gone"}
},
{Button, id = "manageBtn", text = "Manage Videos", layout_width = "fill", layout_height = "50dp", textSize = "13sp", backgroundColor = "#533483", textColor = "#FFFFFF", layout_marginBottom = "6dp"},
{Button, id = "openWebBtn", text = "Open AI Video Generator on Web", layout_width = "fill", layout_height = "50dp", textSize = "13sp", backgroundColor = "#0F3460", textColor = "#FFFFFF", layout_marginBottom = "6dp"},
{Button, id = "closeBtn", text = "Close", layout_width = "fill", layout_height = "50dp", textSize = "13sp", backgroundColor = "#E94560", textColor = "#FFFFFF", layout_marginBottom = "10dp"},
{TextView, text = "© Shri Shyam Devs", layout_width = "fill", layout_height = "wrap", textSize = "12sp", textColor = "#555555", gravity = "center", layout_marginBottom = "6dp"},
{
LinearLayout,
orientation = "horizontal",
layout_width = "fill",
layout_height = "wrap",
gravity = "center",
layout_marginBottom = "6dp",
{Button, id = "emailBtn", text = "Email Us", layout_width = "0dp", layout_weight = 1, layout_height = "44dp", textSize = "12sp", backgroundColor = "#E94560", textColor = "#FFFFFF", layout_marginEnd = "6dp"},
{Button, id = "telegramBtn", text = "Join Shri Shyam Devs", layout_width = "0dp", layout_weight = 1, layout_height = "44dp", textSize = "12sp", backgroundColor = "#0F3460", textColor = "#FFFFFF"}
},
{Button, id = "friendTelegramBtn", text = "Join Plugins impacientes", layout_width = "fill", layout_height = "44dp", textSize = "12sp", backgroundColor = "#533483", textColor = "#FFFFFF"}
}
local mainView = loadlayout(mainLayout)
local mainDlg = LuaDialog(this).setView(mainView).setCancelable(true)
local tw = {
beforeTextChanged = function(s, start, count, after) end,
onTextChanged = function(s, start, before, count)
charCount.setText(s.length() .. "/300")
charCount.setTextColor(s.length() > MAX_PROMPT_LENGTH and 0xFFFF4444 or 0xFF888888)
end,
afterTextChanged = function(s) end
}
videoPrompt.addTextChangedListener(luajava.createProxy("android.text.TextWatcher", tw))
generateBtn.onClick = function()
local prompt = videoPrompt.getText().toString()
if not prompt or #prompt == 0 then Toast.makeText(this, "Please enter a prompt", Toast.LENGTH_SHORT).show() return end
if #prompt > MAX_PROMPT_LENGTH then Toast.makeText(this, "Prompt exceeds 300 characters", Toast.LENGTH_SHORT).show() return end
currentPrompt = prompt
currentVideoUrl = ""
downloadedFilePath = ""
generateBtn.setEnabled(false)
improveBtn.setEnabled(false)
watchBtn.setVisibility(View.GONE)
downloadBtn.setVisibility(View.GONE)
shareBtn.setVisibility(View.GONE)
deleteBtn.setVisibility(View.GONE)
statusText.setVisibility(View.VISIBLE)
statusText.setText("Generating video, please wait...")
service.speak("Generating video, please wait")
generateVideo(prompt, function(ok, result)
generateBtn.setEnabled(true)
improveBtn.setEnabled(true)
if ok then
currentVideoUrl = result
statusText.setText("Video ready!")
watchBtn.setVisibility(View.VISIBLE)
downloadBtn.setVisibility(View.VISIBLE)
service.speak("Video generated successfully")
else
statusText.setText("Error: " .. result)
service.speak("Generation failed")
end
end)
end
improveBtn.onClick = function()
local prompt = videoPrompt.getText().toString()
if not prompt or #prompt == 0 then Toast.makeText(this, "Enter a prompt first", Toast.LENGTH_SHORT).show() return end
improveBtn.setEnabled(false)
generateBtn.setEnabled(false)
statusText.setVisibility(View.VISIBLE)
statusText.setText("Improving prompt...")
service.speak("Improving prompt with AI")
improvePrompt(prompt, function(ok, result)
improveBtn.setEnabled(true)
generateBtn.setEnabled(true)
if ok then
videoPrompt.setText(result)
videoPrompt.setSelection(result:len())
statusText.setText("Prompt improved!")
service.speak("Prompt improved")
else
statusText.setText(result)
service.speak("Could not improve prompt")
end
end)
end
watchBtn.onClick = function()
if currentVideoUrl ~= "" then showVideoPlayerDialog(currentVideoUrl) end
end
downloadBtn.onClick = function()
if currentVideoUrl == "" then return end
local defName = cleanFilename(currentPrompt)
local dlLayout = {
LinearLayout,
orientation = "vertical",
layout_width = "fill",
layout_height = "wrap",
padding = "20dp",
backgroundColor = "#1A1A2E",
{TextView, text = "Save Video As", textSize = "18sp", textColor = "#E94560", gravity = "center", layout_marginBottom = "12dp"},
{EditText, id = "fileNameInput", text = defName, hint = "File name (without extension)", layout_width = "fill", layout_height = "wrap", textSize = "15sp", padding = "10dp", backgroundColor = "#16213E", textColor = "#FFFFFF", layout_marginBottom = "12dp"},
{
LinearLayout,
orientation = "horizontal",
layout_width = "fill",
layout_height = "wrap",
{Button, text = "Save", layout_width = "0dp", layout_weight = 1, layout_height = "50dp", textSize = "15sp", backgroundColor = "#E94560", textColor = "#FFFFFF", layout_marginEnd = "6dp", onClick = function()
local fname = fileNameInput.getText().toString()
if not fname or #fname == 0 then Toast.makeText(this, "Enter a file name", Toast.LENGTH_SHORT).show() return end
fname = fname:gsub("[^%w%s%-_]", ""):gsub("%s+", "_")
if fname == "" then fname = "video" end
dlDlg.dismiss()
statusText.setText("Downloading...")
shareBtn.setVisibility(View.GONE)
deleteBtn.setVisibility(View.GONE)
service.speak("Downloading video")
downloadVideo(currentVideoUrl, fname .. ".mp4", function(success, path)
if success then
downloadedFilePath = path
statusText.setText("Saved: " .. path)
shareBtn.setVisibility(View.VISIBLE)
deleteBtn.setVisibility(View.VISIBLE)
service.speak("Download complete")
else
downloadedFilePath = ""
statusText.setText("Download failed: " .. path)
service.speak("Download failed")
end
end)
end},
{Button, text = "Cancel", layout_width = "0dp", layout_weight = 1, layout_height = "50dp", textSize = "15sp", backgroundColor = "#533483", textColor = "#FFFFFF", onClick = function() dlDlg.dismiss() end}
}
}
dlDlg = LuaDialog(this).setView(loadlayout(dlLayout)).setCancelable(true)
dlDlg.show()
end
shareBtn.onClick = function()
if downloadedFilePath ~= "" then
service.shareFile(downloadedFilePath)
mainDlg.dismiss()
else
Toast.makeText(this, "No file to share", Toast.LENGTH_SHORT).show()
end
end
deleteBtn.onClick = function()
if downloadedFilePath == "" then return end
LuaDialog(this).setTitle("Delete this video?").setPositiveButton("Yes", function()
local f = File(downloadedFilePath)
if f.exists() and f.delete() then
downloadedFilePath = ""
statusText.setText("File deleted")
shareBtn.setVisibility(View.GONE)
deleteBtn.setVisibility(View.GONE)
service.speak("File deleted")
else
Toast.makeText(this, "Failed to delete", Toast.LENGTH_SHORT).show()
end
end).setNegativeButton("No", function() end).show()
end
manageBtn.onClick = function() showManageVideosDialog() end
closeBtn.onClick = function() mainDlg.dismiss() end
openWebBtn.onClick = function() openUrl(mainDlg, "https://ai-video.shrishyamdevs.com") end
emailBtn.onClick = function() openUrl(mainDlg, "mailto:support@shrishyamdevs.com") end
telegramBtn.onClick = function() openUrl(mainDlg, "https://t.me/shrishyamdevs") end
friendTelegramBtn.onClick = function() openUrl(mainDlg, "https://t.me/Pluginimpaciente") end
mainDlg.show()
end

showMainDialog()