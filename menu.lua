require "lib.moonloader"
local keys = require "vkeys"
local imgui = require "imgui"
local encoding = require "encoding"

--main variables
local main_color = 0x5A90CE
encoding.default = "CP1251"
u8 = encoding.utf8
--window settings
local main_window_state = imgui.ImBool(false)
local text_buffer = imgui.ImBuffer(256)

--dadawdad
local enabled = imgui.ImBool(false)
local teamprotect = imgui.ImBool(false)
local fov = imgui.ImInt(120)
local smooth = imgui.ImInt(8)
local deagle = imgui.ImBool(false)
local shotgun = imgui.ImBool(false)
local m4 = imgui.ImBool(false)
local rifle = imgui.ImBool(false)

function main()
	if not isSampLoaded() or not isSampfuncsLoaded() then return end
	while not isSampAvailable() do wait(100) end
	--default wuindows state
	imgui.Process = false
	while true do
		wait(0)

		if main_window_state.v == false then
			imgui.Process = false
		end

		--main 
		if isKeyDown(VK_SHIFT) and isKeyJustPressed(VK_R) then
			--sampAddChatMessage("shift + k", main_color)
			winact()
		end
	end
end

function winact()
	main_window_state.v = not main_window_state.v
	imgui.Process = main_window_state.v
end

function imgui.OnDrawFrame()
    imgui.SetNextWindowSize(imgui.ImVec2(300, 400), imgui.Cond.FirstUseEver)
    imgui.SetNextWindowPos(imgui.ImVec2(300, 600), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))

	imgui.Begin("SMOOTH", main_window_state, imgui.WindowFlags.NoResize)
    imgui.SetCursorPosX(115)
    imgui.Text("shmkz aimbot)")
	imgui.Checkbox("Enabled", enabled)
    imgui.Separator()
    imgui.Checkbox('Team Protect', teamprotect)
	imgui.Text("FOV")
    imgui.SliderInt('fov', fov, 1, 200)
	imgui.Text("Smooth")
	imgui.SliderInt('smooth', smooth, 1, 50)
	imgui.Separator()
	imgui.Text("Weapong")
	imgui.Checkbox('deagle', deagle)
	imgui.Checkbox('m4', m4)
	imgui.Checkbox('shotgun', shotgun)
	imgui.Checkbox('rifle', rifle)	
    imgui.End()
end