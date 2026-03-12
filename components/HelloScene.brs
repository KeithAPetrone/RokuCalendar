sub init()
    m.top.setFocus(true)
    
    deviceInfo = CreateObject("roDeviceInfo")
    m.screenW = deviceInfo.GetDisplaySize().w
    if m.screenW = invalid or m.screenW <= 0 then
        m.screenW = 1920
    end if

    m.calendarGroup = m.top.findNode("calendarGroup")
    m.daysGroup = m.top.findNode("daysGroup")
    m.backgroundPoster = m.top.findNode("backgroundPoster")
    m.backgroundPosterNext = m.top.findNode("backgroundPosterNext")
    m.fadeTransition = m.top.findNode("fadeTransition")
    m.fadeAway = m.top.findNode("fadeAway")
    m.fadeIn = m.top.findNode("fadeIn")
    
    m.backgroundOverlay = m.top.findNode("backgroundOverlay")
    m.headerBar = m.top.findNode("headerBar")
    m.tempLabel = m.top.findNode("tempLabel")
    m.conditionLabel = m.top.findNode("conditionLabel")
    m.todayLabel = m.top.findNode("todayLabel")
    m.monthLabel = m.top.findNode("monthLabel")
    m.loginOverlay = m.top.findNode("loginOverlay")
    m.loginTitle = m.top.findNode("loginTitle")
    m.loginUrl = m.top.findNode("loginUrl")
    m.loginCode = m.top.findNode("loginCode")
    m.googleEvents = {}
    m.bgRects = []
    m.dayLabels = []
    m.evtGroups = []
    m.timeLabels = []
    m.dayHeaders = []
    m.photoPaths = []
    m.photoIndex = 0
    m.currentPoster = 0
    m.viewMode = "monthly"
    m.dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    displaySize = deviceInfo.GetDisplaySize()
    m.screenW = displaySize.w
    m.screenH = displaySize.h
    
    if m.backgroundPoster <> invalid then
        m.backgroundPoster.width = m.screenW
        m.backgroundPoster.height = m.screenH
    end if
    if m.backgroundPosterNext <> invalid then
        m.backgroundPosterNext.width = m.screenW
        m.backgroundPosterNext.height = m.screenH
    end if
    if m.backgroundOverlay <> invalid then
        m.backgroundOverlay.width = m.screenW
        m.backgroundOverlay.height = m.screenH
    end if
    if m.headerBar <> invalid then
        m.headerBar.width = m.screenW
    end if

    if m.calendarGroup <> invalid then
        for i = 0 to 6
            child = m.calendarGroup.getChild(i)
            if child <> invalid then
                m.dayHeaders.push(child)
            end if
        end for
    end if

    updateLayout()

    if m.daysGroup <> invalid then
        createCalendarGrid()
        setupCurrentMonth()
    end if

    m.authTimer = m.top.createChild("Timer")
    m.authTimer.duration = 0.5
    m.authTimer.repeat = false
    m.authTimer.observeField("fire", "onAuthTimerFire")
    m.authTimer.control = "START"
    
    if m.backgroundPoster <> invalid then
        m.backgroundPoster.observeField("loadStatus", "onPosterLoadStatus")
    end if
    if m.backgroundPosterNext <> invalid then
        m.backgroundPosterNext.observeField("loadStatus", "onPosterLoadStatus")
    end if
    
    startWeatherTask()
end sub

sub startWeatherTask()
    m.weatherTask = CreateObject("roSGNode", "WeatherTask")
    m.weatherTask.observeField("temp", "onWeatherUpdate")
    m.weatherTask.observeField("condition", "onWeatherUpdate")
    m.weatherTask.control = "RUN"
    
    m.weatherTimer = m.top.createChild("Timer")
    m.weatherTimer.duration = 1800
    m.weatherTimer.repeat = true
    m.weatherTimer.observeField("fire", "refreshWeather")
    m.weatherTimer.control = "START"
end sub

sub refreshWeather()
    if m.weatherTask <> invalid then
        m.weatherTask.status = "REFRESH"
    end if
end sub

sub onWeatherUpdate()
    if m.tempLabel <> invalid then
        m.tempLabel.text = m.weatherTask.temp
    end if
    if m.conditionLabel <> invalid then
        m.conditionLabel.text = m.weatherTask.condition
    end if
end sub

sub logMsg(msg as string)
    print "[HelloScene] " + msg
end sub

