VERSION 5.00
Begin VB.UserControl smartCheckBox 
   BackColor       =   &H80000005&
   ClientHeight    =   375
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   2520
   ClipControls    =   0   'False
   BeginProperty Font 
      Name            =   "Tahoma"
      Size            =   8.25
      Charset         =   0
      Weight          =   400
      Underline       =   0   'False
      Italic          =   0   'False
      Strikethrough   =   0   'False
   EndProperty
   MousePointer    =   99  'Custom
   ScaleHeight     =   25
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   168
   ToolboxBitmap   =   "smartCheckBox.ctx":0000
End
Attribute VB_Name = "smartCheckBox"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = True
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
'***************************************************************************
'PhotoDemon Checkbox control
'Copyright 2013-2015 by Tanner Helland
'Created: 28/January/13
'Last updated: 20/October/14
'Last update: move control to new flicker-free painting class
'
'In a surprise to precisely no one, PhotoDemon has some unique needs when it comes to user controls - needs that
' the intrinsic VB controls can't handle.  These range from the obnoxious (lack of an "autosize" property for
' anything but labels) to the critical (no Unicode support).
'
'As such, I've created many of my own UCs for the program.  All are owner-drawn, with the goal of maintaining
' visual fidelity across the program, while also enabling key features like Unicode support.
'
'A few notes on this checkbox replacement, specifically:
'
' 1) The control is no longer autosized based on the current font and caption.  If a caption exceeds the size of the
'     (manually set) width, the font size will be repeatedly reduced until the caption fits.
' 2) High DPI settings are handled automatically, so do not attempt to handle this manually.
' 3) A hand cursor is automatically applied, and clicks on both the button and label are registered properly.
' 4) Coloration is automatically handled by PD's internal theming engine.
' 5) When the control receives focus via keyboard, a special focus rect is drawn.  Focus via mouse is conveyed via text glow.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'This control really only needs one event raised - Click
Public Event Click()

'Flicker-free window painter
Private WithEvents cPainter As pdWindowPainter
Attribute cPainter.VB_VarHelpID = -1

'Retrieve the width and height of a string
Private Declare Function GetTextExtentPoint32 Lib "gdi32" Alias "GetTextExtentPoint32W" (ByVal hDC As Long, ByVal lpStrPointer As Long, ByVal cbString As Long, ByRef lpSize As POINTAPI) As Long

'Retrieve specific metrics on a font (in our case, crucial for aligning the radio button against the font baseline and ascender)
Private Declare Function GetTextMetrics Lib "gdi32" Alias "GetTextMetricsA" (ByVal hDC As Long, ByRef lpMetrics As TEXTMETRIC) As Long
Private Type TEXTMETRIC
    tmHeight As Long
    tmAscent As Long
    tmDescent As Long
    tmInternalLeading As Long
    tmExternalLeading As Long
    tmAveCharWidth As Long
    tmMaxCharWidth As Long
    tmWeight As Long
    tmOverhang As Long
    tmDigitizedAspectX As Long
    tmDigitizedAspectY As Long
    tmFirstChar As Byte
    tmLastChar As Byte
    tmDefaultChar As Byte
    tmBreakChar As Byte
    tmItalic As Byte
    tmUnderlined As Byte
    tmStruckOut As Byte
    tmPitchAndFamily As Byte
    tmCharSet As Byte
End Type

'API technique for drawing a focus rectangle; used only for designer mode (see the Paint method for details)
Private Declare Function DrawFocusRect Lib "user32" (ByVal hDC As Long, lpRect As RECT) As Long

'Previously, we used VB's internal label control to render the text caption.  This is now handled dynamically,
' via a pdFont object.
Private curFont As pdFont

'Mouse input handler
Private WithEvents cMouseEvents As pdInputMouse
Attribute cMouseEvents.VB_VarHelpID = -1

'An StdFont object is used to make IDE font choices persistent; note that we also need it to raise events,
' so we can track when it changes.
Private WithEvents mFont As StdFont
Attribute mFont.VB_VarHelpID = -1

'Current caption string (persistent within the IDE, but must be set at run-time for Unicode languages).  Note that m_Caption
' is the ENGLISH CAPTION ONLY.  A translated caption, if one exists, will be stored in m_TranslatedCaption, after PD's
' central themer invokes the translateCaption function.
Private m_Caption As String
Private m_TranslatedCaption As String

'Current control value
Private m_Value As CheckBoxConstants

'Persistent back buffer, which we manage internally
Private m_BackBuffer As pdDIB

'If the mouse is currently INSIDE the control, this will be set to TRUE
Private m_MouseInsideUC As Boolean

'When the option button receives focus via keyboard (e.g. NOT by mouse events), we draw a focus rect to help orient the user.
Private m_FocusRectActive As Boolean

'Whenever the control is repainted, the clickable rect will be updated to reflect the relevant portion of the control's interior
Private clickableRect As RECT

'Additional helpers for rendering themed and multiline tooltips
Private m_ToolTip As clsToolTip
Private m_ToolString As String

'The Enabled property is a bit unique; see http://msdn.microsoft.com/en-us/library/aa261357%28v=vs.60%29.aspx
Public Property Get Enabled() As Boolean
Attribute Enabled.VB_UserMemId = -514
    Enabled = UserControl.Enabled
End Property

Public Property Let Enabled(ByVal NewValue As Boolean)
    
    UserControl.Enabled = NewValue
    PropertyChanged "Enabled"
    
    'Redraw the control
    redrawBackBuffer
    
End Property

'Font handling is a bit specialized for user controls; see http://msdn.microsoft.com/en-us/library/aa261313%28v=vs.60%29.aspx
Public Property Get Font() As StdFont
Attribute Font.VB_UserMemId = -512
    Set Font = mFont
End Property

Public Property Set Font(mNewFont As StdFont)
    
    With mFont
        .Bold = mNewFont.Bold
        .Italic = mNewFont.Italic
        .Name = mNewFont.Name
        .Size = mNewFont.Size
    End With
    
    'Mirror all settings to our internal curFont object, then recreate it
    If Not curFont Is Nothing Then
        curFont.setFontBold mFont.Bold
        curFont.setFontFace mFont.Name
        curFont.setFontItalic mFont.Italic
        curFont.setFontSize mFont.Size
        curFont.createFontObject
    End If
    
    PropertyChanged "Font"
    
    'Redraw the control to match
    updateControlSize
    
End Property

'The pdWindowPaint class raises this event when the control needs to be redrawn.  The passed coordinates contain the
' rect returned by GetUpdateRect (but with right/bottom measurements pre-converted to width/height).
Private Sub cPainter_PaintWindow(ByVal winLeft As Long, ByVal winTop As Long, ByVal winWidth As Long, ByVal winHeight As Long)

    'Flip the relevant chunk of the buffer to the screen
    BitBlt UserControl.hDC, winLeft, winTop, winWidth, winHeight, m_BackBuffer.getDIBDC, winLeft, winTop, vbSrcCopy
    
End Sub

Private Sub mFont_FontChanged(ByVal PropertyName As String)
    Set UserControl.Font = mFont
End Sub

'To improve responsiveness, MouseDown is used instead of Click
Private Sub cMouseEvents_MouseDownCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)

    If Me.Enabled And isMouseOverClickArea(x, y) Then
        If CBool(Me.Value) Then Me.Value = vbUnchecked Else Me.Value = vbChecked
    End If

