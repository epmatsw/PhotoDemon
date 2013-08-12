VERSION 5.00
Begin VB.Form FormOilPainting 
   BackColor       =   &H80000005&
   BorderStyle     =   4  'Fixed ToolWindow
   Caption         =   " Oil Painting"
   ClientHeight    =   6540
   ClientLeft      =   45
   ClientTop       =   285
   ClientWidth     =   12030
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
   ScaleHeight     =   436
   ScaleMode       =   3  'Pixel
   ScaleWidth      =   802
   ShowInTaskbar   =   0   'False
   StartUpPosition =   1  'CenterOwner
   Begin VB.CommandButton CmdOK 
      Caption         =   "&OK"
      Default         =   -1  'True
      Height          =   495
      Left            =   9030
      TabIndex        =   0
      Top             =   5910
      Width           =   1365
   End
   Begin VB.CommandButton CmdCancel 
      Cancel          =   -1  'True
      Caption         =   "&Cancel"
      Height          =   495
      Left            =   10500
      TabIndex        =   1
      Top             =   5910
      Width           =   1365
   End
   Begin PhotoDemon.fxPreviewCtl fxPreview 
      Height          =   5625
      Left            =   120
      TabIndex        =   3
      Top             =   120
      Width           =   5625
      _ExtentX        =   9922
      _ExtentY        =   9922
   End
   Begin PhotoDemon.sliderTextCombo sltRadius 
      Height          =   495
      Left            =   6000
      TabIndex        =   7
      Top             =   2280
      Width           =   5895
      _ExtentX        =   10186
      _ExtentY        =   873
      Min             =   1
      Max             =   200
      Value           =   5
      BeginProperty Font {0BE35203-8F91-11CE-9DE3-00AA004BB851} 
         Name            =   "Tahoma"
         Size            =   9.75
         Charset         =   0
         Weight          =   400
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
   End
   Begin PhotoDemon.sliderTextCombo sltPercent 
      Height          =   495
      Left            =   6000
      TabIndex        =   8
      Top             =   3240
      Width           =   5895
      _ExtentX        =   10186
      _ExtentY        =   873
      Min             =   1
      Max             =   50
      Value           =   15
      BeginProperty Font {0BE35203-8F91-11CE-9DE3-00AA004BB851} 
         Name            =   "Tahoma"
         Size            =   9.75
         Charset         =   0
         Weight          =   400
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
   End
   Begin VB.Label lblPercentile 
      AutoSize        =   -1  'True
      BackStyle       =   0  'Transparent
      Caption         =   "detail:"
      BeginProperty Font 
         Name            =   "Tahoma"
         Size            =   12
         Charset         =   0
         Weight          =   400
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      ForeColor       =   &H00404040&
      Height          =   285
      Left            =   6000
      TabIndex        =   6
      Top             =   2880
      Width           =   660
   End
   Begin VB.Label lblRadius 
      AutoSize        =   -1  'True
      BackStyle       =   0  'Transparent
      Caption         =   "brush size:"
      BeginProperty Font 
         Name            =   "Tahoma"
         Size            =   12
         Charset         =   0
         Weight          =   400
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      ForeColor       =   &H00404040&
      Height          =   285
      Left            =   6000
      TabIndex        =   5
      Top             =   1920
      Width           =   1155
   End
   Begin VB.Label lblIDEWarning 
      BackStyle       =   0  'Transparent
      BeginProperty Font 
         Name            =   "Tahoma"
         Size            =   9
         Charset         =   0
         Weight          =   400
         Underline       =   0   'False
         Italic          =   0   'False
         Strikethrough   =   0   'False
      EndProperty
      ForeColor       =   &H000000FF&
      Height          =   1095
      Left            =   6000
      TabIndex        =   4
      Top             =   4440
      Visible         =   0   'False
      Width           =   5775
      WordWrap        =   -1  'True
   End
   Begin VB.Label lblBackground 
      Height          =   855
      Left            =   0
      TabIndex        =   2
      Top             =   5760
      Width           =   12135
   End