sub updateLayout()
    if m.screenW = invalid or m.screenW <= 0 then
        return
    end if
    scale = (m.screenW / 1920.0)
    if m.viewMode = "monthly" then
        scale = scale * 1.1
        calendarWidth = 1680 * scale
    else
        scale = scale * 0.95
        calendarWidth = 1880 * scale
    end if
    if m.calendarGroup <> invalid then
        m.calendarGroup.scale = [scale, scale]
        centerX = (m.screenW - calendarWidth) / 2
        m.calendarGroup.translation = [centerX, 110]
    end if
end sub

sub createCalendarGrid()
    m.daysGroup.removeChildrenIndex(0, m.daysGroup.getChildCount())
    m.bgRects = []
    m.dayLabels = []
    m.evtGroups = []
    for i = 0 to 41
        col = i MOD 7
        row = i \ 7
        x = col * 240
        y = row * 170
        rect = m.daysGroup.createChild("Rectangle")
        rect.width = 230
        rect.height = 160
        rect.color = "#00000000"
        rect.translation = [x, y]
        m.bgRects.push(rect)
        dayLbl = m.daysGroup.createChild("Label")
        dayLbl.translation = [x + 8, y + 10]
        dayLbl.font = "font:SmallSystemFont"
        dayLbl.scale = [0.8, 0.8]
        m.dayLabels.push(dayLbl)
        evtGrp = m.daysGroup.createChild("Group")
        evtGrp.translation = [x, y]
        m.evtGroups.push(evtGrp)
    end for
end sub

sub onPosterLoadStatus(event as Object)
    node = event.getRoSGNode()
    status = event.getData()
    if status <> "ready" then
        return
    end if
    if m.fadeTransition.state = "running" then
        return
    end if
    if m.currentPoster = 0 then
        if node.id = "backgroundPosterNext" then
            m.fadeAway.fieldToInterp = "backgroundPoster.opacity"
            m.fadeIn.fieldToInterp = "backgroundPosterNext.opacity"
            m.fadeTransition.control = "start"
            m.currentPoster = 1
        end if
    else if m.currentPoster = 1 then
        if node.id = "backgroundPoster" then
            m.fadeAway.fieldToInterp = "backgroundPosterNext.opacity"
            m.fadeIn.fieldToInterp = "backgroundPoster.opacity"
            m.fadeTransition.control = "start"
            m.currentPoster = 0
        end if
    end if
end sub

