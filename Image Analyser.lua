local dir = PLUGIN_DIR or package.searchpath("main", package.path):match("(.*)main.lua")
local uiLanguages = assert(loadfile(dir .. "ui.lua"))()

require "import"
import "android.content.*"
import "android.widget.*"
import "android.view.*"
import "android.graphics.Bitmap"
import "android.graphics.BitmapFactory"
import "android.util.Base64"
import "java.io.*"
import "cjson"
import "android.net.Uri"
import "android.media.MediaPlayer"
import "android.os.Environment"
import "java.text.SimpleDateFormat"
import "java.util.Date"
import "java.util.Locale"
import "android.os.Handler"
import "android.os.Looper"
import "android.provider.MediaStore"
import "android.database.Cursor"

local STRINGS = nil
local langPath = dir .. "Translation strings/"
local currentUILang = "English"
local VERCEL_URL = "https://image-analyser-shrishyamcoders.vercel.app/describe"
local context = this or service
local prefs = context.getSharedPreferences("groq_prefs", Context.MODE_PRIVATE)
local editor = prefs.edit()
local mainHandler = Handler(Looper.getMainLooper())
local externalStorage = Environment.getExternalStorageDirectory().getAbsolutePath()

local savedUILang = prefs.getString("selected_ui_language", nil)
if savedUILang then currentUILang = savedUILang end

local showConfigDialog
local createMainDialog

local function loadTranslationStrings()
    local ok, result = pcall(function()
        return assert(loadfile(langPath .. currentUILang .. ".lua"))()
    end)
    if ok and result then
        STRINGS = result
    else
        currentUILang = "English"
        STRINGS = assert(loadfile(langPath .. "English.lua"))()
    end
end

function setUILanguage(lang)
    local ok, result = pcall(function()
        return assert(loadfile(langPath .. lang .. ".lua"))()
    end)
    if ok and result then
        currentUILang = lang
        STRINGS = result
        editor.putString("selected_ui_language", currentUILang)
        editor.commit()
    else
        currentUILang = "English"
        STRINGS = assert(loadfile(langPath .. "English.lua"))()
        Toast.makeText(context, "Language file not found, using English", Toast.LENGTH_SHORT).show()
        editor.putString("selected_ui_language", "English")
        editor.commit()
    end
end

loadTranslationStrings()

local languageDisplayNames = {}
for name in pairs(uiLanguages) do
    table.insert(languageDisplayNames, name)
end
table.sort(languageDisplayNames)

local function getDeviceLanguage()
    local locale = Locale.getDefault()
    return locale.getLanguage(), locale.getDisplayLanguage()
end

local function generateImagePrompt()
    local _, displayLanguage = getDeviceLanguage()
    return string.format(
        "Analyze this image in great detail, focusing solely on its content. Do not include any additional information or generic statements that AI typically provides. Answer in %s.",
        displayLanguage
    )
end