End Sub

'When the mouse leaves the UC, we must repaint the caption (as it's no longer hovered)
Private Sub cMouseEvents_MouseLeave(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    
    If m_MouseInsideUC Then
        m_MouseInsideUC = False
        redrawBackBuffer
    End If
    
    'Reset the cursor
    cMouseEvents.setSystemCursor IDC_ARROW
    
End Sub

'When the mouse enters the clickable portion of the UC, we must repaint the caption (to reflect its hovered state)
Private Sub cMouseEvents_MouseMoveCustom(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)

    'If the mouse is over the relevant portion of the user control, display the cursor as clickable
    If isMouseOverClickArea(x, y) Then
        
        cMouseEvents.setSystemCursor IDC_HAND
        
        'Repaint the control as necessary
        If Not m_MouseInsideUC Then
            m_MouseInsideUC = True
            redrawBackBuffer
        End If
    
    Else
    
        cMouseEvents.setSystemCursor IDC_ARROW
        
        'Repaint the control as necessary
        If m_MouseInsideUC Then
            m_MouseInsideUC = False
            redrawBackBuffer
        End If
        
    End If

End Sub

'See if the mouse is over the clickable portion of the control
Private Function isMouseOverClickArea(ByVal mouseX As Single, ByVal mouseY As Single) As Boolean
    
    If Math_Functions.isPointInRect(mouseX, mouseY, clickableRect) Then
        isMouseOverClickArea = True
    Else
        isMouseOverClickArea = False
    End If

End Function

Public Property Get hWnd() As Long
Attribute hWnd.VB_UserMemId = -515
    hWnd = UserControl.hWnd
End Property

'Container hWnd must be exposed for external tooltip handling
Public Property Get containerHwnd() As Long
    containerHwnd = UserControl.containerHwnd
End Property

Public Property Get Value() As CheckBoxConstants
Attribute Value.VB_UserMemId = 0
    Value = m_Value
End Property

Public Property Let Value(ByVal NewValue As CheckBoxConstants)
    
    'Update our internal value tracker
    If m_Value <> NewValue Then
    
        m_Value = NewValue
        PropertyChanged "Value"
        
        'Redraw the control; it's important to do this *before* raising the associated event, to maintain an impression of max responsiveness
        redrawBackBuffer
        
        'Notify the user of the change by raising the CLICK event
        RaiseEvent Click
        
    End If
    
End Property

Public Property Get Caption() As String
Attribute Caption.VB_UserMemId = -518
    Caption = m_Caption
End Property

Public Property Let Caption(ByVal newCaption As String)
    
    m_Caption = newCaption
    PropertyChanged "Caption"
    
    'Captions are a bit strange; because the control is auto-sized, changing the caption requires a full redraw
    updateControlSize
    
End Property

Private Sub UserControl_GotFocus()

    'If the mouse is *not* over the user control, assume focus was set via keyboard
    If Not m_MouseInsideUC Then
        m_FocusRectActive = True
        redrawBackBuffer
    End If

End Sub

Private Sub UserControl_Initialize()
    
    'Initialize the internal font object
    Set curFont = New pdFont
    curFont.setTextAlignment vbLeftJustify
    
    'When not in design mode, initialize a tracker for mouse events
    If g_IsProgramRunning Then
    
        Set cMouseEvents = New pdInputMouse
        cMouseEvents.addInputTracker Me.hWnd, True, True, , True
        cMouseEvents.setSystemCursor IDC_HAND
        
        'Also start a flicker-free window painter
        Set cPainter = New pdWindowPainter
        cPainter.startPainter Me.hWnd
        
    'In design mode, initialize a base theming class, so our paint function doesn't fail
    Else
        Set g_Themer = New pdVisualThemes
    End If
    
    m_MouseInsideUC = False
    m_FocusRectActive = False
    
    'Prepare a font object for use
    Set mFont = New StdFont
    Set UserControl.Font = mFont
    
    'Update the control size parameters at least once
    updateControlSize
                
End Sub

'Set default properties
Private Sub UserControl_InitProperties()
    
    Caption = "caption"
    
    Set mFont = UserControl.Font
    mFont_FontChanged ("")
    
    Value = vbChecked
    
End Sub

'Toggle the control's value upon space keypress
Private Sub UserControl_KeyPress(KeyAscii As Integer)

    If (KeyAscii = vbKeySpace) Then
        If CBool(Me.Value) Then Me.Value = vbUnchecked Else Me.Value = vbChecked
    End If

End Sub

Private Sub UserControl_LostFocus()

    'If a focus rect has been drawn, remove it now
    If (Not m_MouseInsideUC) And m_FocusRectActive Then
        m_FocusRectActive = False
        redrawBackBuffer
    End If

End Sub

'At run-time, painting is handled by PD's pdWindowPainter class.  In the IDE, however, we must rely on VB's internal paint event.
Private Sub UserControl_Paint()
    
    'Provide minimal painting within the designer
    If Not g_IsProgramRunning Then redrawBackBuffer
    
End Sub

Private Sub UserControl_ReadProperties(PropBag As PropertyBag)

    With PropBag
        Caption = .ReadProperty("Caption", "")
        Set Font = .ReadProperty("Font", Ambient.Font)
        Value = .ReadProperty("Value", vbChecked)
    End With

End Sub

'The control dynamically resizes its font to make sure the full caption fits within the control area.
Private Sub UserControl_Resize()
    updateControlSize
End Sub

Private Sub UserControl_Show()

    'When the control is first made visible, remove the control's tooltip property and reassign it to the checkbox
    ' using a custom solution (which allows for linebreaks and theming).  Note that this has the ugly side-effect of
    ' permanently erasing the extender's tooltip, so FOR THIS CONTROL, TOOLTIPS MUST BE SET AT RUN-TIME!
    m_ToolString = Extender.ToolTipText

    If m_ToolString <> "" Then

        Set m_ToolTip = New clsToolTip
        With m_ToolTip

            .Create Me
            .MaxTipWidth = PD_MAX_TOOLTIP_WIDTH
            .AddTool Me, m_ToolString
            Extender.ToolTipText = ""

        End With

    End If
    
End Sub

'Whenever the size of the control changes, we must recalculate some internal rendering metrics.
Private Sub updateControlSize()

    'By adjusting this fontY parameter, we can control the auto-height of a created check box
    Dim fontY As Long
    fontY = 1
    
    'Calculate a precise size for the requested caption.
    Dim captionHeight As Long, txtSize As POINTAPI
    
    If Not m_BackBuffer Is Nothing Then
    
        GetTextExtentPoint32 m_BackBuffer.getDIBDC, StrPtr(m_Caption), Len(m_Caption), txtSize
        captionHeight = txtSize.y
    
    'Failsafe if a Resize event is fired before we've initialized our back buffer DC
    Else
        captionHeight = fixDPI(32)
    End If
    
    'The control's size is pretty simple: an x-offset (for the selection circle), plus the size of the caption itself,
    ' and a one-pixel border around the edges.
    UserControl.Height = (fontY * 4 + captionHeight + 2) * TwipsPerPixelYFix
    
    'Remove our font object from the buffer DC, because we are about to recreate it
    curFont.releaseFromDC
    
    'Reset our back buffer, and reassign the font to it
    Set m_BackBuffer = New pdDIB
    m_BackBuffer.createBlank UserControl.ScaleWidth, UserControl.ScaleHeight, 24
    curFont.attachToDC m_BackBuffer.getDIBDC
    
    'Redraw the control
    redrawBackBuffer
            
End Sub

Private Sub UserControl_WriteProperties(PropBag As PropertyBag)

    'Store all associated properties
    With PropBag
        .WriteProperty "Caption", Caption, "caption"
        .WriteProperty "Value", Value, vbChecked
        .WriteProperty "Font", mFont, "Tahoma"
    End With
    
End Sub

'External functions can call this to request a redraw.  This is helpful for live-updating theme settings, as in the Preferences dialog.
Public Sub updateAgainstCurrentTheme()
    
    Me.Font.Name = g_InterfaceFont
    curFont.setFontFace g_InterfaceFont
    curFont.createFontObject
    
    'Redraw the control to match
    updateControlSize
    
End Sub

'External functions must call this if a caption translation is required.
Public Sub translateCaption()
    
    Dim newCaption As String
    
    'Translations are active.  Retrieve a translated caption, and make sure it fits within the control.
    If g_Language.translationActive Then
    
        'Only proceed if our caption requires translation (e.g. it's non-null and non-numeric)
        If (Len(Trim(m_Caption)) <> 0) And (Not IsNumeric(m_Caption)) Then
    
            'Retrieve the translated text
            newCaption = g_Language.TranslateMessage(m_Caption)
            
            'Check the size of the translated text, using the current font settings
            Dim fullControlWidth As Long
            fullControlWidth = getCheckboxPlusCaptionWidth(newCaption)
            
            Dim curFontSize As Single
            curFontSize = mFont.Size
            
            'If the size of the caption is wider than the control itself, repeatedly shrink the font size until we
            ' find a size that fits the entire caption.
            Do While (fullControlWidth > UserControl.ScaleWidth - fixDPI(2)) And (curFontSize >= 8)
                
                'Shrink the font size
                curFontSize = curFontSize - 0.25
                curFont.setFontSize curFontSize
                
                 'Recreate the font object
                curFont.releaseFromDC
                curFont.createFontObject
                curFont.attachToDC m_BackBuffer.getDIBDC
                
                'Calculate a new width
                fullControlWidth = getCheckboxPlusCaptionWidth(newCaption)
            
            Loop
            
        Else
            newCaption = ""
        End If
    
    'If translations are not active, skip this step entirely
    Else
        newCaption = ""
    End If
    
    'Redraw the control if the caption has changed
    If StrComp(newCaption, m_TranslatedCaption, vbBinaryCompare) <> 0 Then
        
        m_TranslatedCaption = newCaption
        redrawBackBuffer
        
    End If
    