sub refreshUI()
    dtNow = CreateObject("roDateTime")
    dtNow.ToLocalTime()
    curDay = dtNow.GetDayOfMonth()
    curMonth = dtNow.GetMonth()
    
    if m.todayLabel <> invalid then
        m.todayLabel.text = "Today is " + dtNow.AsDateString("long")
    end if
    allEvents = m.googleEvents
    colWidth = 240
    rectWidth = 230
    if m.viewMode = "weekly" then
        colWidth = 270
        rectWidth = 260
    end if
    for i = 0 to 41
        col = i MOD 7
        row = i \ 7
        x = col * colWidth
        y = row * 170
        if i < m.bgRects.count() then
            m.bgRects[i].color = "#00000000"
            m.dayLabels[i].text = ""
            m.bgRects[i].visible = false
            m.dayLabels[i].visible = false
            m.bgRects[i].width = rectWidth
            m.bgRects[i].height = 160
            m.bgRects[i].translation = [x, y]
            m.dayLabels[i].translation = [x + 8, y + 10]
            m.evtGroups[i].translation = [x, y]
            if m.evtGroups[i].getChildCount() > 0 then
                m.evtGroups[i].removeChildren(m.evtGroups[i].getChildren(-1, 0))
            end if
        end if
        if i < 7 then
            if m.dayHeaders[i] <> invalid then
                m.dayHeaders[i].translation = [x, 0]
                m.dayHeaders[i].width = rectWidth
                m.dayHeaders[i].text = m.dayNames[i]
            end if
        end if
    end for

    if m.viewMode = "monthly" then
        startIdx = 0
        if type(m.startDayIndex) = "Integer" then
            startIdx = m.startDayIndex
        end if
        for day = 1 to m.daysInMonth
            idx = startIdx + day - 1
            if idx >= 0 and idx < m.bgRects.count() then
                m.bgRects[idx].color = "#3d3d7c99"
                m.bgRects[idx].visible = true
                m.dayLabels[idx].text = (day).ToStr()
                m.dayLabels[idx].visible = true
                dayStr = (day).ToStr()
                if allEvents.doesExist(dayStr) then 
                    summaryText = ""
                    for each ev in allEvents[dayStr]
                        timePrefix = ""
                        if ev.isAllDay = false then
                            h = ev.hour
                            m_val = ev.minute
                            ampm = "a"
                            if h >= 12 then
                                ampm = "p"
                            end if
                            if h > 12 then
                                h = h - 12
                            end if
                            if h = 0 then
                                h = 12
                            end if
                            m_str = (m_val).ToStr()
                            if m_str.len() = 1 then
                                m_str = "0" + m_str
                            end if
                            timePrefix = (h).ToStr() + ":" + m_str + ampm + " "
                        end if
                        summaryText = summaryText + "• " + timePrefix + ev.summary + chr(10)
                    end for
                    lbl = m.evtGroups[idx].createChild("Label")
                    lbl.width = (rectWidth - 10) / 0.7
                    lbl.height = 140 / 0.7
                    lbl.translation = [5, 45]
                    lbl.font = "font:SmallSystemFont"
                    lbl.wrap = true
                    lbl.text = summaryText
                    lbl.scale = [0.7, 0.7]
                end if
                if day = curDay and m.currentMonth = curMonth then
                    m.bgRects[idx].color = "#6d6dbf99"
                end if
            end if
        end for
    else
        dayOfWeek = dtNow.GetDayOfWeek()
        startOfWeek = curDay - dayOfWeek
        maxAllDayEvents = 0
        for i = 0 to 6
            day = startOfWeek + i
            dayStr = (day).ToStr()
            if allEvents.doesExist(dayStr) then
                count = 0
                for each ev in allEvents[dayStr]
                    if ev.isAllDay = true then
                        count = count + 1
                    end if
                end for
                if count > maxAllDayEvents then
                    maxAllDayEvents = count
                end if
            end if
        end for
        
        allDayHeaderSpace = 0
        if maxAllDayEvents > 0 then
            allDayHeaderSpace = 30
        end if
        globalTimelineOffset = 60 + allDayHeaderSpace + (maxAllDayEvents * 35)
        
        for i = 0 to 6
            day = startOfWeek + i
            if i < m.bgRects.count() then
                m.bgRects[i].height = 1000
                m.bgRects[i].color = "#3d3d7c99"
                m.bgRects[i].visible = true
                m.dayLabels[i].visible = false
                if m.dayHeaders[i] <> invalid then
                    headerText = m.dayNames[i]
                    if day >= 1 and day <= m.daysInMonth then
                        headerText = headerText + " " + (day).ToStr()
                    end if
                    m.dayHeaders[i].text = headerText
                end if
                dayStr = (day).ToStr()
                if allEvents.doesExist(dayStr) then
                    allDayY = 5
                    if maxAllDayEvents > 0 then
                        hdr = m.evtGroups[i].createChild("Label")
                        hdr.text = "ALL DAY EVENTS"
                        hdr.font = "font:SmallSystemFont"
                        hdr.color = "0xaaaaaaff"
                        hdr.translation = [5, allDayY]
                        hdr.scale = [0.7, 0.7]
                        allDayY = allDayY + 22
                    end if
                    for each ev in allEvents[dayStr]
                        if ev.isAllDay = true then
                            lbl = m.evtGroups[i].createChild("Label")
                            lbl.width = (rectWidth - 15) / 0.75
                            lbl.wrap = true
                            lbl.height = 34 / 0.75
                            lbl.font = "font:SmallSystemFont"
                            lbl.text = "• " + ev.summary
                            lbl.color = "0xffaa00ff"
                            lbl.translation = [5, allDayY]
                            lbl.scale = [0.75, 0.75]
                            spacingMult = 1
                            if ev.summary.len() > 25 then
                                spacingMult = 2
                            end if
                            allDayY = allDayY + (25 * spacingMult)
                        end if
                    end for
                end if
                for h = 8 to 22
                    y_offset = globalTimelineOffset + (h - 8) * 65
                    line = m.evtGroups[i].createChild("Rectangle")
                    line.width = rectWidth
                    line.height = 2
                    line.color = "0xffffff66"
                    line.translation = [0, y_offset]
                    if i = 0 or i = 6 then
                        timeLbl = m.evtGroups[i].createChild("Label")
                        displayH = h
                        ampm = "a"
                        if h >= 12 then
                            ampm = "p"
                        end if
                        displayH_val = displayH
                        if displayH_val > 12 then
                            displayH_val = displayH_val - 12
                        else if displayH_val = 0 then
                            displayH_val = 12
                        end if
                        timeLbl.text = (displayH_val).ToStr() + ampm
                        timeLbl.font = "font:SmallSystemFont"
                        timeLbl.scale = [0.7, 0.7]
                        x_offset_time = 5
                        if i = 6 then
                            x_offset_time = rectWidth - 35
                        end if
                        timeLbl.translation = [x_offset_time, y_offset - 10]
                        timeLbl.color = "0xffffffff"
                    end if
                end for
                if allEvents.doesExist(dayStr) then
                    timedEvents = []
                    for each ev in allEvents[dayStr]
                        if ev.isAllDay = false then
                            if ev.hour >= 8 then
                                if ev.hour <= 22 then
                                    timedEvents.push(ev)
                                end if
                            end if
                        end if
                    end for
                    lanes = []
                    for each ev in timedEvents
                        startTime = ev.hour * 60 + ev.minute
                        endTime = startTime + 60
                        laneIndex = -1
                        for l = 0 to lanes.count() - 1
                            if startTime >= lanes[l] then
                                laneIndex = l
                                exit for
                            end if
                        end for
                        if laneIndex = -1 then
                            laneIndex = lanes.count()
                            lanes.push(endTime)
                        else
                            lanes[laneIndex] = endTime
                        end if
                        ev.lane = laneIndex
                    end for
                    numLanes = 1
                    if lanes.count() > 0 then
                        numLanes = lanes.count()
                    end if
                    laneWidth = (rectWidth - 10) / numLanes
                    for each ev in timedEvents
                        y_pos = globalTimelineOffset + 5 + (ev.hour - 8) * 65 + (ev.minute / 60.0) * 65
                        lbl = m.evtGroups[i].createChild("Label")
                        lbl.width = (laneWidth - 5) / 0.75
                        lbl.height = 60 / 0.75
                        lbl.wrap = true
                        lbl.font = "font:SmallSystemFont"
                        lbl.text = ev.summary
                        lbl.translation = [5 + (ev.lane * laneWidth), y_pos]
                        lbl.scale = [0.75, 0.75]
                        if day = curDay then
                            if m.currentMonth = curMonth then
                                lbl.color = "0xffff00ff"
                            end if
                        end if
                    end for
                end if
                if day = curDay then
                    if m.currentMonth = curMonth then
                        m.bgRects[i].color = "#6d6dbf99"
                    end if
                end if
            end if
        end for
    end if
    updateLayout()
