sub init()
    m.top.functionName = "runTask"
    cfg = GetConfig()
    m.clientId = cfg.google.clientId
    m.clientSecret = cfg.google.clientSecret
end sub

sub runTask()
    hasTokens = loadSavedTokens()
    m.port = CreateObject("roMessagePort")
    m.top.observeField("status", m.port)
    
    if hasTokens then
        print "[GoogleTask] Tokens found on startup, setting status SUCCESS"
        m.top.status = "SUCCESS"
    else
        print "[GoogleTask] No tokens found on startup, starting AUTHENTICATE"
        handleStatus(m.top.status)
    end if

    while true
        ' Use 1 second timeout to avoid busy-wait
        msg = wait(1000, m.port)
        if type(msg) = "roSGNodeEvent" then
            if msg.getField() = "status" then
                handleStatus(msg.getData())
            end if
        else if msg = invalid then
            ' Occasional sleep to give other threads time
            sleep(100)
        end if
    end while
end sub

sub handleStatus(status as string)
    print "[GoogleTask] Handle Status: "; status
    if status = "AUTHENTICATE" then
        getDeviceCode()
    else if status = "FETCH_CALENDAR" or status = "REFRESH_CALENDAR" then
        if not refreshAccessToken() then
            print "[GoogleTask] Refresh failed, re-authenticating"
            m.top.status = "AUTHENTICATE"
        else
            fetchGoogleCalendar()
        end if
    end if
end sub

function loadSavedTokens() as boolean
    sec = CreateObject("roRegistrySection", "Authentication")
    if sec.Exists("google_refresh_token") then
        m.refreshToken = sec.Read("google_refresh_token")
        m.accessToken = sec.Read("google_access_token")
        return true
    end if
    return false
end function

sub saveTokens(json as object)
    sec = CreateObject("roRegistrySection", "Authentication")
    if json.refresh_token <> invalid then 
        m.refreshToken = json.refresh_token
        sec.Write("google_refresh_token", json.refresh_token)
        print "[GoogleTask] Saved new refresh token"
    end if
    if json.access_token <> invalid then 
        m.accessToken = json.access_token
        sec.Write("google_access_token", json.access_token)
        print "[GoogleTask] Saved new access token"
    end if
    sec.Flush()
end sub

function refreshAccessToken() as boolean
    if m.refreshToken = invalid then 
        print "[GoogleTask] No refresh token available"
        return false
    end if
    
    print "[GoogleTask] Refreshing access token..."
    url = "https://oauth2.googleapis.com/token"
    params = "client_id=" + m.clientId + "&client_secret=" + m.clientSecret + "&refresh_token=" + m.refreshToken + "&grant_type=refresh_token"
    
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.AddHeader("Content-Type", "application/x-www-form-urlencoded")
    
    port = CreateObject("roMessagePort")
    xfer.SetMessagePort(port)
    if xfer.AsyncPostFromString(params) then
        msg = wait(10000, port)
        if type(msg) = "roUrlEvent" then
            code = msg.GetResponseCode()
            print "[GoogleTask] Refresh response code: "; code
            if code = 200 then
                body = msg.GetString()
                if body <> "" then
                    json = ParseJson(body)
                    if json <> invalid and json.access_token <> invalid then
                        saveTokens(json)
                        return true
                    end if
                end if
            else
                print "[GoogleTask] Refresh Error: "; msg.GetString()
            end if
        end if
    end if
    return false
end function

sub getDeviceCode()
    print "[GoogleTask] Requesting device code..."
    url = "https://oauth2.googleapis.com/device/code"
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl(url)
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
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
                    print "[GoogleTask] Device code received: "; json.user_code
                    m.top.authResult = json
                    pollForToken(json.device_code, json.interval)
                end if
            end if
        else if type(msg) = "roUrlEvent" then
            print "[GoogleTask] Device code error: "; msg.GetResponseCode(); " : "; msg.GetString()
        end if
    end if
end sub

