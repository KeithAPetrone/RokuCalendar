sub init()
    m.top.setFocus(true)
    
    m.calendarGroup = m.top.findNode("calendarGroup")
    m.daysGroup = m.top.findNode("daysGroup")
    m.backgroundPoster = m.top.findNode("backgroundPoster")
    
    ' Overlay nodes
    m.loginOverlay = m.top.findNode("loginOverlay")
    m.loginTitle = m.top.findNode("loginTitle")
    m.loginUrl = m.top.findNode("loginUrl")
    m.loginCode = m.top.findNode("loginCode")
    
    ' Data storage
    m.googleEvents = {}
    m.bgRects = []
    m.dayLabels = []
    m.evtLabels = []

    if m.daysGroup <> invalid then
        createCalendarGrid()
        setupCurrentMonth()
    end if

    ' Scaling
    deviceInfo = CreateObject("roDeviceInfo")
    screenW = deviceInfo.GetDisplaySize().w
    if screenW <= 0 then screenW = 1280
    scale = (screenW / 1920.0) * 1.1
    
    if m.calendarGroup <> invalid then
        m.calendarGroup.scale = [scale, scale]
        calendarWidth = 1460 * scale
        centerX = (screenW - calendarWidth) / 2
        m.calendarGroup.translation = [centerX, 110]
    end if
    
    ' Start background tasks after a delay
    m.authTimer = m.top.createChild("Timer")
    m.authTimer.duration = 1.0 ' 1 second delay
    m.authTimer.repeat = false
    m.authTimer.observeField("fire", "onAuthTimerFire")
    m.authTimer.control = "START"
end sub

sub onAuthTimerFire()
    startDropboxAuth()
    startGoogleAuth()
end sub

' --- Grid & Month ---
sub setupCurrentMonth()
    now = CreateObject("roDateTime")
    m.currentYear = now.GetYear()
    m.currentMonth = now.GetMonth()
    
    months = ["January", "February", "March", "April", "May", "June", 
              "July", "August", "September", "October", "November", "December"]
    
    monthLabel = m.top.findNode("monthLabel")
    if monthLabel <> invalid then
        monthLabel.text = months[m.currentMonth - 1] + " " + m.currentYear.toStr()
    end if
    
    firstOfMonthStr = m.currentYear.toStr() + "-"
    if m.currentMonth < 10 then firstOfMonthStr += "0"
    firstOfMonthStr += m.currentMonth.toStr() + "-01T12:00:00Z"
    
    dt = CreateObject("roDateTime")
    dt.FromISO8601String(firstOfMonthStr)
    m.startDayIndex = dt.GetDayOfWeek() ' 0=Sun, 6=Sat (integer)
    if type(m.startDayIndex) <> "Integer" then m.startDayIndex = 0
    
    m.daysInMonth = 31
    if m.currentMonth = 4 or m.currentMonth = 6 or m.currentMonth = 9 or m.currentMonth = 11 then
        m.daysInMonth = 30
    else if m.currentMonth = 2 then
        m.daysInMonth = 28
        if (m.currentYear MOD 4 = 0 and m.currentYear MOD 100 <> 0) or (m.currentYear MOD 400 = 0) then m.daysInMonth = 29
    end if
    
    refreshUI()
end sub

sub createCalendarGrid()
    if m.daysGroup = invalid then return
    m.daysGroup.removeChildrenIndex(m.daysGroup.getChildCount(), 0)
    for i = 0 to 41
        col = i MOD 7
        row = i \ 7
        x = col * 210
        y = row * 130
        rect = m.daysGroup.createChild("Rectangle")
        rect.width = 200 : rect.height = 120 : rect.color = "#00000000" : rect.translation = [x, y]
        m.bgRects.push(rect)
        dayLbl = m.daysGroup.createChild("Label")
        dayLbl.translation = [x + 8, y + 10] : dayLbl.font = "font:MediumBoldSystemFont"
        m.dayLabels.push(dayLbl)
        evtLbl = m.daysGroup.createChild("Label")
        evtLbl.translation = [x, y + 30] : evtLbl.width = 192 : evtLbl.horizAlign = "right" : evtLbl.font = "font:SmallSystemFont"
        m.evtLabels.push(evtLbl)
    end for
end sub