end sub

sub setupCurrentMonth()
    dt = CreateObject("roDateTime")
    dt.ToLocalTime()
    m.currentYear = dt.GetYear()
    m.currentMonth = dt.GetMonth()
    months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    if m.monthLabel <> invalid then
        m.monthLabel.text = months[m.currentMonth - 1] + " " + (m.currentYear).ToStr()
    end if
    monthPadding = ""
    if m.currentMonth < 10 then
        monthPadding = "0"
    end if
    isoDate = (m.currentYear).ToStr() + "-" + monthPadding + (m.currentMonth).ToStr() + "-01T12:00:00Z"
    dtStart = CreateObject("roDateTime")
    dtStart.FromISO8601String(isoDate)
    dtStart.ToLocalTime()
    m.startDayIndex = fix(dtStart.GetDayOfWeek())
    m.daysInMonth = 31
    if m.currentMonth = 4 or m.currentMonth = 6 or m.currentMonth = 9 or m.currentMonth = 11 then
        m.daysInMonth = 30
    else if m.currentMonth = 2 then
        m.daysInMonth = 28
        if (m.currentYear MOD 4 = 0 and m.currentYear MOD 100 <> 0) or (m.currentYear MOD 400 = 0) then
            m.daysInMonth = 29
        end if
    end if
    refreshUI()
end sub

sub onAuthTimerFire()
    startDropboxAuth()
    startGoogleAuth()
    m.loginCheckTimer = m.top.createChild("Timer")
    m.loginCheckTimer.duration = 2.0
    m.loginCheckTimer.repeat = true
    m.loginCheckTimer.observeField("fire", "checkPendingLogins")
    m.loginCheckTimer.control = "START"
end sub

sub startDropboxAuth()
    m.dbTask = CreateObject("roSGNode", "DropboxTask")
    m.dbTask.observeField("authResult", "checkPendingLogins")
    m.dbTask.observeField("status", "onDBStatusChange")
    m.dbTask.observeField("photoUrls", "onPhotoUrls")
    m.dbTask.status = "AUTHENTICATE"
    m.dbTask.control = "RUN"
end sub

sub onDBStatusChange()
    status = m.dbTask.status
    if status = "SUCCESS" then
        m.dbTask.status = "FETCH_PHOTOS"
    else if status = "AUTHENTICATE" then
        checkPendingLogins()
    end if
end sub

sub startGoogleAuth()
    m.googleTask = CreateObject("roSGNode", "GoogleTask")
    m.googleTask.observeField("authResult", "checkPendingLogins")
    m.googleTask.observeField("status", "onGoogleStatusChange")
    m.googleTask.observeField("calendarData", "onGoogleCalendarData")
    m.googleTask.status = "AUTHENTICATE"
    m.googleTask.control = "RUN"
