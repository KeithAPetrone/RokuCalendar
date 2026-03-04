sub init()
    m.top.functionName = "runTask"
    cfg = GetConfig()
    m.clientId = cfg.google.clientId
    m.clientSecret = cfg.google.clientSecret
end sub

sub runTask()
    loadSavedTokens()
    m.port = CreateObject("roMessagePort")
    m.top.observeField("status", m.port)
    handleStatus(m.top.status)
    while true
        msg = wait(0, m.port)
        if type(msg) = "roSGNodeEvent" and msg.getField() = "status" then
            handleStatus(msg.getData())
        end if
    end while
end sub

sub handleStatus(status as string)
    if status = "AUTHENTICATE" then
        getDeviceCode()
    else if status = "FETCH_CALENDAR" then
        fetchGoogleCalendar()
    end if
end sub

function loadSavedTokens() as boolean
    sec = CreateObject("roRegistrySection", "Authentication")
    if sec.Exists("google_refresh_token") then
        m.refreshToken = sec.Read("google_refresh_token")
        m.accessToken = sec.Read("google_access_token")
        m.top.status = "SUCCESS"
        return true
    end if
    return false
end function

sub saveTokens(json as object)
    sec = CreateObject("roRegistrySection", "Authentication")
    if json.refresh_token <> invalid then 
        m.refreshToken = json.refresh_token
        sec.Write("google_refresh_token", json.refresh_token)
    end if
    if json.access_token <> invalid then 
        m.accessToken = json.access_token
        sec.Write("google_access_token", json.access_token)
    end if
    sec.Flush()
end sub

sub getDeviceCode()
    url = "https://oauth2.googleapis.com/device/code"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url) : xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.AddHeader("Content-Type", "application/x-www-form-urlencoded")
    params = "client_id=" + m.clientId + "&scope=https://www.googleapis.com/auth/calendar.readonly"
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    if xfer.AsyncPostFromString(params) then
        msg = wait(10000, port)
        if type(msg) = "roUrlEvent" and msg.GetResponseCode() = 200 then
            body = msg.GetString()
            if body <> "" then
                json = ParseJson(body)
                if json <> invalid then
                    m.top.authResult = json
                    pollForToken(json.device_code, json.interval)
                end if
            end if
        end if
    end if
end sub

sub pollForToken(deviceCode as string, interval as integer)
    url = "https://oauth2.googleapis.com/token"
    params = "client_id=" + m.clientId + "&client_secret=" + m.clientSecret + "&device_code=" + deviceCode + "&grant_type=urn:ietf:params:oauth:grant-type:device_code"
    while true
        xfer = CreateObject("roUrlTransfer")
        xfer.SetUrl(url) : xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
        xfer.AddHeader("Content-Type", "application/x-www-form-urlencoded")
        port = CreateObject("roMessagePort")
        xfer.SetMessagePort(port)
        if xfer.AsyncPostFromString(params) then
            msg = wait(10000, port)
            if type(msg) = "roUrlEvent" then
                code = msg.GetResponseCode()
                body = msg.GetString()
                if body <> "" then
                    json = ParseJson(body)
                    if code = 200 and json <> invalid and json.access_token <> invalid then
                        saveTokens(json)
                        m.top.status = "SUCCESS"
                        return
                    else if json <> invalid and json.error <> "authorization_pending" then
                        m.top.status = "GOOG_TOKEN_ERR_" + json.error
                        return
                    end if
                end if
            end if
        end if
        sleep(interval * 1000)
    end while
end sub

sub fetchGoogleCalendar()
    if m.accessToken = invalid then 
        m.top.status = "GOOG_FETCH_NO_TOKEN"
        return
    end if
    
    ' 1. Get List of all calendars
    calListUrl = "https://www.googleapis.com/calendar/v3/users/me/calendarList"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(calListUrl) : xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.AddHeader("Authorization", "Bearer " + m.accessToken)
    
    resp = xfer.GetToString()
    if resp = "" then return
    
    jsonList = ParseJson(resp)
    if jsonList = invalid or jsonList.items = invalid then return
    
    ' 2. Fetch events for EVERY calendar
    now = CreateObject("roDateTime")
    thisMonth = now.GetMonth()
    monthStr = thisMonth.toStr()
    if thisMonth < 10 then monthStr = "0" + monthStr
    timeMin = now.GetYear().toStr() + "-" + monthStr + "-01T00:00:00Z"
    
    allEventsAA = {}
    
    for each cal in jsonList.items
        calId = cal.id
        url = "https://www.googleapis.com/calendar/v3/calendars/" + xfer.UrlEncode(calId) + "/events"
        url += "?timeMin=" + timeMin + "&singleEvents=true&orderBy=startTime&maxResults=50"
        
        xfer.SetUrl(url)
        eventResp = xfer.GetToString()
        if eventResp <> "" then
            eventsJson = ParseJson(eventResp)
            if eventsJson <> invalid and eventsJson.items <> invalid then
                for each item in eventsJson.items
                    dayPart = invalid
                    if item.start <> invalid and item.start.date <> invalid then
                        dayPart = item.start.date
                    else if item.start <> invalid and item.start.dateTime <> invalid then
                        dayPart = item.start.dateTime.split("T")[0]
                    end if
                    
                    if dayPart <> invalid then
                        daySegs = dayPart.split("-")
                        if daySegs.count() >= 3 and Val(daySegs[1]) = thisMonth then
                            dayNum = Val(daySegs[2]).toStr()
                            ' Merge multiple events with commas
                            if allEventsAA.doesExist(dayNum) then
                                allEventsAA[dayNum] += ", " + item.summary
                            else
                                allEventsAA[dayNum] = item.summary
                            end if
                        end if
                    end if
                end for
            end if
        end if
    next
    
    m.top.calendarData = allEventsAA
    m.top.status = "GOOG_FETCH_OK"
end sub
