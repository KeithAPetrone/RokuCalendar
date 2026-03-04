sub init()
    m.top.setFocus(true)
    m.calendarGroup = m.top.findNode("calendarGroup")
    m.daysGroup = m.top.findNode("daysGroup")
    m.backgroundPoster = m.top.findNode("backgroundPoster")
    m.statusLabel = m.top.findNode("statusLabel")
    m.loginOverlay = m.top.findNode("loginOverlay")
    m.loginTitle = m.top.findNode("loginTitle")
    m.loginUrl = m.top.findNode("loginUrl")
    m.loginCode = m.top.findNode("loginCode")
    m.googleEvents = {}
    m.bgRects = []
    m.dayLabels = []
    m.evtLabels = []
    m.photoPaths = [] ' To store the list of filenames
    m.photoIndex = 0
    if m.daysGroup <> invalid then
        createCalendarGrid()
        setupCurrentMonth()
    end if
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
    m.authTimer = m.top.createChild("Timer")
    m.authTimer.duration = 1.0 : m.authTimer.repeat = false
    m.authTimer.observeField("fire", "onAuthTimerFire")
    m.authTimer.control = "START"
end sub

sub onAuthTimerFire()
    startDropboxAuth()
    startGoogleAuth()
end sub

sub setupCurrentMonth()
    now = CreateObject("roDateTime")
    now.ToLocalTime()
    m.currentYear = now.GetYear()
    m.currentMonth = now.GetMonth()
    months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    m.top.findNode("monthLabel").text = months[m.currentMonth - 1] + " " + m.currentYear.toStr()
    
    monthPadding = ""
    if m.currentMonth < 10 then monthPadding = "0"
    firstOfMonthStr = m.currentYear.toStr() + "-" + monthPadding + m.currentMonth.toStr() + "-01T12:00:00Z"
    
    dt = CreateObject("roDateTime")
    dt.FromISO8601String(firstOfMonthStr)
    dt.ToLocalTime()
    if dt.GetMonth() <> m.currentMonth then
        if m.currentMonth < 10 then monthPadding = "0"
        dt = CreateObject("roDateTime")
        dt.FromISO8601String(m.currentYear.toStr() + "-" + monthPadding + m.currentMonth.toStr() + "-01T20:00:00Z")
        dt.ToLocalTime()
    end if
    m.startDayIndex = fix(dt.GetDayOfWeek())
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
    m.daysGroup.removeChildrenIndex(m.daysGroup.getChildCount(), 0)
    for i = 0 to 41
        col = i MOD 7 : row = i \ 7 : x = col * 210 : y = row * 130
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
    startIdx = 0
    if type(m.startDayIndex) = "Integer" then
        startIdx = m.startDayIndex
    end if
    for i = 0 to 41
        m.bgRects[i].color = "#00000000" : m.dayLabels[i].text = "" : m.evtLabels[i].text = ""
    end for
    for day = 1 to m.daysInMonth
        idx = startIdx + day - 1
        if idx >= 0 and idx <= 41 then
            m.bgRects[idx].color = "#3d3d7cff" : m.dayLabels[idx].text = day.toStr()
            dayStr = day.toStr()
            if allEvents.doesExist(dayStr) then m.evtLabels[idx].text = allEvents[dayStr]
        end if
    end for
end sub

sub startDropboxAuth()
    m.dbTask = CreateObject("roSGNode", "DropboxTask")
    m.dbTask.observeField("authResult", "onDBAuthResult")
    m.dbTask.observeField("status", "onDBStatusChange")
    m.dbTask.observeField("photoUrls", "onPhotoUrls")
    m.dbTask.status = "AUTHENTICATE"
    m.dbTask.control = "RUN"
end sub

sub onDBAuthResult()
    res = m.dbTask.authResult
    if res <> invalid and res.user_code <> invalid and m.dbTask.status <> "SUCCESS" then
        showLoginOverlay("Dropbox (Photos)", res.verification_url, res.user_code)
    end if
end sub

sub onDBStatusChange()
    if m.statusLabel <> invalid then m.statusLabel.text = "DB: " + m.dbTask.status
    if m.dbTask.status = "SUCCESS" then
        if m.loginOverlay <> invalid then m.loginOverlay.visible = false
        m.dbTask.status = "FETCH_PHOTOS"
        checkPendingLogins()
    end if
end sub

sub startGoogleAuth()
    m.googleTask = CreateObject("roSGNode", "GoogleTask")
    m.googleTask.observeField("authResult", "onGoogleAuthResult")
    m.googleTask.observeField("status", "onGoogleStatusChange")
    m.googleTask.observeField("calendarData", "onGoogleCalendarData")
    m.googleTask.status = "AUTHENTICATE"
    m.googleTask.control = "RUN"
end sub

sub onGoogleAuthResult()
    checkPendingLogins()
end sub

sub checkPendingLogins()
    if m.dbTask <> invalid and m.dbTask.status = "AUTHENTICATE" and m.loginOverlay.visible then return
    if m.googleTask <> invalid and m.googleTask.status = "AUTHENTICATE" then
        res = m.googleTask.authResult
        if res <> invalid and res.user_code <> invalid then
            showLoginOverlay("Google Calendar", res.verification_url, res.user_code)
        end if
    end if
end sub

sub onGoogleStatusChange()
    if m.statusLabel <> invalid then m.statusLabel.text = "GOOG: " + m.googleTask.status
    if m.googleTask.status = "SUCCESS" then
        if m.loginOverlay <> invalid then m.loginOverlay.visible = false
        m.googleTask.status = "FETCH_CALENDAR"
    end if
end sub

sub onGoogleCalendarData()
    if m.googleTask <> invalid and m.googleTask.calendarData <> invalid then
        m.googleEvents = m.googleTask.calendarData
        refreshUI()
    end if
end sub

sub showLoginOverlay(title as string, url as string, code as string)
    m.loginTitle.text = "Login to " + title : m.loginUrl.text = "Visit: " + url : m.loginCode.text = code : m.loginOverlay.visible = true
end sub

sub onPhotoUrls()
    ' If status was a "List OK" status, then these are PATHS
    if m.dbTask.status.instr("DB_LIST_OK") >= 0 then
        m.photoPaths = m.dbTask.photoUrls
        m.photoIndex = 0
        if m.slideshowTimer = invalid then
            m.slideshowTimer = m.top.createChild("Timer")
            m.slideshowTimer.repeat = true : m.slideshowTimer.duration = 30
            m.slideshowTimer.observeField("fire", "nextPhoto")
        end if
        m.slideshowTimer.control = "START"
        nextPhoto()
    ' If status was "Link Ready", then this is a single URL to show
    else if m.dbTask.status = "DB_LINK_READY" then
        if m.dbTask.photoUrls.count() > 0 then
            m.backgroundPoster.uri = m.dbTask.photoUrls[0]
        end if
    end if
end sub

sub nextPhoto()
    if m.photoPaths.count() > 0 then
        path = m.photoPaths[m.photoIndex]
        m.photoIndex = (m.photoIndex + 1) MOD m.photoPaths.count()
        ' Request a fresh link for this path
        m.dbTask.status = "GET_LINK_FOR|" + path
    end if
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if press and key = "back" and m.loginOverlay.visible then
        m.loginOverlay.visible = false : return true
    end if
    return false
end function