End
Attribute VB_Name = "FormOilPainting"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = True
Attribute VB_Exposed = False
'***************************************************************************
'Oil Painting Effect Tool
'Copyright �2012-2013 by Tanner Helland
'Created: 09/August/13
'Last updated: 09/August/13
'Last update: initial build
'
'Oil painting image effect, heavily optimized.  An "accumulation" technique is used instead of the standard sliding
' window mechanism.  (See http://web.archive.org/web/20060718054020/http://www.acm.uiuc.edu/siggraph/workshops/wjarosz_convolution_2001.pdf)
' This allows the algorithm to perform extremely well, despite being written in pure VB.
'
'That said, it is still unfortunately slow in the IDE.  I STRONGLY recommend compiling the project before applying this
' effect at a large radius (> 10).
'
'All source code in this file is licensed under a modified BSD license.  This means you may use the code in your own
' projects IF you provide attribution.  For more information, please visit http://www.tannerhelland.com/photodemon/#license
'
'***************************************************************************

Option Explicit

'When previewing, we need to modify the strength to be representative of the final filter.  This means dividing by the
' original image dimensions in order to establish the right ratio.
Dim iWidth As Long, iHeight As Long

Dim allowPreview As Boolean

'Custom tooltip class allows for things like multiline, theming, and multiple monitor support
Dim m_ToolTip As clsToolTip

'CANCEL button
Private Sub CmdCancel_Click()
    Unload Me
End Sub

'OK button
Private Sub CmdOK_Click()

    'Validate text box entries
    If sltRadius.IsValid And sltPercent.IsValid Then
        Me.Visible = False
        Process "Oil Painting", , buildParams(sltRadius.Value, sltPercent.Value)
        Unload Me
    End If
    
End Sub

