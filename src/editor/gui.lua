-- ----------------------------------------------------------------------------
-- Global variables
-- Markers for editor marker margin
BREAKPOINT_MARKER         = 1
BREAKPOINT_MARKER_VALUE   = 2 -- = 2^BREAKPOINT_MARKER
CURRENT_LINE_MARKER       = 2
CURRENT_LINE_MARKER_VALUE = 4 -- = 2^CURRENT_LINE_MARKER

-- Globals
local font             = nil    -- fonts to use for the editor
local fontItalic       = nil

-- ----------------------------------------------------------------------------
-- Pick some reasonable fixed width fonts to use for the editor
if wx.__WXMSW__ then
	font       = wx.wxFont(10, wx.wxFONTFAMILY_MODERN, wx.wxFONTSTYLE_NORMAL, wx.wxFONTWEIGHT_NORMAL, false, ide.config.editor.fontname or "Courier New")
	fontItalic = wx.wxFont(10, wx.wxFONTFAMILY_MODERN, wx.wxFONTSTYLE_ITALIC, wx.wxFONTWEIGHT_NORMAL, false, ide.config.editor.fontname or "Courier New")
else
	font       = wx.wxFont(10, wx.wxFONTFAMILY_MODERN, wx.wxFONTSTYLE_NORMAL, wx.wxFONTWEIGHT_NORMAL, false, "")
	fontItalic = wx.wxFont(10, wx.wxFONTFAMILY_MODERN, wx.wxFONTSTYLE_ITALIC, wx.wxFONTWEIGHT_NORMAL, false, "")
end

ide.font       = font
ide.fontItalic = fontItalic

-- wxWindow variables
local frame            = nil    -- wxFrame the main top level window
	local toolBar      = nil
	local statusBar    = nil
	local menuBar      = nil
	
	local splitter     = nil    -- wxSplitterWindow for the notebook and errorLog
		local notebook = nil    -- wxNotebook of editors
		local bottomnotebook = nil	-- notebook for the GUIs in the bottom line
			local errorLog = nil    -- wxStyledTextCtrl log window for messages

-- ----------------------------------------------------------------------------
-- Create the wxFrame
-- ----------------------------------------------------------------------------
frame = wx.wxFrame(wx.NULL, wx.wxID_ANY, "Estrela Editor")

menuBar = wx.wxMenuBar()
statusBar = frame:CreateStatusBar( 4 )
local status_txt_width = statusBar:GetTextExtent("OVRW")
frame:SetStatusWidths({-1, status_txt_width, status_txt_width, status_txt_width*5})
frame:SetStatusText("Welcome to Estrela Editor")

frame:DragAcceptFiles(true)
frame:Connect(wx.wxEVT_DROP_FILES,function(evt)
		local files = evt:GetFiles()
		if not files or #files == 0 then return end
		for i,f in ipairs(files) do
			LoadFile(f,nil,true)
		end
	end)

toolBar = frame:CreateToolBar(wx.wxNO_BORDER + wx.wxTB_FLAT + wx.wxTB_DOCKABLE)
-- note: Ususally the bmp size isn't necessary, but the HELP icon is not the right size in MSW
local toolBmpSize = toolBar:GetToolBitmapSize()
toolBar:AddTool(ID_NEW,     "New",      wx.wxArtProvider.GetBitmap(wx.wxART_NORMAL_FILE, wx.wxART_MENU, toolBmpSize), "Create an empty document")
toolBar:AddTool(ID_OPEN,    "Open",     wx.wxArtProvider.GetBitmap(wx.wxART_FILE_OPEN, wx.wxART_MENU, toolBmpSize),   "Open an existing document")
toolBar:AddTool(ID_SAVE,    "Save",     wx.wxArtProvider.GetBitmap(wx.wxART_FILE_SAVE, wx.wxART_MENU, toolBmpSize),   "Save the current document")
toolBar:AddTool(ID_SAVEALL, "Save All", wx.wxArtProvider.GetBitmap(wx.wxART_NEW_DIR, wx.wxART_MENU, toolBmpSize),     "Save all documents")
toolBar:AddSeparator()
toolBar:AddTool(ID_CUT,   "Cut",   wx.wxArtProvider.GetBitmap(wx.wxART_CUT, wx.wxART_MENU, toolBmpSize),   "Cut the selection")
toolBar:AddTool(ID_COPY,  "Copy",  wx.wxArtProvider.GetBitmap(wx.wxART_COPY, wx.wxART_MENU, toolBmpSize),  "Copy the selection")
toolBar:AddTool(ID_PASTE, "Paste", wx.wxArtProvider.GetBitmap(wx.wxART_PASTE, wx.wxART_MENU, toolBmpSize), "Paste text from the clipboard")
toolBar:AddSeparator()
toolBar:AddTool(ID_UNDO, "Undo", wx.wxArtProvider.GetBitmap(wx.wxART_UNDO, wx.wxART_MENU, toolBmpSize), "Undo last edit")
toolBar:AddTool(ID_REDO, "Redo", wx.wxArtProvider.GetBitmap(wx.wxART_REDO, wx.wxART_MENU, toolBmpSize), "Redo last undo")
toolBar:AddSeparator()
toolBar:AddTool(ID_FIND,    "Find",    wx.wxArtProvider.GetBitmap(wx.wxART_FIND, wx.wxART_MENU, toolBmpSize), "Find text")
toolBar:AddTool(ID_REPLACE, "Replace", wx.wxArtProvider.GetBitmap(wx.wxART_FIND_AND_REPLACE, wx.wxART_MENU, toolBmpSize), "Find and replace text")
toolBar:AddSeparator()
toolBar:AddTool(ID "debug.projectdir.fromfile",     "Update",      wx.wxArtProvider.GetBitmap(wx.wxART_GO_DIR_UP , wx.wxART_MENU, toolBmpSize), "Sets projectdir from file")
toolBar:Realize()