End Sub

'Use this function to completely redraw the back buffer from scratch.  Note that this is computationally expensive compared to just flipping the
' existing buffer to the screen, so only redraw the backbuffer if the control state has somehow changed.
Private Sub redrawBackBuffer()

    'Start by erasing the back buffer
    If g_IsProgramRunning Then
        GDI_Plus.GDIPlusFillDIBRect m_BackBuffer, 0, 0, m_BackBuffer.getDIBWidth, m_BackBuffer.getDIBHeight, g_Themer.getThemeColor(PDTC_BACKGROUND_DEFAULT), 255
    Else
        m_BackBuffer.createBlank m_BackBuffer.getDIBWidth, m_BackBuffer.getDIBHeight, 24, RGB(255, 255, 255)
        curFont.attachToDC m_BackBuffer.getDIBDC
    End If
    
    'Colors used throughout this paint function are determined primarily control enablement
    Dim chkBoxColorBorder As Long, chkBoxColorFill As Long
    If Me.Enabled Then
        chkBoxColorBorder = g_Themer.getThemeColor(PDTC_GRAY_DEFAULT)
        chkBoxColorFill = g_Themer.getThemeColor(PDTC_ACCENT_SHADOW)
    Else
        chkBoxColorBorder = g_Themer.getThemeColor(PDTC_DISABLED)
        chkBoxColorFill = g_Themer.getThemeColor(PDTC_DISABLED)
    End If
    
    'Next, determine the precise size of our caption, including all internal metrics.  (We need those so we can properly
    ' align the check box with the baseline of the font and the caps (not ascender!) height.
    Dim captionWidth As Long, captionHeight As Long
    captionWidth = curFont.getWidthOfString(m_Caption)
    captionHeight = curFont.getHeightOfString(m_Caption)
    
    'Retrieve the descent of the current font.
    Dim fontDescent As Long, fontMetrics As TEXTMETRIC
    GetTextMetrics m_BackBuffer.getDIBDC, fontMetrics
    fontDescent = fontMetrics.tmDescent
    
    'From the precise font metrics, determine a check box offset X and Y, and a check box size.  Note that 1px is manually
    ' added as part of maintaining a 1px border around the user control as a whole.
    Dim offsetX As Long, offsetY As Long, chkBoxSize As Long
    offsetX = 1 + fixDPI(2)
    offsetY = fontMetrics.tmInternalLeading + 1
    chkBoxSize = captionHeight - fontDescent
    chkBoxSize = chkBoxSize - fontMetrics.tmInternalLeading
    chkBoxSize = chkBoxSize + 1
    
    'Because GDI+ is finicky with antialiasing on odd-numbered sizes, force the size to the nearest even number
    If chkBoxSize Mod 2 = 1 Then
        chkBoxSize = chkBoxSize + 1
        offsetY = offsetY - 1
    End If
    
    'Draw a border for the checkbox regardless of value state
    GDI_Plus.GDIPlusDrawRectOutlineToDC m_BackBuffer.getDIBDC, offsetX, offsetY, offsetX + chkBoxSize, offsetY + chkBoxSize, chkBoxColorBorder, 255, 1
    
    'If the check box button is checked, draw a checkmark inside the border
    If CBool(m_Value) Then
        GDI_Plus.GDIPlusDrawLineToDC m_BackBuffer.getDIBDC, offsetX + 2, offsetY + (chkBoxSize \ 2), offsetX + (chkBoxSize \ 2) - 1.5, offsetY + chkBoxSize - 2.5, chkBoxColorFill, 255, fixDPI(2), True, LineCapRound
        GDI_Plus.GDIPlusDrawLineToDC m_BackBuffer.getDIBDC, offsetX + (chkBoxSize \ 2) - 1, (offsetY + chkBoxSize) - 3, (offsetX + chkBoxSize) - 2, offsetY + 2, chkBoxColorFill, 255, fixDPI(2), True, LineCapRound
    End If
    
    'Set the text color according to the mouse position, e.g. highlight the text if the mouse is over it
    If Me.Enabled Then
    
        If m_MouseInsideUC Then
            curFont.setFontColor g_Themer.getThemeColor(PDTC_TEXT_HYPERLINK)
        Else
            curFont.setFontColor g_Themer.getThemeColor(PDTC_TEXT_DEFAULT)
        End If
        
    Else
        curFont.setFontColor g_Themer.getThemeColor(PDTC_DISABLED)
    End If
    
    'Failsafe check for designer mode
    If Not g_IsProgramRunning Then
        curFont.setFontColor RGB(0, 0, 0)
    End If
    
    'Render the text
    If Len(m_TranslatedCaption) <> 0 Then
        curFont.fastRenderText offsetX * 2 + chkBoxSize + fixDPI(6), 1, m_TranslatedCaption
    Else
        curFont.fastRenderText offsetX * 2 + chkBoxSize + fixDPI(6), 1, m_Caption
    End If
    
    'Update the clickable rect using the measurements from the final render
    With clickableRect
        .Left = 0
        .Top = 0
        If Len(m_TranslatedCaption) <> 0 Then
            .Right = offsetX * 2 + chkBoxSize + fixDPI(6) + curFont.getWidthOfString(m_TranslatedCaption) + fixDPI(6)
        Else
            .Right = offsetX * 2 + chkBoxSize + fixDPI(6) + curFont.getWidthOfString(m_Caption) + fixDPI(6)
        End If
        .Bottom = m_BackBuffer.getDIBHeight
    End With
    
    'If a focus rect is required (because focus was set via keyboard, not mouse), render it now.
    If m_FocusRectActive And m_MouseInsideUC Then m_FocusRectActive = False
    
    If m_FocusRectActive And Me.Enabled Then
        GDI_Plus.GDIPlusDrawRoundRect m_BackBuffer, 0, 0, clickableRect.Right, m_BackBuffer.getDIBHeight, 3, chkBoxColorFill, True, False
    End If
    
    'In the designer, draw a focus rect around the control; this is minimal feedback required for positioning
    If Not g_IsProgramRunning Then
        
        Dim tmpRect As RECT
        With tmpRect
            .Left = 0
            .Top = 0
            .Right = m_BackBuffer.getDIBWidth
            .Bottom = m_BackBuffer.getDIBHeight
        End With
        
        DrawFocusRect m_BackBuffer.getDIBDC, tmpRect

    End If
    
    'Paint the buffer to the screen
    If g_IsProgramRunning Then cPainter.requestRepaint Else BitBlt UserControl.hDC, 0, 0, m_BackBuffer.getDIBWidth, m_BackBuffer.getDIBHeight, m_BackBuffer.getDIBDC, 0, 0, vbSrcCopy