'Apply an "oil painting" effect to the image (heavily optimized accumulation implementation!)
'Inputs: radius of the effect (min 1, no real max - but the scroll bar is maxed at 200 presently)
'        smoothness of the effect; smaller values indicate less smoothness (e.g. less bins are used to calculate luminance)
Public Sub ApplyOilPaintingEffect(ByVal mRadius As Long, ByVal mLevels As Double, Optional ByVal toPreview As Boolean = False, Optional ByRef dstPic As fxPreviewCtl)
    
    If Not toPreview Then Message "Repainting image with oils..."
    
    'If this is a preview, we need to adjust the kernel radius to match the size of the preview box
    If toPreview Then
        mRadius = (mRadius / iWidth) * curLayerValues.Width
        If mRadius < 1 Then mRadius = 1
    End If
    
    'Create a local array and point it at the pixel data of the current image
    Dim dstImageData() As Byte
    Dim dstSA As SAFEARRAY2D
    prepImageData dstSA, toPreview, dstPic
    CopyMemory ByVal VarPtrArray(dstImageData()), VarPtr(dstSA), 4
    
    'Create a second local array.  This will contain the a copy of the current image, and we will use it as our source reference
    ' (This is necessary to prevent processed pixel values from spreading across the image as we go.)
    Dim srcLayer As pdLayer
    Set srcLayer = New pdLayer
    srcLayer.createFromExistingLayer workingLayer
    
    'Create a second local array.  This will contain the a copy of the current image, and we will use it as our source reference
    ' (This is necessary to prevent medianred pixel values from spreading across the image as we go.)
    Dim srcImageData() As Byte
    Dim srcSA As SAFEARRAY2D
    prepSafeArray srcSA, srcLayer
    CopyMemory ByVal VarPtrArray(srcImageData()), VarPtr(srcSA), 4
        
    'Local loop variables can be more efficiently cached by VB's compiler, so we transfer all relevant loop data here
    Dim x As Long, y As Long, initX As Long, initY As Long, finalX As Long, finalY As Long
    initX = 0
    initY = 0
    finalX = srcLayer.getLayerWidth - 1
    finalY = srcLayer.getLayerHeight - 1
    
    'Just to be safe, make sure the radius isn't larger than the image itself
    If (finalY - initY) < (finalX - initX) Then
        If mRadius > (finalY - initY) Then mRadius = finalY - initY
    Else
        If mRadius > (finalX - initX) Then mRadius = finalX - initX
    End If
        
    'These values will help us access locations in the array more quickly.
    ' (qvDepth is required because the image array may be 24 or 32 bits per pixel, and we want to handle both cases.)
    Dim QuickVal As Long, QuickValInner As Long, QuickY As Long, qvDepth As Long
    qvDepth = srcLayer.getLayerColorDepth \ 8
    
    'To keep processing quick, only update the progress bar when absolutely necessary.  This function calculates that value
    ' based on the size of the area to be processed.
    Dim progBarCheck As Long
    SetProgBarMax finalX
    progBarCheck = findBestProgBarValue()
    
    'The number of pixels in the current median box are tracked dynamically.
    Dim NumOfPixels As Long
    NumOfPixels = 0
            
    'Median filtering takes a lot of variables
    Dim rValues(0 To 255) As Long, gValues(0 To 255) As Long, bValues(0 To 255) As Long, lValues(0 To 255) As Long
    Dim lbX As Long, lbY As Long, ubX As Long, ubY As Long
    Dim obuX As Boolean, obuY As Boolean, oblY As Boolean
    Dim i As Long, j As Long
    Dim r As Long, g As Long, b As Long, l As Long
    
    Dim atBottom As Boolean
    atBottom = True
    
    Dim startY As Long, stopY As Long, yStep As Long
    
    'We'll use the requested number of levels to create a gradient output.  Thus divide mLevels by 255, and build a
    ' look-up table for it.
    mLevels = mLevels / 255
    Dim maxPossibleLum As Long
    maxPossibleLum = 255 * mLevels
    
    Dim lLookup() As Byte
    ReDim lLookup(0 To 765) As Byte
    For i = 0 To 765
        lLookup(i) = CLng(CDbl(i / 3) * mLevels)
    Next i
    
    'Later in the function, we must find the most populated luminance bin; these values help us track it
    Dim maxBinCount As Long, maxBinIndex As Byte
    
    'Generate an initial array of median data for the first pixel
    For x = initX To initX + mRadius - 1
        QuickVal = x * qvDepth
    For y = initY To initY + mRadius
    
        r = srcImageData(QuickVal + 2, y)
        g = srcImageData(QuickVal + 1, y)
        b = srcImageData(QuickVal, y)
        l = lLookup(r + g + b)
        rValues(l) = rValues(l) + r
        gValues(l) = gValues(l) + g
        bValues(l) = bValues(l) + b
        lValues(l) = lValues(l) + 1
        
    Next y
    Next x
                
    'Loop through each pixel in the image, tallying median values as we go
    For x = initX To finalX
            
        QuickVal = x * qvDepth
        
        'Determine the bounds of the current median box in the X direction
        lbX = x - mRadius
        If lbX < 0 Then lbX = 0
        
        ubX = x + mRadius
        If ubX > finalX Then
            obuX = True
            ubX = finalX
        Else
            obuX = False
        End If
                
        'As part of my accumulation algorithm, I swap the inner loop's direction with each iteration.
        ' Set y-related loop variables depending on the direction of the next cycle.
        If atBottom Then
            lbY = 0
            ubY = mRadius
        Else
            lbY = finalY - mRadius
            ubY = finalY
        End If
        
        'Remove trailing values from the median box if they lie outside the processing radius
        If lbX > 0 Then
        
            QuickValInner = (lbX - 1) * qvDepth
        
            For j = lbY To ubY
                r = srcImageData(QuickValInner + 2, j)
                g = srcImageData(QuickValInner + 1, j)
                b = srcImageData(QuickValInner, j)
                l = lLookup(r + g + b)
                rValues(l) = rValues(l) - r
                gValues(l) = gValues(l) - g
                bValues(l) = bValues(l) - b
                lValues(l) = lValues(l) - 1
            Next j
        
        End If
        
        'Add leading values to the median box if they lie inside the processing radius
        If Not obuX Then
        
            QuickValInner = ubX * qvDepth
            
            For j = lbY To ubY
                r = srcImageData(QuickValInner + 2, j)
                g = srcImageData(QuickValInner + 1, j)
                b = srcImageData(QuickValInner, j)
                l = lLookup(r + g + b)
                rValues(l) = rValues(l) + r
                gValues(l) = gValues(l) + g
                bValues(l) = bValues(l) + b
                lValues(l) = lValues(l) + 1
            Next j
            
        End If
        
        'Depending on the direction we are moving, remove a line of pixels from the median box
        ' (because the interior loop will add it back in).
        If atBottom Then
        
            For i = lbX To ubX
                QuickValInner = i * qvDepth
                r = srcImageData(QuickValInner + 2, mRadius)
                g = srcImageData(QuickValInner + 1, mRadius)
                b = srcImageData(QuickValInner, mRadius)
                l = lLookup(r + g + b)
                rValues(l) = rValues(l) - r
                gValues(l) = gValues(l) - g
                bValues(l) = bValues(l) - b
                lValues(l) = lValues(l) - 1
            Next i
       
        Else
       
            QuickY = finalY - mRadius
       
            For i = lbX To ubX
                QuickValInner = i * qvDepth
                r = srcImageData(QuickValInner + 2, QuickY)
                g = srcImageData(QuickValInner + 1, QuickY)
                b = srcImageData(QuickValInner, QuickY)
                l = lLookup(r + g + b)
                rValues(l) = rValues(l) - r
                gValues(l) = gValues(l) - g
                bValues(l) = bValues(l) - b
                lValues(l) = lValues(l) - 1
            Next i
       
        End If
        
        'Based on the direction we're traveling, reverse the interior loop boundaries as necessary.
        If atBottom Then
            startY = 0
            stopY = finalY
            yStep = 1
        Else
            startY = finalY
            stopY = 0
            yStep = -1
        End If
            
    'Process the next column.  This step is pretty much identical to the row steps above (but in a vertical direction, obviously)
    For y = startY To stopY Step yStep
            
        'If we are at the bottom and moving up, we will REMOVE rows from the bottom and ADD them at the top.
        'If we are at the top and moving down, we will REMOVE rows from the top and ADD them at the bottom.
        'As such, there are two copies of this function, one per possible direction.
        If atBottom Then
        
            'Calculate bounds
            lbY = y - mRadius
            If lbY < 0 Then lbY = 0
            
            ubY = y + mRadius
            If ubY > finalY Then
                obuY = True
                ubY = finalY
            Else
                obuY = False
            End If
                                
            'Remove trailing values from the box
            If lbY > 0 Then
            
                QuickY = lbY - 1
            
                For i = lbX To ubX
                    QuickValInner = i * qvDepth
                    r = srcImageData(QuickValInner + 2, QuickY)
                    g = srcImageData(QuickValInner + 1, QuickY)
                    b = srcImageData(QuickValInner, QuickY)
                    l = lLookup(r + g + b)
                    rValues(l) = rValues(l) - r
                    gValues(l) = gValues(l) - g
                    bValues(l) = bValues(l) - b
                    lValues(l) = lValues(l) - 1
                Next i
                        
            End If
                    
            'Add leading values
            If Not obuY Then
            
                For i = lbX To ubX
                    QuickValInner = i * qvDepth
                    r = srcImageData(QuickValInner + 2, ubY)
                    g = srcImageData(QuickValInner + 1, ubY)
                    b = srcImageData(QuickValInner, ubY)
                    l = lLookup(r + g + b)
                    rValues(l) = rValues(l) + r
                    gValues(l) = gValues(l) + g
                    bValues(l) = bValues(l) + b
                    lValues(l) = lValues(l) + 1
                Next i
            
            End If
            
        'The exact same code as above, but in the opposite direction
        Else
        
            lbY = y - mRadius
            If lbY < 0 Then
                oblY = True
                lbY = 0
            Else
                oblY = False
            End If
            
            ubY = y + mRadius
            If ubY > finalY Then ubY = finalY
                                
            If ubY < finalY Then
            
                QuickY = ubY + 1
            
                For i = lbX To ubX
                    QuickValInner = i * qvDepth
                    r = srcImageData(QuickValInner + 2, QuickY)
                    g = srcImageData(QuickValInner + 1, QuickY)
                    b = srcImageData(QuickValInner, QuickY)
                    l = lLookup(r + g + b)
                    rValues(l) = rValues(l) - r
                    gValues(l) = gValues(l) - g
                    bValues(l) = bValues(l) - b
                    lValues(l) = lValues(l) - 1
                Next i
                        
            End If
                    
            If Not oblY Then
            
                For i = lbX To ubX
                    QuickValInner = i * qvDepth
                    r = srcImageData(QuickValInner + 2, lbY)
                    g = srcImageData(QuickValInner + 1, lbY)
                    b = srcImageData(QuickValInner, lbY)
                    l = lLookup(r + g + b)
                    rValues(l) = rValues(l) + r
                    gValues(l) = gValues(l) + g
                    bValues(l) = bValues(l) + b
                    lValues(l) = lValues(l) + 1
                Next i
            
            End If
        
        End If
        
        'With a local histogram successfully built for the area surrounding this pixel, we now need to find the
        ' maximum luminance value.
        maxBinCount = 0
        For i = 0 To maxPossibleLum
            If lValues(i) > maxBinCount Then
                maxBinCount = lValues(i)
                maxBinIndex = i
            End If
        Next i
                
        r = rValues(maxBinIndex) / maxBinCount
        If r > 255 Then r = 255
        g = gValues(maxBinIndex) / maxBinCount
        If g > 255 Then g = 255
        b = bValues(maxBinIndex) / maxBinCount
        If b > 255 Then b = 255
                
        'Finally, apply the results to the image.
        dstImageData(QuickVal + 2, y) = r
        dstImageData(QuickVal + 1, y) = g
        dstImageData(QuickVal, y) = b
        
    Next y
        atBottom = Not atBottom
        If Not toPreview Then
            If (x And progBarCheck) = 0 Then
                If userPressedESC() Then Exit For
                SetProgBarVal x
            End If
        End If
    Next x
        
    'With our work complete, point both ImageData() arrays away from their DIBs and deallocate them
    CopyMemory ByVal VarPtrArray(srcImageData), 0&, 4
    Erase srcImageData
    
    CopyMemory ByVal VarPtrArray(dstImageData), 0&, 4
    Erase dstImageData
    
    srcLayer.eraseLayer
    Set srcLayer = Nothing
    
    'Pass control to finalizeImageData, which will handle the rest of the rendering using the data inside workingLayer
    finalizeImageData toPreview, dstPic

