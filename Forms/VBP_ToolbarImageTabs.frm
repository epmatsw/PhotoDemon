VERSION 5.00
Begin VB.Form toolbar_ImageTabs 
   AutoRedraw      =   -1  'True
   BackColor       =   &H00E0E0E0&
   BorderStyle     =   0  'None
   Caption         =   "Images"
   ClientHeight    =   1140
   ClientLeft      =   0
   ClientTop       =   0
   ClientWidth     =   13710
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
   LinkTopic       =   "Form1"
   MaxButton       =   0   'False
   MinButton       =   0   'False
   NegotiateMenus  =   0   'False
   OLEDropMode     =   1  'Manual
   ScaleHeight     =   76
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   914
   ShowInTaskbar   =   0   'False
   StartUpPosition =   3  'Windows Default
   Begin VB.HScrollBar hsThumbnails 
      Height          =   255
      Left            =   0
      Max             =   10
      TabIndex        =   0
      Top             =   840
      Visible         =   0   'False
      Width           =   13695
   End
End
Attribute VB_Name = "toolbar_ImageTabs"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'PhotoDemon Image Selection ("Tab") Toolbar
'Copyright 2013-2015 by Tanner Helland
'Created: 15/October/13
'Last updated: 31/May/14
'Last update: rewrite all custom mouse code against pdInput
'
'In fall 2013, PhotoDemon left behind the MDI model in favor of fully dockable/floatable tool and image windows.
' This required quite a new features, including a way to switch between loaded images when image windows are docked -
' which is where this form comes in.
'
'The purpose of this form is to provide a tab-like interface for switching between open images.  Please note that
' much of this form's layout and alignment is handled by PhotoDemon's window manager, so you will need to look
' there for detailed information on things like the window's positioning and alignment.
'
'To my knowledge, as of January '14 the tabstrip should work properly under all orientations and screen DPIs.
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://photodemon.org/about/license/
'
'***************************************************************************

Option Explicit

'A collection of all currently active thumbnails; this is dynamically resized as thumbnails are added/removed.
Private Type thumbEntry
    thumbDIB As pdDIB
    thumbShadow As pdDIB
    indexInPDImages As Long
End Type

Private imgThumbnails() As thumbEntry
Private numOfThumbnails As Long

'Because the user can resize the thumbnail bar, we must track thumbnail width/height dynamically
Private thumbWidth As Long, thumbHeight As Long

'We don't want thumbnails to fill the full size of their individual blocks, so we apply a border of this many pixels
' to each side of the thumbnail
Private Const thumbBorder As Long = 5

'The back buffer we use to hold the thumbnail display
Private bufferDIB As pdDIB
Private m_BufferWidth As Long, m_BufferHeight As Long

'An outside class provides access to mousewheel events for scrolling the tabstrip view
Private WithEvents cMouseEvents As pdInputMouse
Attribute cMouseEvents.VB_VarHelpID = -1

'The currently selected and currently hovered thumbnail
Private curThumb As Long, curThumbHover As Long

'When we are responsible for this window resizing (because the user is resizing our window manually), we set this to TRUE.
' This variable is then checked before requesting additional redraws during our resize event.
Private weAreResponsibleForResize As Boolean

'As a convenience to the user, we provide a small notification when an image has unsaved changes
Private unsavedChangesDIB As pdDIB

'Drop-shadows on the thumbnails have a variable radius that changes based on the user's DPI settings
Private shadowBlurRadius As Long

'Custom tooltip class allows for things like multiline, theming, and multiple monitor support
Dim m_ToolTip As clsToolTip

'If the user loads tons of images, the tabstrip may overflow the available area.  We now allow them to drag-scroll the list.
' In order to allow that, we must track a few extra things, like initial mouse x/y
Private m_MouseDown As Boolean, m_ScrollingOccured As Boolean
Private m_InitX As Long, m_InitY As Long, m_InitOffset As Long
Private m_ListScrollable As Boolean
Private m_MouseDistanceTraveled As Long

'Horizontal or vertical layout; obviously, all our rendering and mouse detection code changes depending on the orientation
' of the tabstrip.
Private verticalLayout As Boolean

'External functions can force a full redraw by calling this sub
Public Sub forceRedraw()
    Form_Resize
End Sub

'When the user switches images, redraw the toolbar to match the change
Public Sub notifyNewActiveImage(ByVal newPDImageIndex As Long)
    
    'Find the matching thumbnail entry, and mark it as active
    Dim i As Long
    For i = 0 To numOfThumbnails
        If imgThumbnails(i).indexInPDImages = newPDImageIndex Then
            curThumb = i
            Exit For
        Else
            curThumb = 0
        End If
    Next i
    
    'Redraw the toolbar to reflect the change
    redrawToolbar True
        