-- ----------------------------------------------------------------------------
-- Add the child windows to the frame

splitter = wx.wxSplitterWindow(frame, wx.wxID_ANY,
							   wx.wxDefaultPosition, wx.wxDefaultSize,
							   wx.wxSP_3DSASH)
local ph
splitter:Connect(wx.wxEVT_SIZE, function (evt) 
		local h = evt:GetSize():GetHeight()
		ph = ph or h
		local h2 = ph
		ph = h
		local dh = splitter:GetSashPosition()
		splitter:SetSashPosition(dh-h2+h)
		splitter:UpdateSize()
		evt:Skip()
	end)

notebook = wx.wxNotebook(splitter, wx.wxID_ANY,
						 wx.wxDefaultPosition, wx.wxDefaultSize,
						 wx.wxCLIP_CHILDREN)

local current -- the currently active editor, needed by the focus selection
notebook:Connect(wx.wxEVT_COMMAND_NOTEBOOK_PAGE_CHANGED,
		function (event)
			current = event:GetSelection() -- update the active editor reference
			SetEditorSelection(event:GetSelection())
			event:Skip() -- skip to let page change
		end)

notebook:Connect(wx.wxEVT_SET_FOCUS, 	-- Notepad tabs shouldn't be selectable,
	function (event) 					-- select the editor then instead
		SetEditorSelection(current) -- select the currently active one.
	end)

bottomnotebook = wx.wxNotebook(splitter, wx.wxID_ANY,
						 wx.wxDefaultPosition, wx.wxDefaultSize,
						 wx.wxCLIP_CHILDREN)
errorLog = wxstc.wxStyledTextCtrl(bottomnotebook, wx.wxID_ANY,wx.wxDefaultPosition, wx.wxDefaultSize,
										  wx.wxBORDER_STATIC)
bottomnotebook:AddPage(errorLog, "Output", true)

local shellbox = wx.wxPanel(bottomnotebook,wx.wxID_ANY)
shellbox.output = wxstc.wxStyledTextCtrl(shellbox, ID "shellbox.output")
shellbox.input = wxstc.wxStyledTextCtrl(shellbox, ID "shellbox.input")
shellbox.run = wx.wxButton(shellbox, ID "shellbox.run", "Run")
local vsizer = wx.wxFlexGridSizer(1, 0, 0, 0)
vsizer:AddGrowableCol(0)
vsizer:AddGrowableRow(0)
vsizer:Add(shellbox.input, 0, wx.wxGROW+wx.wxALIGN_CENTER_HORIZONTAL, 0 )
vsizer:Add(shellbox.run, 0, wx.wxGROW+wx.wxALIGN_CENTER_HORIZONTAL, 0 )

local gridsizer = wx.wxFlexGridSizer(0, 1, 0, 0)
gridsizer:AddGrowableCol(0)
gridsizer:AddGrowableRow(0)
gridsizer:Add(shellbox.output, 0, wx.wxGROW+wx.wxALIGN_CENTER_HORIZONTAL, 0 )
gridsizer:Add(vsizer, 0, wx.wxGROW+wx.wxALIGN_CENTER_HORIZONTAL, 0 )
shellbox:SetSizer(gridsizer)



bottomnotebook:AddPage(shellbox, "Lua shell",false)
ide.shellbox = shellbox

splitter:Initialize(notebook) -- split later to show errorLog




-------
-- hierarchy

splitter.errorLog = errorLog
splitter.bottomnotebook = bottomnotebook
splitter.notebook = notebook

frame.splitter = 	splitter
frame.toolBar = 	toolBar
frame.errorLog = 	errorLog
frame.menuBar = 	menuBar

ide.frame = frame

