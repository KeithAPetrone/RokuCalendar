sub init()
    m.top.setFocus(true)
    print "HelloScene initialized"

    ' scale calendar to fit screen resolution
    m.calendarGroup = m.top.findNode("calendarGroup")
    if m.calendarGroup <> invalid then
        deviceInfo = CreateObject("roDeviceInfo")
        displaySize = deviceInfo.GetDisplaySize()
        screenW = displaySize.w
        screenH = displaySize.h
        
        ' Default to 1280x720 if detection fails
        if screenW <= 0 then screenW = 1280
        if screenH <= 0 then screenH = 720
        
        ' Base scale on 1920 design width
        baseScale = screenW / 1920.0
        
        ' Use 0.85 for a slightly smaller fit
        scale = baseScale * 0.85
        m.calendarGroup.scale = [scale, scale]
        
        ' Move slightly right to [20, 110]
        m.calendarGroup.translation = [20, 110]
        
        print "Screen Resolution: "; screenW; "x"; screenH
        print "Calendar scale set to"; scale; " at"; m.calendarGroup.translation
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press then
        print "Key pressed: "; key
        ' Remote key handling for future expansion
        ' 0=Back, 1=Up, 2=Down, 3=Left, 4=Right, 5=OK, etc.
    end if
    return false
end function