End Sub

'Returns TRUE is a given thumbnail is currently viewable in its entirety; FALSE if it lies partially or fully off-screen.
Public Function fitThumbnailOnscreen(ByVal thumbIndex As Long) As Boolean

    Dim isThumbnailOnscreen As Boolean

    'First, figure out where the thumbnail actually sits.
    
    'Determine a scrollbar offset as necessary
    Dim scrollOffset As Long
    scrollOffset = hsThumbnails.Value
    
    'Per the tabstrip's current alignment, figure out a relevant position
    Dim hPosition As Long, vPosition As Long
    
    If verticalLayout Then
        hPosition = 0
        vPosition = (thumbIndex * thumbHeight) - scrollOffset
    Else
        hPosition = (thumbIndex * thumbWidth) - scrollOffset
        vPosition = 0
    End If
    
    'Use the tabstrip's size to determine if this thumbnail lies off-screen
    If verticalLayout Then
        
        If vPosition < 0 Or (vPosition + thumbHeight - 1) > Me.ScaleHeight Then
            isThumbnailOnscreen = False
        Else
            isThumbnailOnscreen = True
        End If
        
    Else
    
        If hPosition < 0 Or (hPosition + thumbWidth - 1) > Me.ScaleWidth Then
            isThumbnailOnscreen = False
        Else
            isThumbnailOnscreen = True
        End If
        
    End If
    
    'If the thumbnail is not onscreen, make it so!
    If Not isThumbnailOnscreen Then
    
        If verticalLayout Then
        
            If vPosition < 0 Then
                hsThumbnails.Value = thumbIndex * thumbHeight
            Else
            
                If ((thumbIndex + 1) * thumbHeight) - Me.ScaleHeight > hsThumbnails.Max Then
                    hsThumbnails.Value = hsThumbnails.Max
                Else
                    hsThumbnails.Value = ((thumbIndex + 1) * thumbHeight) - Me.ScaleHeight
                End If
                
            End If
            
        Else
        
            If hPosition < 0 Then
                hsThumbnails.Value = thumbIndex * thumbWidth
            Else
            
                If ((thumbIndex + 1) * thumbWidth) - Me.ScaleWidth > hsThumbnails.Max Then
                    hsThumbnails.Value = hsThumbnails.Max
                Else
                    hsThumbnails.Value = ((thumbIndex + 1) * thumbWidth) - Me.ScaleWidth
                End If
                
            End If
            
        End If
    
    End If
            
End Function

'When the user somehow changes an image, they need to notify the toolbar, so that a new thumbnail can be rendered
Public Sub notifyUpdatedImage(ByVal pdImagesIndex As Long)
    
    'Find the matching thumbnail entry, and update its thumbnail DIB
    Dim i As Long
    For i = 0 To numOfThumbnails
        If imgThumbnails(i).indexInPDImages = pdImagesIndex Then
            
            If Not (pdImages(pdImagesIndex) Is Nothing) Then
            
                If verticalLayout Then
                    pdImages(pdImagesIndex).requestThumbnail imgThumbnails(i).thumbDIB, thumbHeight - (fixDPI(thumbBorder) * 2)
                Else
                    pdImages(pdImagesIndex).requestThumbnail imgThumbnails(i).thumbDIB, thumbWidth - (fixDPI(thumbBorder) * 2)
                End If
                
            End If
            
            If g_InterfacePerformance <> PD_PERF_FASTEST Then updateShadowDIB i
            Exit For
        End If
    Next i
    
    'Redraw the toolbar to reflect the change
    redrawToolbar
        
End Sub

'Whenever a new image is loaded, it needs to be registered with the toolbar
Public Sub registerNewImage(ByVal pdImagesIndex As Long)

    'Request a thumbnail from the relevant pdImage object, and premultiply it to allow us to blit it more quickly
    Set imgThumbnails(numOfThumbnails).thumbDIB = New pdDIB
    
    If verticalLayout Then
        pdImages(pdImagesIndex).requestThumbnail imgThumbnails(numOfThumbnails).thumbDIB, thumbHeight - (fixDPI(thumbBorder) * 2)
    Else
        pdImages(pdImagesIndex).requestThumbnail imgThumbnails(numOfThumbnails).thumbDIB, thumbWidth - (fixDPI(thumbBorder) * 2)
    End If
    
    'Create a matching shadow DIB
    Set imgThumbnails(numOfThumbnails).thumbShadow = New pdDIB
    If g_InterfacePerformance <> PD_PERF_FASTEST Then updateShadowDIB numOfThumbnails
    
    'Make a note of this thumbnail's index in the main pdImages array
    imgThumbnails(numOfThumbnails).indexInPDImages = pdImagesIndex
    
    'We can assume this image will be the active one
    curThumb = numOfThumbnails
    
    'Prepare the array to receive another entry in the future
    numOfThumbnails = numOfThumbnails + 1
    ReDim Preserve imgThumbnails(0 To numOfThumbnails) As thumbEntry
    
    'Redraw the toolbar to reflect these changes
    redrawToolbar True
    