sub pollForToken(deviceCode as string, interval as integer)
    print "[GoogleTask] Polling for token..."
    url = "https://oauth2.googleapis.com/token"
    params = "client_id=" + m.clientId + "&client_secret=" + m.clientSecret + "&device_code=" + deviceCode + "&grant_type=urn:ietf:params:oauth:grant-type:device_code"
    while true
        xfer = CreateObject("roUrlTransfer")
        xfer.SetUrl(url)
        xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
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
                        print "[GoogleTask] Token received successfully"
                        saveTokens(json)
                        m.top.status = "SUCCESS"
                        return
                    else if json <> invalid and json.error <> "authorization_pending" then
                        print "[GoogleTask] Token polling error: "; json.error
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
        print "[GoogleTask] No access token for fetch"
        m.top.status = "GOOG_FETCH_NO_TOKEN"
        return
    end if
    
    print "[GoogleTask] Fetching calendar list..."
    xfer = CreateObject("roUrlTransfer")
    xfer.SetUrl("https://www.googleapis.com/calendar/v3/users/me/calendarList")
    xfer.SetCertificatesFile("common:/certs/ca-bundle.crt")
    xfer.AddHeader("Authorization", "Bearer " + m.accessToken)
    
    resp = xfer.GetToString()
    if resp = "" then 
        print "[GoogleTask] Empty response from calendar list"
        m.top.status = "GOOG_FETCH_ERR_EMPTY_LIST"
        return
    end if
    jsonList = ParseJson(resp)
    if jsonList = invalid or jsonList.items = invalid then 
        print "[GoogleTask] Failed to parse calendar list or items missing. Resp: "; resp
        m.top.status = "GOOG_FETCH_ERR_PARSE_LIST"
        return
    end if
    
    now = CreateObject("roDateTime")
    now.ToLocalTime()
    thisMonth = now.GetMonth()
    thisYear = now.GetYear()
    
    monthStr = (thisMonth).ToStr()
    if thisMonth < 10 then
        monthStr = "0" + monthStr
    end if
    timeMin = (thisYear).ToStr() + "-" + monthStr + "-01T00:00:00Z"
    
    nextMonth = thisMonth + 1
    nextYear = thisYear
    if nextMonth > 12 then
        nextMonth = 1
        nextYear = nextYear + 1
    end if
    nextMonthStr = (nextMonth).ToStr()
    if nextMonth < 10 then
        nextMonthStr = "0" + nextMonthStr
    end if
    timeMax = (nextYear).ToStr() + "-" + nextMonthStr + "-01T00:00:00Z"
    
    print "[GoogleTask] Fetching events for local month: "; thisMonth; " Year: "; thisYear
    print "[GoogleTask] Range: "; timeMin; " to "; timeMax
    allEventsAA = {}
    seenEvents = {} ' Tracking AA for global/day deduplication
    
    for each cal in jsonList.items
        calName = cal.summary
        print "[GoogleTask] Fetching calendar: "; calName
        url = "https://www.googleapis.com/calendar/v3/calendars/" + xfer.UrlEncode(cal.id) + "/events"
        url += "?timeMin=" + timeMin + "&timeMax=" + timeMax + "&singleEvents=true&orderBy=startTime&maxResults=100"
        xfer.SetUrl(url)
        eventResp = xfer.GetToString()
        if eventResp <> "" then
            eventsJson = ParseJson(eventResp)
            if eventsJson <> invalid and eventsJson.items <> invalid then
                for each item in eventsJson.items
                    summary = item.summary
                    if summary = invalid or summary = "" then
                        summary = "(No Title)"
                    end if
                    isAllDay = false
                    dayNum = invalid
                    eventHour = 0
                    eventMin = 0
                    
                    if item.start <> invalid and item.start.dateTime <> invalid then
                        dt = CreateObject("roDateTime")
                        dt.FromISO8601String(item.start.dateTime)
                        dt.ToLocalTime()
                        if dt.GetMonth() = thisMonth and dt.GetYear() = thisYear then
                            dayNum = (dt.GetDayOfMonth()).ToStr()
                            eventHour = dt.GetHours()
                            eventMin = dt.GetMinutes()
                        end if
                    else if item.start <> invalid and item.start.date <> invalid then
                        isAllDay = true
                        dateParts = item.start.date.split("-")
                        if dateParts.count() = 3 then
                            if (dateParts[0]).toInt() = thisYear and (dateParts[1]).toInt() = thisMonth then
                                dayNum = ((dateParts[2]).toInt()).ToStr()
                            end if
                        end if
                    end if
                    
                    if dayNum <> invalid then
                        isAllDayStr = "f"
                        if isAllDay then
                            isAllDayStr = "t"
                        end if
                        dedupeKey = dayNum + "|" + summary + "|" + isAllDayStr
                        if isAllDay = false then
                            dedupeKey = dedupeKey + "|" + (eventHour).ToStr() + "|" + (eventMin).ToStr()
                        end if
                        
                        if not seenEvents.doesExist(dedupeKey) then
                            eventObj = {
                                summary: summary,
                                hour: eventHour,
                                minute: eventMin,
                                isAllDay: isAllDay
                            }
                            if not allEventsAA.doesExist(dayNum) then
                                allEventsAA[dayNum] = []
                            end if
                            allEventsAA[dayNum].push(eventObj)
                            seenEvents[dedupeKey] = true
                        end if
                    end if
                end for
            end if
        end if
    end for
    
    for each dayKey in allEventsAA
        allEventsAA[dayKey].sortBy("hour")
    end for
    
    print "[GoogleTask] Fetch complete. updating calendarData field."
    m.top.calendarData = allEventsAA
    m.top.status = "GOOG_FETCH_OK"
end sub