end sub

sub onGoogleStatusChange()
    status = m.googleTask.status
    if status = "SUCCESS" then 
        m.googleTask.status = "FETCH_CALENDAR"
        m.calRefreshTimer = m.top.createChild("Timer")
        m.calRefreshTimer.duration = 900
        m.calRefreshTimer.repeat = true
        m.calRefreshTimer.observeField("fire", "refreshCalendar")
        m.calRefreshTimer.control = "START"
    else if status = "AUTHENTICATE" then
        checkPendingLogins()
    end if
end sub

sub refreshCalendar()
    if m.googleTask <> invalid then
        m.googleTask.status = "REFRESH_CALENDAR"
    end if
end sub

sub checkPendingLogins()
    googAuth = false
    if m.googleTask <> invalid then
        if m.googleTask.status = "AUTHENTICATE" then
            googAuth = true
        end if
    end if
    
    if googAuth = false then
        if m.loginOverlay.visible = true then
            m.loginOverlay.visible = false
        end if
        return
    end if
    
    if m.loginOverlay.visible = true then
        return
    end if
    
    if googAuth = true then
        res = m.googleTask.authResult
        if res <> invalid then
            if res.user_code <> invalid then
                showLoginOverlay("Google Calendar", res.verification_url, res.user_code)
            end if
        end if
    end if
end sub

sub onGoogleCalendarData()
    if m.googleTask <> invalid then
        if m.googleTask.calendarData <> invalid then
            m.googleEvents = m.googleTask.calendarData
            refreshUI()
        end if
    end if
end sub

sub showLoginOverlay(title as string, url as string, code as string)
    m.loginTitle.text = "Login to " + title
    m.loginUrl.text = "Visit: " + url
    m.loginCode.text = code
    m.loginOverlay.visible = true
end sub

sub onPhotoUrls()
    if m.dbTask = invalid then
        return
    end if
    status = m.dbTask.status
    urls = m.dbTask.photoUrls
    if urls = invalid or urls.count() = 0 then
        return
    end if
    if status = "DB_LIST_OK" then
        if m.photoPaths.count() = 0 then
            m.photoPaths = urls
            ' Randomize starting index
            m.photoIndex = Rnd(m.photoPaths.count()) - 1
            if m.photoIndex < 0 then
                m.photoIndex = 0
            end if
            if m.slideshowTimer = invalid then
                m.slideshowTimer = m.top.createChild("Timer")
                m.slideshowTimer.repeat = true
                m.slideshowTimer.duration = 30
                m.slideshowTimer.observeField("fire", "nextPhoto")
            end if
            m.slideshowTimer.control = "START"
            nextPhoto()
            if m.photoRefreshTimer = invalid then
                m.photoRefreshTimer = m.top.createChild("Timer")
                m.photoRefreshTimer.repeat = true
                m.photoRefreshTimer.duration = 600
                m.photoRefreshTimer.observeField("fire", "refreshPhotoList")
            end if
            m.photoRefreshTimer.control = "START"
        else
            m.photoPaths = urls
        end if
    else if status = "DB_LINK_READY" or (urls.count() = 1 and InStr(1, urls[0], "https://") >= 1) then
        if m.currentPoster = 0 then
            ' If it's the very first photo ever loaded, just show it
            if m.backgroundPoster.uri = "" then
                m.backgroundPoster.uri = urls[0]
                m.backgroundPoster.opacity = 0.8
            else
                ' Otherwise, load into the hidden poster to trigger cross-fade
                m.backgroundPosterNext.uri = urls[0]
            end if
        else
            m.backgroundPoster.uri = urls[0]
        end if
    end if
end sub

sub refreshPhotoList()
    if m.dbTask <> invalid then
        m.dbTask.status = "REFRESH_PHOTOS"
    end if
end sub

sub nextPhoto()
    if m.photoPaths <> invalid then
        if m.photoPaths.count() > 0 then
            path = m.photoPaths[m.photoIndex]
            m.photoIndex = (m.photoIndex + 1) MOD m.photoPaths.count()
            if m.dbTask <> invalid then
                m.dbTask.status = "GET_LINK_FOR|" + path
            end if
        end if
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press = true then
        if key = "back" then
            if m.loginOverlay.visible = true then
                m.loginOverlay.visible = false
                return true
            end if
        else if key = "play" or key = "OK" or key = "options" then
            if m.viewMode = "monthly" then
                m.viewMode = "weekly"
            else
                m.viewMode = "monthly"
            end if
            refreshUI()
            return true
        end if
    end if
    return false
end function