End Sub

'Whenever an image is unloaded, it needs to be de-registered with the toolbar
Public Sub RemoveImage(ByVal pdImagesIndex As Long, Optional ByVal refreshToolbar As Boolean = True)

    'Find the matching thumbnail in our collection
    Dim i As Long, thumbIndex As Long
    thumbIndex = -1
    
    For i = 0 To numOfThumbnails
        If imgThumbnails(i).indexInPDImages = pdImagesIndex Then
            thumbIndex = i
            Exit For
        End If
    Next i
    
    'thumbIndex is now equal to the matching thumbnail.  Remove that entry, then shift all thumbnails after that point down.
    If (thumbIndex > -1) And (thumbIndex <= UBound(imgThumbnails)) Then
    
        If Not (imgThumbnails(thumbIndex).thumbDIB Is Nothing) Then
            imgThumbnails(thumbIndex).thumbDIB.eraseDIB
            Set imgThumbnails(thumbIndex).thumbDIB = Nothing
        End If
        
        If Not (imgThumbnails(thumbIndex).thumbShadow Is Nothing) Then
            imgThumbnails(thumbIndex).thumbShadow.eraseDIB
            Set imgThumbnails(thumbIndex).thumbShadow = Nothing
        End If
        
        For i = thumbIndex To numOfThumbnails - 1
            Set imgThumbnails(i).thumbDIB = imgThumbnails(i + 1).thumbDIB
            Set imgThumbnails(i).thumbShadow = imgThumbnails(i + 1).thumbShadow
            imgThumbnails(i).indexInPDImages = imgThumbnails(i + 1).indexInPDImages
        Next i
        
        'Decrease the array size to erase the unneeded trailing entry
        numOfThumbnails = numOfThumbnails - 1
    
        If numOfThumbnails < 0 Then
            numOfThumbnails = 0
            curThumb = 0
        End If
        
        ReDim Preserve imgThumbnails(0 To numOfThumbnails) As thumbEntry
        
    End If
    
    'Because inactive images can be unloaded via the Win 7 taskbar, it is possible for our curThumb tracker to get out of sync.
    ' Update it now.
    For i = 0 To numOfThumbnails
        If imgThumbnails(i).indexInPDImages = g_CurrentImage Then
            curThumb = i
            Exit For
        Else
            curThumb = 0
        End If
    Next i
    
    'Redraw the toolbar to reflect these changes
    If refreshToolbar Then redrawToolbar

End Sub

'Given mouse coordinates over the form, return the thumbnail at that location.  If the cursor is not over a thumbnail,
' the function will return -1
Private Function getThumbAtPosition(ByVal x As Long, ByVal y As Long) As Long
    
    Dim thumbOffset As Long
    thumbOffset = hsThumbnails.Value
    
    If verticalLayout Then
        getThumbAtPosition = (y + thumbOffset) \ thumbHeight
        If getThumbAtPosition > (numOfThumbnails - 1) Then getThumbAtPosition = -1
    Else
        getThumbAtPosition = (x + thumbOffset) \ thumbWidth
        If getThumbAtPosition > (numOfThumbnails - 1) Then getThumbAtPosition = -1
    End If
    
End Function

Private Sub cMouseEvents_MouseEnter(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)
    g_MouseOverImageTabstrip = True
End Sub

Private Sub cMouseEvents_MouseLeave(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long)

    g_MouseOverImageTabstrip = False
    
    If curThumbHover <> -1 Then
        curThumbHover = -1
        redrawToolbar
    End If
    
    cMouseEvents.setSystemCursor IDC_ARROW

End Sub

Public Sub cMouseEvents_MouseWheelHorizontal(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long, ByVal scrollAmount As Double)

    'Horizontal scrolling - only trigger it if the horizontal scroll bar is actually visible
    If m_ListScrollable Then
  
        If scrollAmount > 0 Then
            
            If hsThumbnails.Value + hsThumbnails.LargeChange > hsThumbnails.Max Then
                hsThumbnails.Value = hsThumbnails.Max
            Else
                hsThumbnails.Value = hsThumbnails.Value + hsThumbnails.LargeChange
            End If
            
            curThumbHover = getThumbAtPosition(x, y)
            redrawToolbar
        
        ElseIf scrollAmount < 0 Then
            
            If hsThumbnails.Value - hsThumbnails.LargeChange < hsThumbnails.Min Then
                hsThumbnails.Value = hsThumbnails.Min
            Else
                hsThumbnails.Value = hsThumbnails.Value - hsThumbnails.LargeChange
            End If
            
            curThumbHover = getThumbAtPosition(x, y)
            redrawToolbar
            
        End If
        
    End If