local useCustomApi = prefs.getBoolean("use_custom_api", false)
local customApiKey = prefs.getString("custom_api_key", "")
local playAnalysisSound = prefs.getBoolean("play_analysis_sound", true)
local lastCapturedImagePath = nil
local saveImagesEnabled = prefs.getBoolean("save_images_enabled", false)
local lastAIReply = ""
local currentMediaBase64 = nil
local currentMediaType = nil
local currentMediaPath = nil
local currentSessionType = nil
local imageExtensions = {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp"}
local backgroundMediaPlayer = nil

local CAPTURE_MODES = {
    CURRENT_ELEMENT = "current_element",
    FULL_SCREEN = "full_screen",
    DISABLED = "disabled"
}
local selectedCaptureMode = prefs.getString("capture_mode", CAPTURE_MODES.DISABLED)
local useCustomInstructions = prefs.getBoolean("use_custom_instructions", false)
local customImageInstructions = prefs.getString("custom_image_instructions", "")

local function buildPayload(prompt)
    local payload = {image = currentMediaBase64, prompt = prompt}
    if useCustomApi and customApiKey ~= "" then
        payload.key = customApiKey
    end
    return cjson.encode(payload)
end

local function clearSession()
    currentMediaBase64 = nil
    currentMediaType = nil
    currentMediaPath = nil
    currentSessionType = nil
    lastCapturedImagePath = nil
    lastAIReply = ""
end

local function startNewSession(sessionType, mediaBase64, mediaType, mediaPath)
    clearSession()
    currentSessionType = sessionType
    currentMediaBase64 = mediaBase64
    currentMediaType = mediaType
    currentMediaPath = mediaPath
end

local function endsWith(str, suffix)
    return suffix == "" or str:sub(-#suffix) == suffix
end

function formatDate(timestamp)
    return SimpleDateFormat("dd/MM/yyyy HH:mm").format(Date(timestamp))
end

function isImageFile(filename)
    filename = filename:lower()
    for _, ext in ipairs(imageExtensions) do
        if endsWith(filename, ext) then return true end
    end
    return false
end

function formatFileSize(bytes)
    if bytes >= 1048576 then
        return string.format("%.1f MB", bytes / 1048576)
    elseif bytes >= 1024 then
        return string.format("%.1f KB", bytes / 1024)
    else
        return string.format("%d bytes", bytes)
    end
end

function loadFilesInBackground(limit, callback)
    Thread(Runnable {
        run = function()
            local items = getAllImages(limit)
            mainHandler.post(Runnable {
                run = function() callback(items) end
            })
        end
    }).start()
end

function getAllImages(limit)
    local results = {}
    local projection = {
        MediaStore.MediaColumns.DISPLAY_NAME,
        MediaStore.MediaColumns.DATA,
        MediaStore.MediaColumns.SIZE,
        MediaStore.MediaColumns.DATE_MODIFIED
    }
    local cursor = context.getContentResolver().query(
        MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
        projection, nil, nil,
        MediaStore.MediaColumns.DATE_MODIFIED .. " DESC"
    )
    if cursor and cursor.moveToFirst() then
        local ni = cursor.getColumnIndex(MediaStore.MediaColumns.DISPLAY_NAME)
        local pi = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
        local si = cursor.getColumnIndex(MediaStore.MediaColumns.SIZE)
        local di = cursor.getColumnIndex(MediaStore.MediaColumns.DATE_MODIFIED)
        local count = 0
        repeat
            if limit and count >= limit then break end
            table.insert(results, {
                name = cursor.getString(ni),
                path = cursor.getString(pi),
                size = cursor.getLong(si),
                lastModified = cursor.getLong(di) * 1000
            })
            count = count + 1
        until not cursor.moveToNext()
        cursor.close()
    end
    return results
end

function startBackgroundMusic()
    if backgroundMediaPlayer then
        backgroundMediaPlayer.release()
        backgroundMediaPlayer = nil
    end
    local soundPath = dir .. "background_chat.mp3"
    local f = io.open(soundPath, "r")
    if f then
        f:close()
        backgroundMediaPlayer = MediaPlayer()
        backgroundMediaPlayer.setDataSource(soundPath)
        backgroundMediaPlayer.setLooping(true)
        backgroundMediaPlayer.prepare()
        backgroundMediaPlayer.start()
    end
end

function stopBackgroundMusic()
    if backgroundMediaPlayer then
        backgroundMediaPlayer.stop()
        backgroundMediaPlayer.release()
        backgroundMediaPlayer = nil
    end
end

function openTelegramChannel1()
    service.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://t.me/jieshuoofficial")))
end

function openTelegramChannel2()
    service.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://t.me/Tech_VisionaryM_M")))
end

local function bitmapToBase64(bitmap)
    local out = ByteArrayOutputStream()
    bitmap.compress(Bitmap.CompressFormat.JPEG, 95, out)
    return Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
end

local function callVercel(prompt, callback)
    local headers = {["Content-Type"] = "application/json"}
    Http.post(VERCEL_URL, buildPayload(prompt), headers, function(code, resp)
        if playAnalysisSound then stopBackgroundMusic() end
        if code ~= 200 then
            callback(false, STRINGS.API_ERROR_PREFIX .. tostring(code))
            return
        end
        local ok, data = pcall(cjson.decode, resp)
        if ok and data and data.result then
            callback(true, data.result)
        elseif ok and data and data.error then
            callback(false, data.error)
        else
            callback(false, STRINGS.NO_VALID_DESCRIPTION)
        end
    end)
end

local function showUnifiedResponseDialog(title, content)
    lastAIReply = content or ""
    service.asyncSpeak(lastAIReply)
    local isScreenshot = (currentSessionType == "screenshot")

    local dialogLayout = {
        ScrollView,
        layout_width = "fill",
        layout_height = "fill",
        {
            LinearLayout,
            orientation = "vertical",
            layout_width = "fill",
            layout_height = "wrap_content",
            padding = "16dp",
            {
                TextView,
                id = "response_text",
                text = lastAIReply,
                textSize = "16sp",
                layout_width = "fill",
                layout_height = "wrap_content",
                padding = "10dp"
            },
            {
                LinearLayout,
                orientation = "horizontal",
                layout_width = "fill",
                layout_height = "wrap_content",
                layout_marginTop = "8dp",
                {
                    Button,
                    text = STRINGS.COPY_BUTTON,
                    layout_width = "0dp",
                    layout_height = "wrap_content",
                    layout_weight = "1",
                    onClick = function()
                        if lastAIReply ~= "" then
                            local clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE)
                            clipboard.setPrimaryClip(ClipData.newPlainText("Response", lastAIReply))
                            service.speak(STRINGS.RESPONSE_COPIED)
                        else
                            service.speak(STRINGS.NO_RESPONSE_TO_COPY)
                        end
                    end
                },
                {
                    Button,
                    text = STRINGS.SHARE_DESCRIPTION_BUTTON,
                    layout_width = "0dp",
                    layout_height = "wrap_content",
                    layout_weight = "1",
                    onClick = function()
                        if lastAIReply ~= "" then
                            local intent = Intent(Intent.ACTION_SEND)
                            intent.setType("text/plain")
                            intent.putExtra(Intent.EXTRA_TEXT, lastAIReply)
                            context.startActivity(Intent.createChooser(intent, "Share response"))
                        else
                            service.speak(STRINGS.NO_RESPONSE_TO_SHARE)
                        end
                        dlg_response_unified.dismiss()
                    end
                },
                {
                    Button,
                    id = "share_image_btn",
                    text = STRINGS.SHARE_IMAGE_BUTTON,
                    layout_width = "0dp",
                    layout_height = "wrap_content",
                    layout_weight = "1",
                    enabled = saveImagesEnabled,
                    onClick = function()
                        local imagePath = currentMediaPath or lastCapturedImagePath
                        if imagePath then service.shareFile(imagePath) end
                        dlg_response_unified.dismiss()
                    end
                }
            },
            {
                EditText,
                id = "user_query_input_unified",
                hint = STRINGS.IMAGE_QUESTION_HINT,
                layout_width = "fill",
                layout_height = "wrap_content",
                layout_marginTop = "8dp"
            },
            {
                LinearLayout,
                orientation = "horizontal",
                layout_width = "fill",
                layout_height = "wrap_content",
                {
                    Button,
                    text = STRINGS.SEND_BUTTON,
                    layout_width = "0dp",
                    layout_height = "wrap_content",
                    layout_weight = "1",
                    onClick = function()
                        local query = user_query_input_unified.getText().toString()
                        if query and #query > 0 then
                            if playAnalysisSound then startBackgroundMusic() end
                            service.speak(STRINGS.GENERATING_RESPONSE)
                            callVercel(query, function(ok, reply)
                                lastAIReply = reply
                                response_text.setText(reply)
                                service.speak(reply)
                                user_query_input_unified.setText("")
                            end)
                        else
                            service.speak(STRINGS.PLEASE_WRITE_QUESTION)
                        end
                    end
                },
                {
                    Button,
                    id = "toggle_capture_mode_btn",
                    text = string.format(STRINGS.CAPTURE_MODE_FORMAT,
                        selectedCaptureMode == CAPTURE_MODES.CURRENT_ELEMENT and STRINGS.CAPTURE_CURRENT_ELEMENT or
                        selectedCaptureMode == CAPTURE_MODES.FULL_SCREEN and STRINGS.CAPTURE_FULL_SCREEN or STRINGS.CAPTURE_DISABLED),
                    layout_width = "0dp",
                    layout_height = "wrap_content",
                    layout_weight = "1",
                    visibility = isScreenshot and View.VISIBLE or View.GONE,
                    onClick = function()
                        if selectedCaptureMode == CAPTURE_MODES.DISABLED then
                            selectedCaptureMode = CAPTURE_MODES.CURRENT_ELEMENT
                        elseif selectedCaptureMode == CAPTURE_MODES.CURRENT_ELEMENT then
                            selectedCaptureMode = CAPTURE_MODES.FULL_SCREEN
                        else
                            selectedCaptureMode = CAPTURE_MODES.DISABLED
                        end
                        toggle_capture_mode_btn.setText(string.format(STRINGS.CAPTURE_MODE_FORMAT,
                            selectedCaptureMode == CAPTURE_MODES.CURRENT_ELEMENT and STRINGS.CAPTURE_CURRENT_ELEMENT or
                            selectedCaptureMode == CAPTURE_MODES.FULL_SCREEN and STRINGS.CAPTURE_FULL_SCREEN or STRINGS.CAPTURE_DISABLED))
                        editor.putString("capture_mode", selectedCaptureMode)
                        editor.commit()
                    end
                },
                {
                    Button,
                    text = STRINGS.CLOSE_BUTTON,
                    layout_width = "0dp",
                    layout_height = "wrap_content",
                    layout_weight = "1",
                    onClick = function()
                        if not isScreenshot and playAnalysisSound then stopBackgroundMusic() end
                        clearSession()
                        dlg_response_unified.dismiss()
                    end
                }
            }
        }
    }

    dlg_response_unified = LuaDialog(service)
    dlg_response_unified.setTitle(title)
    dlg_response_unified.setView(loadlayout(dialogLayout))
    dlg_response_unified.show()
end

local function showFileExplorer()
    local imageList = {}
    local mimeTypes = {
        jpg = "image/jpeg", jpeg = "image/jpeg", png = "image/png",
        gif = "image/gif", bmp = "image/bmp", webp = "image/webp"
    }
    local dialogLayout = {
        LinearLayout,
        orientation = "vertical",
        layout_width = "fill",
        layout_height = "fill",
        {
            TextView,
            id = "explorerStatusText",
            textSize = "14sp",
            layout_width = "fill",
            layout_height = "wrap_content",
            padding = "10dp",
            text = STRINGS.LOADING_TEXT
        },
        {
            ListView,
            id = "fileListView",
            layout_width = "fill",
            layout_height = "fill",
            layout_weight = "1"
        },
        {
            Button,
            text = STRINGS.CLOSE_BUTTON,
            layout_width = "fill",
            layout_height = "wrap_content",
            onClick = function() dialog.dismiss() end
        }
    }

    local dialog = LuaDialog(service)
    dialog.setView(loadlayout(dialogLayout))
    dialog.setTitle(STRINGS.MEDIA_EXPLORER_TITLE)
    dialog.show()

    local items = {}
    local adapter = ArrayAdapter(service, android.R.layout.simple_list_item_1, items)
    fileListView.setAdapter(adapter)

    loadFilesInBackground(1000, function(result)
        imageList = result
        adapter.clear()
        for _, item in ipairs(imageList) do
            adapter.add(string.format(STRINGS.FILE_FORMAT, item.name, formatFileSize(item.size), formatDate(item.lastModified)))
        end
        explorerStatusText.setText(string.format(STRINGS.ALL_IMAGES_FORMAT, #imageList))
        fileListView.setAdapter(adapter)
    end)

    fileListView.onItemClick = function(parent, view, position, id)
        if position < #imageList then
            local selected = imageList[position + 1]
            local ext = selected.name:match("%.(%w+)$")
            local mimeType = ext and mimeTypes[ext:lower()]
            if not mimeType then
                service.speak(STRINGS.UNSUPPORTED_FILE_TYPE)
                return
            end
            local bitmap = BitmapFactory.decodeFile(selected.path)
            if not bitmap then
                service.speak(STRINGS.IMAGE_LOAD_ERROR)
                return
            end
            local imageBase64 = bitmapToBase64(bitmap)
            local imagePath = saveImagesEnabled and selected.path or nil
            startNewSession("file_image", imageBase64, mimeType, imagePath)
            dialog.dismiss()
            if playAnalysisSound then startBackgroundMusic() end
            local prompt = (useCustomInstructions and customImageInstructions ~= "") and customImageInstructions or generateImagePrompt()
            callVercel(prompt, function(ok, description)
                showUnifiedResponseDialog(ok and STRINGS.IMAGE_DESCRIPTION_TITLE or STRINGS.ERROR_TITLE, description)
            end)
        end
    end
end

local function captureAndProcess(node, isFullScreen)
    service.speak(STRINGS.ANALYZING_IMAGE)
    local captureCallback = function(bitmap)
        local imageBase64 = bitmapToBase64(bitmap)
        startNewSession("screenshot", imageBase64, "image/jpeg", lastCapturedImagePath)
        if saveImagesEnabled then
            local fileName = (isFullScreen and "fullscreen_" or "element_") .. SimpleDateFormat("yyyyMMdd_HHmmss").format(Date()) .. ".jpg"
            local groqDir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "GroqImages")
            if not groqDir.exists() then groqDir.mkdirs() end
            local imageFile = File(groqDir, fileName)
            local outputStream = FileOutputStream(imageFile)
            bitmap.compress(Bitmap.CompressFormat.JPEG, 95, outputStream)
            outputStream.close()
            lastCapturedImagePath = imageFile.getAbsolutePath()
            currentMediaPath = lastCapturedImagePath
        end
        if playAnalysisSound then startBackgroundMusic() end
        local prompt = (useCustomInstructions and customImageInstructions ~= "") and customImageInstructions or generateImagePrompt()
        callVercel(prompt, function(ok, description)
            if ok then
                showUnifiedResponseDialog(STRINGS.IMAGE_DESCRIPTION_TITLE, description)
            else
                service.speak(STRINGS.ERROR_TITLE .. ": " .. description)
                showUnifiedResponseDialog(STRINGS.ERROR_TITLE, description)
            end
        end)
    end
    if node then
        this.getScreenShot(node, {onScreenCaptureDone = captureCallback})
    else
        this.getScreenShot({onScreenCaptureDone = captureCallback})
    end
end

local function showCustomInstructionsDialog()
    local dlg_instructions
    local layout = {
        LinearLayout,
        orientation = "vertical",
        layout_width = "fill",
        layout_height = "wrap_content",
        padding = "16dp",
        {TextView, text = STRINGS.IMAGE_INSTRUCTIONS_LABEL, textSize = "16sp", layout_width = "fill", layout_height = "wrap_content"},
        {EditText, id = "image_instructions_edit", hint = STRINGS.IMAGE_INSTRUCTIONS_HINT, layout_width = "fill", layout_height = "150dp", inputType = "textMultiLine", gravity = "top|left", text = customImageInstructions},
        {
            LinearLayout,
            orientation = "horizontal",
            layout_width = "fill",
            layout_height = "wrap_content",
            layout_marginTop = "16dp",
            {
                Button,
                text = STRINGS.SAVE_BUTTON,
                layout_width = "0dp",
                layout_height = "wrap_content",
                layout_weight = "1",
                onClick = function()
                    customImageInstructions = image_instructions_edit.getText().toString()
                    editor.putString("custom_image_instructions", customImageInstructions)
                    editor.commit()
                    dlg_instructions.dismiss()
                end
            },
            {
                Button,
                text = STRINGS.CANCEL_BUTTON,
                layout_width = "0dp",
                layout_height = "wrap_content",
                layout_weight = "1",
                onClick = function() dlg_instructions.dismiss() end
            }
        }
    }
    dlg_instructions = LuaDialog(service)
    dlg_instructions.setTitle(STRINGS.CUSTOM_INSTRUCTIONS_TITLE)
    dlg_instructions.setView(loadlayout(layout))
    dlg_instructions.show()
end

showConfigDialog = function()
    local captureModeOptions = {STRINGS.CAPTURE_DISABLED, STRINGS.CAPTURE_CURRENT_ELEMENT, STRINGS.CAPTURE_FULL_SCREEN}
    local captureModeValues = {CAPTURE_MODES.DISABLED, CAPTURE_MODES.CURRENT_ELEMENT, CAPTURE_MODES.FULL_SCREEN}
    local selectedCaptureModePosition = 1
    for i, mode in ipairs(captureModeValues) do
        if mode == selectedCaptureMode then selectedCaptureModePosition = i break end
    end
    local currentLanguageIndex = 1
    for index, name in ipairs(languageDisplayNames) do
        if uiLanguages[name] == currentUILang then currentLanguageIndex = index break end
    end

    local configDialogLayout = {
        ScrollView,
        layout_width = "fill",
        layout_height = "fill",
        {
            LinearLayout,
            orientation = "vertical",
            layout_width = "fill",
            layout_height = "wrap_content",
            padding = "16dp",
            {TextView, text = STRINGS.UI_LANGUAGE_LABEL, textSize = "18sp", layout_width = "fill", layout_height = "wrap_content", layout_marginBottom = "8dp"},
            {Spinner, id = "ui_language_spinner", layout_width = "fill", layout_height = "wrap_content", layout_marginBottom = "16dp"},
            {TextView, text = STRINGS.AUTO_CAPTURE_MODE, textSize = "18sp", layout_width = "fill", layout_height = "wrap_content", layout_marginBottom = "8dp", layout_marginTop = "16dp"},
            {Spinner, id = "capture_mode_spinner", layout_width = "fill", layout_height = "wrap_content", layout_marginBottom = "16dp"},
            {Switch, id = "save_images_switch", text = STRINGS.SAVE_IMAGES_SWITCH, checked = saveImagesEnabled, layout_width = "fill", layout_height = "wrap_content", layout_marginTop = "16dp"},
            {Switch, id = "play_sound_switch", text = STRINGS.PLAY_SOUND_SWITCH, checked = playAnalysisSound, layout_width = "fill", layout_height = "wrap_content", layout_marginTop = "16dp"},
            {Switch, id = "custom_instructions_switch", text = STRINGS.CUSTOM_INSTRUCTIONS_SWITCH, checked = useCustomInstructions, layout_width = "fill", layout_height = "wrap_content", layout_marginTop = "16dp"},
            {Switch, id = "custom_api_switch", text = STRINGS.CUSTOM_API_SWITCH, checked = useCustomApi, layout_width = "fill", layout_height = "wrap_content", layout_marginTop = "16dp"},
            {
                Button,
                id = "instructions_button",
                text = STRINGS.CUSTOM_INSTRUCTIONS_BUTTON,
                layout_width = "fill",
                layout_height = "wrap_content",
                layout_marginTop = "8dp",
                enabled = useCustomInstructions,
                onClick = function() showCustomInstructionsDialog() end
            },
            {
                Button,
                id = "api_button",
                text = STRINGS.CUSTOM_API_BUTTON,
                layout_width = "fill",
                layout_height = "wrap_content",
                layout_marginTop = "8dp",
                enabled = useCustomApi,
                onClick = function()
                    local dlg_custom_api
                    local apiLayout = {
                        LinearLayout,
                        orientation = "vertical",
                        layout_width = "fill",
                        layout_height = "wrap_content",
                        padding = "16dp",
                        {EditText, id = "custom_api_key_input", hint = STRINGS.API_KEY_HINT, layout_width = "fill", layout_height = "wrap_content", text = customApiKey},
                        {
                            LinearLayout,
                            orientation = "horizontal",
                            layout_width = "fill",
                            layout_height = "wrap_content",
                            layout_marginTop = "16dp",
                            {
                                Button,
                                text = STRINGS.SAVE_BUTTON,
                                layout_width = "0dp",
                                layout_height = "wrap_content",
                                layout_weight = "1",
                                onClick = function()
                                    customApiKey = custom_api_key_input.getText().toString()
                                    useCustomApi = custom_api_switch.isChecked()
                                    editor.putString("custom_api_key", customApiKey)
                                    editor.commit()
                                    dlg_custom_api.dismiss()
                                end
                            },
                            {
                                Button,
                                text = STRINGS.CANCEL_BUTTON,
                                layout_width = "0dp",
                                layout_height = "wrap_content",
                                layout_weight = "1",
                                onClick = function() dlg_custom_api.dismiss() end
                            }
                        }
                    }
                    dlg_custom_api = LuaDialog(service)
                    dlg_custom_api.setTitle(STRINGS.CUSTOM_API_TITLE)
                    dlg_custom_api.setView(loadlayout(apiLayout))
                    dlg_custom_api.show()
                end
            },
            {TextView, text = "Developed by: David Treminio & Ayush Kumar", textSize = "14sp", layout_width = "fill", layout_height = "wrap_content", padding = "8dp", layout_marginTop = "16dp"},
            {
                Button,
                text = STRINGS.JIESHUO_CHANNEL_BUTTON,
                layout_width = "fill",
                layout_height = "wrap_content",
                layout_marginTop = "4dp",
                onClick = function() openTelegramChannel1() dlg_config.dismiss() dlg_main.dismiss() end
            },
            {
                Button,
                text = STRINGS.TECHVISIONARY_CHANNEL_BUTTON,
                layout_width = "fill",
                layout_height = "wrap_content",
                layout_marginTop = "4dp",
                onClick = function() openTelegramChannel2() dlg_config.dismiss() dlg_main.dismiss() end
            },
            {
                Button,
                text = STRINGS.BACK_BUTTON,
                layout_width = "fill",
                layout_height = "wrap_content",
                layout_marginTop = "16dp",
                onClick = function() dlg_config.dismiss() end
            }
        }
    }

    dlg_config = LuaDialog(service)
    dlg_config.setTitle(STRINGS.CONFIG_TITLE)
    dlg_config.setView(loadlayout(configDialogLayout))

    local uiLangAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, String(languageDisplayNames))
    uiLangAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
    ui_language_spinner.setAdapter(uiLangAdapter)
    ui_language_spinner.setSelection(currentLanguageIndex - 1)
    ui_language_spinner.setOnItemSelectedListener(AdapterView.OnItemSelectedListener{
        onItemSelected = function(parent, view, position, id)
            local selectedLang = uiLanguages[languageDisplayNames[position + 1]]
            if selectedLang ~= currentUILang then
                setUILanguage(selectedLang)
                dlg_config.dismiss()
                if dlg_main then dlg_main.dismiss() end
                createMainDialog()
                dlg_main.show()
                showConfigDialog()
            end
        end,
        onNothingSelected = function() end
    })

    save_images_switch.setOnCheckedChangeListener{
        onCheckedChanged = function(view, isChecked)
            saveImagesEnabled = isChecked
            editor.putBoolean("save_images_enabled", isChecked)
            editor.commit()
            if share_image_btn then share_image_btn.setEnabled(isChecked) end
        end
    }

    play_sound_switch.setOnCheckedChangeListener{
        onCheckedChanged = function(view, isChecked)
            playAnalysisSound = isChecked
            editor.putBoolean("play_analysis_sound", isChecked)
            editor.commit()
        end
    }

    custom_instructions_switch.setOnCheckedChangeListener{
        onCheckedChanged = function(view, isChecked)
            useCustomInstructions = isChecked
            editor.putBoolean("use_custom_instructions", isChecked)
            editor.commit()
            instructions_button.setEnabled(isChecked)
        end
    }

    custom_api_switch.setOnCheckedChangeListener{
        onCheckedChanged = function(view, isChecked)
            useCustomApi = isChecked
            editor.putBoolean("use_custom_api", isChecked)
            editor.commit()
            api_button.setEnabled(isChecked)
        end
    }

    local captureModeAdapter = ArrayAdapter(service, android.R.layout.simple_spinner_item, captureModeOptions)
    captureModeAdapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item)
    capture_mode_spinner.setAdapter(captureModeAdapter)
    capture_mode_spinner.setSelection(selectedCaptureModePosition - 1)
    capture_mode_spinner.setOnItemSelectedListener{
        onItemSelected = function(parent, view, position, id)
            selectedCaptureMode = captureModeValues[position + 1]
            editor.putString("capture_mode", selectedCaptureMode)
            editor.commit()
        end,
        onNothingSelected = function(parent) end
    }

    dlg_config.show()