sub refreshUI()
    allEvents = m.googleEvents
    
    ' Ensure startDayIndex is an integer for calculation
    startIdx = 0
    if type(m.startDayIndex) = "Integer" then
        startIdx = m.startDayIndex
    else if type(m.startDayIndex) = "String" then
        startIdx = m.startDayIndex.toInt()
    end if
    
    for i = 0 to 41
        if m.bgRects[i] <> invalid then m.bgRects[i].color = "#00000000"
        if m.dayLabels[i] <> invalid then m.dayLabels[i].text = ""
        if m.evtLabels[i] <> invalid then m.evtLabels[i].text = ""
    end for
    
    for day = 1 to m.daysInMonth
        idx = startIdx + day - 1
        if idx <= 41 then
            if m.bgRects[idx] <> invalid then m.bgRects[idx].color = "#3d3d7cff"
            if m.dayLabels[idx] <> invalid then m.dayLabels[idx].text = day.toStr()
            dayStr = day.toStr()
            if allEvents.doesExist(dayStr) and m.evtLabels[idx] <> invalid then 
                m.evtLabels[idx].text = allEvents[dayStr]
            end if
        end if
    end for
end sub

' --- Dropbox Auth ---
sub startDropboxAuth()
    m.dbTask = CreateObject("roSGNode", "DropboxTask")
    if m.dbTask <> invalid then
        m.dbTask.observeField("authResult", "onDBAuthResult")
        m.dbTask.observeField("status", "onDBStatusChange")
        m.dbTask.observeField("photoUrls", "onPhotoUrls")
        m.dbTask.status = "AUTHENTICATE"
        m.dbTask.control = "RUN"
    end if
end sub

sub onDBAuthResult()
    if m.dbTask = invalid then return
    res = m.dbTask.authResult
    if res <> invalid and res.user_code <> invalid and m.dbTask.status <> "SUCCESS" then
        showLoginOverlay("Dropbox (Photos)", res.verification_url, res.user_code)
    end if
end sub

sub onDBStatusChange()
    if m.dbTask = invalid then return
    if m.dbTask.status = "SUCCESS" then
        if m.loginOverlay <> invalid then m.loginOverlay.visible = false
        m.dbTask.status = "FETCH_PHOTOS"
        m.dbTask.control = "RUN"
        checkPendingLogins()
    end if
end sub

' --- Google Auth ---
sub startGoogleAuth()
    m.googleTask = CreateObject("roSGNode", "GoogleTask")
    if m.googleTask <> invalid then
        m.googleTask.observeField("authResult", "onGoogleAuthResult")
        m.googleTask.observeField("status", "onGoogleStatusChange")
        m.googleTask.observeField("calendarData", "onGoogleCalendarData")
        m.googleTask.status = "AUTHENTICATE"
        m.googleTask.control = "RUN"
    end if
end sub

sub onGoogleAuthResult()
    checkPendingLogins()
end sub

sub checkPendingLogins()
    if m.dbTask <> invalid and m.dbTask.status = "AUTHENTICATE" and m.loginOverlay <> invalid and m.loginOverlay.visible then return

    if m.googleTask <> invalid and m.googleTask.status = "AUTHENTICATE" then
        res = m.googleTask.authResult
        if res <> invalid and res.user_code <> invalid then
            showLoginOverlay("Google Calendar", res.verification_url, res.user_code)
        end if
    end if
end sub

sub onGoogleStatusChange()
    if m.googleTask = invalid then return
    if m.googleTask.status = "SUCCESS" then
        if m.loginOverlay <> invalid then m.loginOverlay.visible = false
        m.googleTask.status = "FETCH_CALENDAR"
        m.googleTask.control = "RUN"
    end if
end sub

sub onGoogleCalendarData()
    if m.googleTask <> invalid and m.googleTask.calendarData <> invalid then
        m.googleEvents = m.googleTask.calendarData
        refreshUI()
    end if
end sub

' --- Overlay UI ---
sub showLoginOverlay(title as string, url as string, code as string)
    if m.loginTitle <> invalid then m.loginTitle.text = "Login to " + title
    if m.loginUrl <> invalid then m.loginUrl.text = "Visit: " + url
    if m.loginCode <> invalid then m.loginCode.text = code
    if m.loginOverlay <> invalid then m.loginOverlay.visible = true
end sub

sub onPhotoUrls()
    if m.dbTask <> invalid and m.dbTask.photoUrls <> invalid and m.dbTask.photoUrls.count() > 0 then
        m.photoUrls = m.dbTask.photoUrls
        m.photoIndex = 0
        if m.slideshowTimer = invalid then
            m.slideshowTimer = m.top.createChild("Timer")
            m.slideshowTimer.repeat = true : m.slideshowTimer.duration = 30
            m.slideshowTimer.observeField("fire", "nextPhoto")
        end if
        m.slideshowTimer.control = "START"
        nextPhoto()
    end if
end sub

sub nextPhoto()
    if m.photoUrls <> invalid and m.photoUrls.count() > 0 and m.backgroundPoster <> invalid then
        m.backgroundPoster.uri = m.photoUrls[m.photoIndex]
        m.photoIndex = (m.photoIndex + 1) MOD m.photoUrls.count()
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press and key = "back" and m.loginOverlay <> invalid and m.loginOverlay.visible then
        m.loginOverlay.visible = false
        return true
    end if
    return false
end function