End Sub

Public Sub cMouseEvents_MouseWheelVertical(ByVal Button As PDMouseButtonConstants, ByVal Shift As ShiftConstants, ByVal x As Long, ByVal y As Long, ByVal scrollAmount As Double)

    'Vertical scrolling - only trigger it if the horizontal scroll bar is actually visible
    If m_ListScrollable Then
  
        If scrollAmount < 0 Then
            
            If hsThumbnails.Value + hsThumbnails.LargeChange > hsThumbnails.Max Then
                hsThumbnails.Value = hsThumbnails.Max
            Else
                hsThumbnails.Value = hsThumbnails.Value + hsThumbnails.LargeChange
            End If
            
            curThumbHover = getThumbAtPosition(x, y)
            redrawToolbar
        
        ElseIf scrollAmount > 0 Then
            
            If hsThumbnails.Value - hsThumbnails.LargeChange < hsThumbnails.Min Then
                hsThumbnails.Value = hsThumbnails.Min
            Else
                hsThumbnails.Value = hsThumbnails.Value - hsThumbnails.LargeChange
            End If
            
            curThumbHover = getThumbAtPosition(x, y)
            redrawToolbar
            
        End If
        
    End If

End Sub

Private Sub Form_Load()

    'Initialize the back buffer
    Set bufferDIB = New pdDIB

    'Reset the thumbnail array
    numOfThumbnails = 0
    ReDim imgThumbnails(0 To numOfThumbnails) As thumbEntry
    
    'Enable mousewheel scrolling
    Set cMouseEvents = New pdInputMouse
    cMouseEvents.addInputTracker Me.hWnd, True, , , True
    cMouseEvents.setSystemCursor IDC_HAND
    
    'Detect initial alignment
    If (g_WindowManager.getImageTabstripAlignment = vbAlignLeft) Or (g_WindowManager.getImageTabstripAlignment = vbAlignRight) Then
        verticalLayout = True
    Else
        verticalLayout = False
    End If
    
    'Set default thumbnail sizes
    If verticalLayout Then
        thumbWidth = g_WindowManager.getClientWidth(Me.hWnd)
        thumbHeight = thumbWidth
    Else
        thumbHeight = g_WindowManager.getClientHeight(Me.hWnd)
        thumbWidth = thumbHeight
    End If
    
    'Compensate for the presence of the 2px border along the edge of the tabstrip
    thumbWidth = thumbWidth - 2
    thumbHeight = thumbHeight - 2
    
    'Retrieve the unsaved image notification icon from the resource file
    Set unsavedChangesDIB = New pdDIB
    loadResourceToDIB "NTFY_UNSAVED", unsavedChangesDIB
    
    'Update the drop-shadow blur radius to account for DPI
    shadowBlurRadius = fixDPI(2)
    
    'If the tabstrip ever becomes long enough to scroll, this will be set to TRUE
    m_ListScrollable = False
    
    'Activate the custom tooltip handler
    Set m_ToolTip = New clsToolTip
    m_ToolTip.Create Me
    m_ToolTip.MaxTipWidth = PD_MAX_TOOLTIP_WIDTH
    m_ToolTip.DelayTime(ttDelayShow) = 10000
    m_ToolTip.AddTool Me, ""
    
    'Theme the form
    makeFormPretty Me
    
End Sub

'When the left mouse button is pressed, activate click-to-drag mode for scrolling the tabstrip window
Private Sub Form_MouseDown(Button As Integer, Shift As Integer, x As Single, y As Single)
    
    'Make a note of the initial mouse position
    If Button = vbLeftButton Then
        m_MouseDown = True
        m_InitX = x
        m_InitY = y
        m_MouseDistanceTraveled = 0
        m_InitOffset = hsThumbnails.Value
    End If
    
    'Reset the "resize in progress" tracker
    weAreResponsibleForResize = False
    
    'Reset the "scrolling occured" tracker
    m_ScrollingOccured = False
    
End Sub

