sub init()
    m.top.setFocus(true)
    print "HelloScene initialized"

    ' scale calendar to fit screen resolution
    m.calendarGroup = m.top.findNode("calendarGroup")
    m.daysGroup = m.top.findNode("daysGroup")

    if m.calendarGroup <> invalid then
        deviceInfo = CreateObject("roDeviceInfo")
        displaySize = deviceInfo.GetDisplaySize()
        screenW = displaySize.w
        screenH = displaySize.h

        if screenW <= 0 then screenW = 1280
        if screenH <= 0 then screenH = 720

        baseScale = screenW / 1920.0
        scale = baseScale * 0.85
        m.calendarGroup.scale = [scale, scale]
        m.calendarGroup.translation = [20, 110]

        createCalendarGrid()
        ' Mock data for now: show March 2026 starting on Sunday (index 0)
        populateCalendar(0, 31, {
            "2": "Mtg",
            "3": "Dentist",
            "4": "Gym",
            "6": "Conf",
            "9": "Doctor",
            "11": "Project",
            "13": "Game",
            "14": "Birthday",
            "17": "Dentist",
            "19": "Gym",
            "21": "Trip",
            "23": "Work",
            "26": "Meeting",
            "28": "Dinner",
            "29": "Easter"
        })
    end if
end sub

sub createCalendarGrid()
    ' Create 42 blocks (6 weeks * 7 days)
    for i = 0 to 41
        col = i MOD 7
        row = i \ 7
        x = col * 210
        y = row * 130

        ' 1. Background Rect
        rect = CreateObject("roSGNode", "Rectangle")
        rect.id = "bg_" + i.toStr()
        rect.width = 200
        rect.height = 120
        rect.color = "0x2d2d5cff"
        rect.translation = [x, y]
        m.daysGroup.appendChild(rect)

        ' 2. Day Number Label
        dayLbl = CreateObject("roSGNode", "Label")
        dayLbl.id = "day_" + i.toStr()
        dayLbl.translation = [x + 8, y + 10]
        dayLbl.font = "font:MediumBoldSystemFont"
        dayLbl.color = "0xffffffff"
        m.daysGroup.appendChild(dayLbl)

        ' 3. Event Label (Right justified)
        evtLbl = CreateObject("roSGNode", "Label")
        evtLbl.id = "evt_" + i.toStr()
        evtLbl.translation = [x, y + 30]
        evtLbl.width = 192
        evtLbl.horizAlign = "right"
        evtLbl.font = "font:SmallSystemFont"
        evtLbl.color = "0xffffffff"
        m.daysGroup.appendChild(evtLbl)
    end for
end sub

sub populateCalendar(startDayIndex as integer, daysInMonth as integer, events as object)
    ' Clear all previous labels
    for i = 0 to 41
        dayLbl = m.daysGroup.findNode("day_" + i.toStr())
        evtLbl = m.daysGroup.findNode("evt_" + i.toStr())
        if dayLbl <> invalid then dayLbl.text = ""
        if evtLbl <> invalid then evtLbl.text = ""
    end for

    ' Fill in days
    for day = 1 to daysInMonth
        index = startDayIndex + day - 1
        if index <= 41 then
            dayLbl = m.daysGroup.findNode("day_" + index.toStr())
            evtLbl = m.daysGroup.findNode("evt_" + index.toStr())

            if dayLbl <> invalid then dayLbl.text = day.toStr()

            ' Add event if exists
            dayStr = day.toStr()
            if events.doesExist(dayStr) then
                if evtLbl <> invalid then evtLbl.text = events[dayStr]
                ' color events differently
                if dayStr = "29" then evtLbl.color = "0xff44ffff" ' Easter
                if dayStr = "2" then evtLbl.color = "0x4444ffff" ' Work
            end if
        end if
    end for
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press then
        print "Key pressed: "; key
        ' Remote key handling for future expansion
        ' 0=Back, 1=Up, 2=Down, 3=Left, 4=Right, 5=OK, etc.
    end if
    return false
end function