End Sub

'Estimate the size and offset of the checkbox and caption chunk of the control.  The function allows you to pass an arbitrary caption,
' which it uses to determine auto-shrinking of font size for lengthy translated captions.
Private Function getCheckboxPlusCaptionWidth(Optional ByVal relevantCaption As String = "") As Long

    If Len(relevantCaption) = 0 Then relevantCaption = m_Caption

    'Start by retrieving caption width and height.  (Checkbox size is proportional to these values.)
    Dim captionWidth As Long, captionHeight As Long
    captionWidth = curFont.getWidthOfString(relevantCaption)
    captionHeight = curFont.getHeightOfString(relevantCaption)
    
    'Retrieve exact size metrics of the caption, as rendered in the current font
    Dim fontDescent As Long, fontMetrics As TEXTMETRIC
    GetTextMetrics m_BackBuffer.getDIBDC, fontMetrics
    fontDescent = fontMetrics.tmDescent
    
    'Using the font metrics, determine a check box offset and size.  Note that 1px is manually added as part of maintaining a
    ' 1px border around the user control as a whole (which is used for a focus rect).
    Dim offsetX As Long, offsetY As Long, chkBoxSize As Long
    offsetX = 1 + fixDPI(2)
    offsetY = fontMetrics.tmInternalLeading + 1
    chkBoxSize = captionHeight - fontDescent
    chkBoxSize = chkBoxSize - fontMetrics.tmInternalLeading
    chkBoxSize = chkBoxSize + 1
    
    'Because GDI+ is finicky with antialiasing on odd-numbered sizes, force the size to the nearest even number
    If chkBoxSize Mod 2 = 1 Then
        chkBoxSize = chkBoxSize + 1
        offsetY = offsetY - 1
    End If
    
    'Return the determined check box size, plus a 6px extender to separate it from the caption.
    getCheckboxPlusCaptionWidth = offsetX * 2 + chkBoxSize + fixDPI(6) + captionWidth

End Function