Private Sub Form_MouseMove(Button As Integer, Shift As Integer, x As Single, y As Single)
    
    'Note that the mouse is currently over the tabstrip
    g_MouseOverImageTabstrip = True
    
    'We require a few mouse movements to fire before doing anything; otherwise this function will fire constantly.
    m_MouseDistanceTraveled = m_MouseDistanceTraveled + 1
    
    'We handle several different _MouseMove scenarios, in this order:
    ' 1) If the mouse is near the resizable edge of the form, and the left button is depressed, activate live resizing.
    ' 2) If a button is depressed, activate tabstrip scrolling (if the list is long enough)
    ' 3) If no buttons are depressed, hover the image at the current position (if any)
    
    'If the mouse is near the resizable edge of the toolbar (which varies according to its alignment),
    ' allow the user to resize the thumbnail toolbar
    Dim mouseInResizeTerritory As Boolean
    
    'How close does the mouse have to be to the form border to allow resizing; currently we use 7 pixels, while accounting
    ' for DPI variance (e.g. 7 pixels at 96 dpi)
    Dim resizeBorderAllowance As Long
    resizeBorderAllowance = fixDPI(7)
    
    Dim hitCode As Long
    
    Select Case g_WindowManager.getImageTabstripAlignment
    
        Case vbAlignLeft
            If (y > 0) And (y < Me.ScaleHeight) And (x > Me.ScaleWidth - resizeBorderAllowance) Then mouseInResizeTerritory = True
            hitCode = HTRIGHT
        
        Case vbAlignTop
            If (x > 0) And (x < Me.ScaleWidth) And (y > Me.ScaleHeight - resizeBorderAllowance) Then mouseInResizeTerritory = True
            hitCode = HTBOTTOM
        
        Case vbAlignRight
            If (y > 0) And (y < Me.ScaleHeight) And (x < resizeBorderAllowance) Then mouseInResizeTerritory = True
            hitCode = HTLEFT
        
        Case vbAlignBottom
            If (x > 0) And (x < Me.ScaleWidth) And (y < resizeBorderAllowance) Then mouseInResizeTerritory = True
            hitCode = HTTOP
    
    End Select
        
    'Check mouse button state; if it's down, check for resize or scrolling of the image list
    If m_MouseDown Then
        
        If mouseInResizeTerritory Then
                
            If Button = vbLeftButton Then
                
                'Allow resizing
                weAreResponsibleForResize = True
                ReleaseCapture
                SendMessage Me.hWnd, WM_NCLBUTTONDOWN, hitCode, ByVal 0&
                
            End If
        
        'The mouse is not in resize territory.
        Else
        
            mouseInResizeTerritory = False
            
            'If the list is scrollable (due to tons of images being loaded), calculate a new offset now
            If m_ListScrollable And (m_MouseDistanceTraveled > 5) And (Not weAreResponsibleForResize) Then
            
                m_ScrollingOccured = True
            
                Dim mouseOffset As Long
                
                If verticalLayout Then
                    mouseOffset = (m_InitY - y)
                Else
                    mouseOffset = (m_InitX - x)
                End If
                
                'Change the invisible scroll bar to match the new offset
                Dim newScrollValue As Long
                newScrollValue = m_InitOffset + mouseOffset
                
                If newScrollValue < 0 Then
                    hsThumbnails.Value = 0
                
                ElseIf newScrollValue > hsThumbnails.Max Then
                    hsThumbnails.Value = hsThumbnails.Max
                    
                Else
                    hsThumbnails.Value = newScrollValue
                    
                End If
                
            
            End If
        
        End If
    
    'The left mouse button is not down.  Hover the image beneath the cursor (if any)
    Else
    
        Dim oldThumbHover As Long
        oldThumbHover = curThumbHover
        
        'Retrieve the thumbnail at this position, and change the mouse pointer accordingly
        curThumbHover = getThumbAtPosition(x, y)
        
        'To prevent flickering, only update the tooltip when absolutely necessary
        If curThumbHover <> oldThumbHover Then
        
            'If the cursor is over a thumbnail, update the tooltip to display that image's filename
            If curThumbHover <> -1 Then
                        
                If Len(pdImages(imgThumbnails(curThumbHover).indexInPDImages).locationOnDisk) <> 0 Then
                    m_ToolTip.ToolTipHeader = pdImages(imgThumbnails(curThumbHover).indexInPDImages).originalFileNameAndExtension
                    m_ToolTip.ToolText(Me) = pdImages(imgThumbnails(curThumbHover).indexInPDImages).locationOnDisk
                Else
                    m_ToolTip.ToolTipHeader = g_Language.TranslateMessage("This image does not have a filename.")
                    m_ToolTip.ToolText(Me) = g_Language.TranslateMessage("Once this image has been saved to disk, its filename will appear here.")
                End If
            
            'The cursor is not over a thumbnail; let the user know they can hover if they want more information.
            Else
            
                m_ToolTip.ToolTipHeader = ""
                m_ToolTip.ToolText(Me) = "Hover an image thumbnail to see its name and current file location."
            
            End If
            
        End If
        
    End If
    
    'Set a mouse pointer according to the handling above
    If mouseInResizeTerritory Then
    
        If verticalLayout Then
            cMouseEvents.setSystemCursor IDC_SIZEWE
        Else
            cMouseEvents.setSystemCursor IDC_SIZENS
        End If
            
    Else
    
        'Display a hand cursor if over an image
        If curThumbHover = -1 Then cMouseEvents.setSystemCursor IDC_ARROW Else cMouseEvents.setSystemCursor IDC_HAND
    
    End If
    
    'Regardless of what happened above, redraw the toolbar to reflect any changes
    redrawToolbar
    