end

createMainDialog = function()
    local mainDialogLayout = {
        ScrollView,
        layout_width = "fill",
        layout_height = "fill",
        {
            LinearLayout,
            orientation = "vertical",
            layout_width = "fill",
            layout_height = "wrap_content",
            padding = "16dp",
            {
                LinearLayout,
                orientation = "horizontal",
                layout_width = "fill",
                layout_height = "wrap_content",
                layout_marginTop = "16dp",
                {
                    Button,
                    text = STRINGS.SETTINGS_BUTTON,
                    layout_width = "0dp",
                    layout_height = "wrap_content",
                    layout_weight = "1",
                    onClick = function() showConfigDialog() end
                },
                {
                    Button,
                    text = STRINGS.CURRENT_ELEMENT_BUTTON,
                    layout_width = "0dp",
                    layout_height = "wrap_content",
                    layout_weight = "1",
                    onClick = function()
                        task(200, function() captureAndProcess(node, false) end)
                        dlg_main.dismiss()
                    end
                }
            },
            {
                LinearLayout,
                orientation = "horizontal",
                layout_width = "fill",
                layout_height = "wrap_content",
                layout_marginTop = "8dp",
                {
                    Button,
                    text = STRINGS.FULL_SCREEN_BUTTON,
                    layout_width = "0dp",
                    layout_height = "wrap_content",
                    layout_weight = "1",
                    onClick = function()
                        task(200, function() captureAndProcess(nil, true) end)
                        dlg_main.dismiss()
                    end
                },
                {
                    Button,
                    text = STRINGS.MEDIA_EXPLORER_BUTTON,
                    layout_width = "0dp",
                    layout_height = "wrap_content",
                    layout_weight = "1",
                    onClick = function()
                        showFileExplorer()
                        dlg_main.dismiss()
                    end
                }
            },
            {
                Button,
                text = STRINGS.EXIT_BUTTON,
                layout_width = "match_parent",
                layout_height = "wrap_content",
                layout_marginTop = "16dp",
                onClick = function() dlg_main.dismiss() end
            }
        }
    }
    dlg_main = LuaDialog(service)
    dlg_main.setTitle(STRINGS.MAIN_TITLE)
    dlg_main.setView(loadlayout(mainDialogLayout))
end

createMainDialog()

if selectedCaptureMode == CAPTURE_MODES.CURRENT_ELEMENT then
    task(200, function() captureAndProcess(node, false) end)
elseif selectedCaptureMode == CAPTURE_MODES.FULL_SCREEN then
    task(200, function() captureAndProcess(nil, true) end)
else
    dlg_main.show()
end

return true