End Sub

Private Sub Form_Activate()

    'Note the current image's width and height, which will be needed to adjust the preview effect
    If pdImages(CurrentImage).selectionActive Then
        iWidth = pdImages(CurrentImage).mainSelection.boundWidth
        iHeight = pdImages(CurrentImage).mainSelection.boundHeight
    Else
        iWidth = pdImages(CurrentImage).Width
        iHeight = pdImages(CurrentImage).Height
    End If

    allowPreview = True

    'Draw a preview of the effect
    updatePreview
    
    'Assign the system hand cursor to all relevant objects
    Set m_ToolTip = New clsToolTip
    makeFormPretty Me, m_ToolTip
    
    'If the program is not compiled, display a special warning for this tool
    If Not g_IsProgramCompiled Then
        lblIDEWarning.Caption = g_Language.TranslateMessage("WARNING!  This tool has been heavily optimized, but at high radius values it will still be quite slow inside the IDE.  Please compile before applying or previewing any radius larger than 20.")
        lblIDEWarning.Visible = True
    End If
    
End Sub

Private Sub Form_Load()
    allowPreview = False
End Sub

Private Sub Form_Unload(Cancel As Integer)
    ReleaseFormTheming Me
End Sub

Private Sub sltPercent_Change()
    updatePreview
End Sub

Private Sub sltRadius_Change()
    updatePreview
End Sub

Private Sub updatePreview()
    If allowPreview Then ApplyOilPaintingEffect sltRadius.Value, sltPercent.Value, True, fxPreview
End Sub