End Sub

Private Sub Form_MouseUp(Button As Integer, Shift As Integer, x As Single, y As Single)

    'If the _MouseUp event was triggered by the user, select the image at that position
    If Not weAreResponsibleForResize Then
    
        Dim potentialNewThumb As Long
        potentialNewThumb = getThumbAtPosition(x, y)
        
        'Notify the program that a new image has been selected; it will then bring that image to the foreground,
        ' which will automatically trigger a toolbar redraw.  Also, do not select the image if the user has been
        ' scrolling the list.
        If (potentialNewThumb >= 0) And (Not m_ScrollingOccured) Then
            curThumb = potentialNewThumb
            activatePDImage imgThumbnails(curThumb).indexInPDImages, "user clicked image thumbnail"
        End If
        
    End If
    
    'Release mouse tracking
    If m_MouseDown Then
        m_MouseDown = False
        m_InitX = 0
        m_InitY = 0
        m_MouseDistanceTraveled = 0
    End If

End Sub

'(This code is copied from FormMain's OLEDragDrop event - please mirror any changes there)
Private Sub Form_OLEDragDrop(Data As DataObject, Effect As Long, Button As Integer, Shift As Integer, x As Single, y As Single)

    'Make sure the form is available (e.g. a modal form hasn't stolen focus)
    If Not g_AllowDragAndDrop Then Exit Sub
    
    'Use the external function (in the clipboard handler, as the code is roughly identical to clipboard pasting)
    ' to load the OLE source.
    Clipboard_Handler.loadImageFromDragDrop Data, Effect, False

End Sub

'(This code is copied from FormMain's OLEDragOver event - please mirror any changes there)
Private Sub Form_OLEDragOver(Data As DataObject, Effect As Long, Button As Integer, Shift As Integer, x As Single, y As Single, State As Integer)

    'Make sure the form is available (e.g. a modal form hasn't stolen focus)
    If Not g_AllowDragAndDrop Then Exit Sub

    'Check to make sure the type of OLE object is files
    If Data.GetFormat(vbCFFiles) Or Data.GetFormat(vbCFText) Then
        'Inform the source that the files will be treated as "copied"
        Effect = vbDropEffectCopy And Effect
    Else
        'If it's not files or text, don't allow a drop
        Effect = vbDropEffectNone
    End If

End Sub

'Any time this window is resized, we need to recreate the thumbnail display
Private Sub Form_Resize()

    'Detect alignment changes (if any)
    If (g_WindowManager.getImageTabstripAlignment = vbAlignLeft) Or (g_WindowManager.getImageTabstripAlignment = vbAlignRight) Then
        verticalLayout = True
    Else
        verticalLayout = False
    End If

    Dim i As Long

    'If the tabstrip is horizontal and the window's height is changing, we need to recreate all image thumbnails
    If ((Not verticalLayout) And (thumbHeight <> g_WindowManager.getClientHeight(Me.hWnd) - 2)) Then
        
        thumbHeight = g_WindowManager.getClientHeight(Me.hWnd) - 2
    
        For i = 0 To numOfThumbnails - 1
            imgThumbnails(i).thumbDIB.eraseDIB
            pdImages(imgThumbnails(i).indexInPDImages).requestThumbnail imgThumbnails(i).thumbDIB, thumbHeight - (fixDPI(thumbBorder) * 2)
            If g_InterfacePerformance <> PD_PERF_FASTEST Then updateShadowDIB i
        Next i
    
    End If
    
    'If the tabstrip is vertical and the window's with is changing, we need to recreate all image thumbnails
    If (verticalLayout And (thumbWidth <> g_WindowManager.getClientWidth(Me.hWnd) - 2)) Then
    
        thumbWidth = g_WindowManager.getClientWidth(Me.hWnd) - 2
        
        For i = 0 To numOfThumbnails - 1
            imgThumbnails(i).thumbDIB.eraseDIB
            pdImages(imgThumbnails(i).indexInPDImages).requestThumbnail imgThumbnails(i).thumbDIB, thumbWidth - (fixDPI(thumbBorder) * 2)
            If g_InterfacePerformance <> PD_PERF_FASTEST Then updateShadowDIB i
        Next i
    
    End If
    
    'Update thumbnail sizes
    If verticalLayout Then
        thumbWidth = g_WindowManager.getClientWidth(Me.hWnd) - 2
        thumbHeight = thumbWidth
    Else
        thumbHeight = g_WindowManager.getClientHeight(Me.hWnd) - 2
        thumbWidth = thumbHeight
    End If
        
    'Create a background buffer the same size as this window
    m_BufferWidth = g_WindowManager.getClientWidth(Me.hWnd)
    m_BufferHeight = g_WindowManager.getClientHeight(Me.hWnd)
    
    'Redraw the toolbar
    redrawToolbar
    
    'Notify the window manager that the tab strip has been resized; it will resize image windows to match
    'If Not weAreResponsibleForResize Then
    g_WindowManager.notifyImageTabStripResized
    
End Sub

Private Sub Form_Unload(Cancel As Integer)
    ReleaseFormTheming Me
    g_WindowManager.unregisterForm Me
    Set cMouseEvents = Nothing
End Sub

'Whenever a function wants to render the current toolbar, it may do so here
Private Sub redrawToolbar(Optional ByVal fitCurrentThumbOnScreen As Boolean = False)

    'Recreate the toolbar buffer
    bufferDIB.createBlank m_BufferWidth, m_BufferHeight, 24, ConvertSystemColor(vb3DShadow)
    
    If numOfThumbnails > 0 Then
        
        'Horizontal/vertical layout changes the constraining dimension (e.g. the dimension used to detect if the number
        ' of image tabs currently visible is long enough that it needs to be scrollable).
        Dim constrainingDimension As Long, constrainingMax As Long
        If verticalLayout Then
            constrainingDimension = thumbHeight
            constrainingMax = m_BufferHeight
        Else
            constrainingDimension = thumbWidth
            constrainingMax = m_BufferWidth
        End If
        
        'Determine if the scrollbar needs to be accounted for or not
        Dim maxThumbSize As Long
        maxThumbSize = constrainingDimension * numOfThumbnails - 1
        
        If maxThumbSize < constrainingMax Then
            hsThumbnails.Value = 0
            m_ListScrollable = False
        Else
            m_ListScrollable = True
            hsThumbnails.Max = maxThumbSize - constrainingMax
            
            'Dynamically set the scrollbar's LargeChange value relevant to thumbnail size
            Dim lChange As Long
            
            lChange = (maxThumbSize - constrainingMax) \ 16
            
            If lChange < 1 Then lChange = 1
            If lChange > thumbWidth \ 4 Then lChange = thumbWidth \ 4
            
            hsThumbnails.LargeChange = lChange
            
            'If requested, fit the currently active thumbnail on-screen
            If fitCurrentThumbOnScreen Then fitThumbnailOnscreen curThumb
            
        End If
        
        'Determine a scrollbar offset as necessary
        Dim scrollOffset As Long
        scrollOffset = hsThumbnails.Value
        
        'Render each thumbnail block
        Dim i As Long
        For i = 0 To numOfThumbnails - 1
            If verticalLayout Then
                If g_WindowManager.getImageTabstripAlignment = vbAlignLeft Then
                    renderThumbTab i, 0, (i * thumbHeight) - scrollOffset
                Else
                    renderThumbTab i, 2, (i * thumbHeight) - scrollOffset
                End If
            Else
                If g_WindowManager.getImageTabstripAlignment = vbAlignTop Then
                    renderThumbTab i, (i * thumbWidth) - scrollOffset, 0
                Else
                    renderThumbTab i, (i * thumbWidth) - scrollOffset, 2
                End If
            End If
        Next i
        
        'Eventually we'll do something nicer, but for now, draw a line across the edge of the tabstrip nearest the image.
        Select Case g_WindowManager.getImageTabstripAlignment
        
            Case vbAlignLeft
                GDIPlusDrawLineToDC bufferDIB.getDIBDC, m_BufferWidth - 1, 0, m_BufferWidth - 1, m_BufferHeight, ConvertSystemColor(vb3DLight), 255, 2, False
            
            Case vbAlignTop
                GDIPlusDrawLineToDC bufferDIB.getDIBDC, 0, m_BufferHeight - 1, m_BufferWidth, m_BufferHeight - 1, ConvertSystemColor(vb3DLight), 255, 2, False
            
            Case vbAlignRight
                GDIPlusDrawLineToDC bufferDIB.getDIBDC, 1, 0, 1, m_BufferHeight, ConvertSystemColor(vb3DLight), 255, 2, False
            
            Case vbAlignBottom
                GDIPlusDrawLineToDC bufferDIB.getDIBDC, 0, 1, m_BufferWidth, 1, ConvertSystemColor(vb3DLight), 255, 2, False
        
        End Select
        
    End If
    
    'Activate color management for our form
    assignDefaultColorProfileToObject Me.hWnd, Me.hDC
    turnOnColorManagementForDC Me.hDC
    
    'Copy the buffer to the form
    BitBlt Me.hDC, 0, 0, m_BufferWidth, m_BufferHeight, bufferDIB.getDIBDC, 0, 0, vbSrcCopy
    Me.Picture = Me.Image
    Me.Refresh
    
End Sub
    
'Render a given thumbnail onto the background form at the specified offset
Private Sub renderThumbTab(ByVal thumbIndex As Long, ByVal offsetX As Long, ByVal offsetY As Long)

    'Only draw the current tab if it will be visible
    Dim tabVisible As Boolean
    tabVisible = False
    
    If verticalLayout Then
        If ((offsetY + thumbHeight) > 0) And (offsetY < m_BufferHeight) Then tabVisible = True
    Else
        If ((offsetX + thumbWidth) > 0) And (offsetX < m_BufferWidth) Then tabVisible = True
    End If
    
    If tabVisible Then
    
        Dim tmpRect As RECTL
        Dim hBrush As Long
    
        'If this thumbnail has been selected, draw the background with the system's current selection color
        If thumbIndex = curThumb Then
            SetRect tmpRect, offsetX, offsetY, offsetX + thumbWidth, offsetY + thumbHeight
            hBrush = CreateSolidBrush(ConvertSystemColor(vb3DLight))
            FillRect bufferDIB.getDIBDC, tmpRect, hBrush
            DeleteObject hBrush
        End If
        
        'If the current thumbnail is highlighted but not selected, simply render the border with a highlight
        If (thumbIndex <> curThumb) And (thumbIndex = curThumbHover) Then
            SetRect tmpRect, offsetX, offsetY, offsetX + thumbWidth, offsetY + thumbHeight
            hBrush = CreateSolidBrush(ConvertSystemColor(vbHighlight))
            FrameRect bufferDIB.getDIBDC, tmpRect, hBrush
            SetRect tmpRect, tmpRect.Left + 1, tmpRect.Top + 1, tmpRect.Right - 1, tmpRect.Bottom - 1
            FrameRect bufferDIB.getDIBDC, tmpRect, hBrush
            DeleteObject hBrush
        End If
    
        'Render the matching thumbnail shadow and thumbnail into this block
        If g_InterfacePerformance <> PD_PERF_FASTEST Then imgThumbnails(thumbIndex).thumbShadow.alphaBlendToDC bufferDIB.getDIBDC, 192, offsetX, offsetY + fixDPI(1)
        imgThumbnails(thumbIndex).thumbDIB.alphaBlendToDC bufferDIB.getDIBDC, 255, offsetX + fixDPI(thumbBorder), offsetY + fixDPI(thumbBorder)
        
        'If the parent image has unsaved changes, also render a notification icon
        If Not pdImages(imgThumbnails(thumbIndex).indexInPDImages).getSaveState(pdSE_AnySave) Then
            unsavedChangesDIB.alphaBlendToDC bufferDIB.getDIBDC, 230, offsetX + fixDPI(thumbBorder) + fixDPI(2), offsetY + thumbHeight - fixDPI(thumbBorder) - unsavedChangesDIB.getDIBHeight - fixDPI(2)
        End If
        
    End If

End Sub

'Whenever a thumbnail has been updated, this sub must be called to regenerate its drop-shadow
Private Sub updateShadowDIB(ByVal imgThumbnailIndex As Long)
    imgThumbnails(imgThumbnailIndex).thumbShadow.eraseDIB
    createShadowDIB imgThumbnails(imgThumbnailIndex).thumbDIB, imgThumbnails(imgThumbnailIndex).thumbShadow
    padDIB imgThumbnails(imgThumbnailIndex).thumbShadow, fixDPI(thumbBorder)
    quickBlurDIB imgThumbnails(imgThumbnailIndex).thumbShadow, shadowBlurRadius
    imgThumbnails(imgThumbnailIndex).thumbShadow.fixPremultipliedAlpha True
End Sub

'Even though the scroll bar is not visible, we still process mousewheel events using it, so redraw when it changes
Private Sub hsThumbnails_Change()
    redrawToolbar
End Sub

Private Sub hsThumbnails_Scroll()
    redrawToolbar
End Sub

'External functions can use this to re-theme this form at run-time (important when changing languages, for example)
Public Sub requestMakeFormPretty()
    makeFormPretty Me, m_ToolTip
End Sub
